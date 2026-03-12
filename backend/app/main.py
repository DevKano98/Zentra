import asyncio
import base64
import json
import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.config import settings
from app.database.supabase_client import supabase
from app.ml.classifier import _load_models
from app.routes.call_routes import router as call_router
from app.routes.dashboard_routes import router as dashboard_router
from app.routes.integration_routes import router as integration_router
from app.routes.report_routes import router as report_router
from app.routes.user_routes import router as user_router
from app.services.deepgram_service import SarvamStreamingSession
from app.services.gemini_service import build_system_prompt, generate_response, parse_signals
from app.services.notification_service import _firebase_initialized
from app.services.tts_service import synthesize

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s — %(name)s — %(levelname)s — %(message)s",
)
logger = logging.getLogger(__name__)

_dashboard_connections: list[WebSocket] = []


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Zentra backend...")

    try:
        response = supabase.table("call_records").select("id").limit(1).execute()
        logger.info("Supabase connection verified")
    except Exception as e:
        logger.error(f"Supabase connection failed: {e}")

    _load_models()
    logger.info("ML models loaded")

    if _firebase_initialized:
        logger.info("Firebase FCM initialized")
    else:
        logger.warning("Firebase FCM not initialized")

    # ── Keep-alive self-ping for Render free tier ────────────────────────────
    # Render spins down the service after 15 min of inactivity. Pinging our own
    # /health endpoint every 14 min keeps it awake at zero cost.
    # Set RENDER_EXTERNAL_URL in Render env vars (it's set automatically).
    async def _keep_alive():
        url = os.environ.get("RENDER_EXTERNAL_URL", "").rstrip("/")
        if not url:
            logger.info("Keep-alive: RENDER_EXTERNAL_URL not set — skipping (local dev)")
            return
        ping_url = f"{url}/health"
        logger.info(f"Keep-alive ping started → {ping_url} every 14 min")
        while True:
            await asyncio.sleep(14 * 60)   # 14 minutes
            try:
                import httpx
                async with httpx.AsyncClient(timeout=10) as client:
                    r = await client.get(ping_url)
                    logger.info(f"Keep-alive ping: {r.status_code}")
            except Exception as e:
                logger.warning(f"Keep-alive ping failed: {e}")

    keep_alive_task = asyncio.create_task(_keep_alive())
    # ─────────────────────────────────────────────────────────────────────────

    yield

    keep_alive_task.cancel()
    logger.info("Shutting down Zentra backend")


limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="Zentra API",
    description="AI-powered call screening backend for Android",
    version="1.0.0",
    lifespan=lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(call_router)
app.include_router(user_router)
app.include_router(report_router)
app.include_router(dashboard_router)
app.include_router(integration_router)


@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


@app.websocket("/ws/call/{call_id}")
async def websocket_call(websocket: WebSocket, call_id: str):
    await websocket.accept()
    logger.info(f"WebSocket call connected: {call_id}")

    conversation_history = []
    
    user_prefs = {
        "user_name": "User",
        "user_city": "India",
        "ai_language": "hindi",
        "ai_voice_gender": "female",
        "urgency_threshold": 5,
    }

    try:
        init_msg = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        if init_msg.get("type") == "init":
            user_prefs.update({
                "user_name": init_msg.get("user_name", "User"),
                "user_city": init_msg.get("user_city", "India"),
                "ai_language": init_msg.get("ai_language", "hindi"),
                "ai_voice_gender": init_msg.get("ai_voice_gender", "female"),
                "urgency_threshold": init_msg.get("urgency_threshold", 5),
            })
    except asyncio.TimeoutError:
        pass
    except Exception as e:
        logger.warning(f"Init message error: {e}")

    # Build prompt and greeting
    system_prompt = build_system_prompt(
        user_name=user_prefs["user_name"],
        user_city=user_prefs["user_city"],
        urgency_threshold=user_prefs["urgency_threshold"],
        ai_language=user_prefs["ai_language"],
        ai_voice_gender=user_prefs["ai_voice_gender"],
    )

    # Initial greeting logic
    ai_name = "Divya" if user_prefs["ai_voice_gender"] == "female" else "Rohan"
    gender_phrase = "bol rahi hoon" if user_prefs["ai_voice_gender"] == "female" else "bol raha hoon"
    greeting_text = f"Namaste, main {ai_name} hoon, {user_prefs['user_name']} ki taraf se {gender_phrase}. Main aapki kya madad kar sakti hoon?"
    
    async def process_and_respond(transcript_turn: str):
        conversation_history.append(
            {"role": "user", "parts": [{"text": transcript_turn}]}
        )

        try:
            ai_text = generate_response(
                history=conversation_history,
                system_prompt=system_prompt,
            )
            signals = parse_signals(ai_text)

            conversation_history.append(
                {"role": "model", "parts": [{"text": signals["clean_response"]}]}
            )

            tts_audio = synthesize(
                signals["clean_response"],
                language=user_prefs["ai_language"],
                gender=user_prefs["ai_voice_gender"],
            )
            audio_b64 = base64.b64encode(tts_audio).decode() if tts_audio else ""

            response_payload = {
                "type": "ai_response",
                "text": signals["clean_response"],
                "audio_b64": audio_b64,
                "urgency": signals["urgency"],
                "category": signals["category"],
                "action": signals["action"],
            }
            await websocket.send_json(response_payload)

            if signals["action"] in ("BLOCK_OTP", "BLOCK_SCAM"):
                await _broadcast_scam_event(
                    {
                        "call_id": call_id,
                        "category": signals["category"],
                        "urgency": signals["urgency"],
                        "action": signals["action"],
                    }
                )

            if signals["action"] in ("BLOCK_OTP", "BLOCK_SCAM", "END_CALL"):
                await websocket.send_json({"type": "call_end", "reason": signals["action"]})
                # Note: We don't close the connection here yet to allow final audio packets
        except Exception as e:
            logger.error(f"Error processing AI response for {call_id}: {e}")

    async def on_transcript(text: str):
        logger.info(f"Transcript received: {text}")
        # Process each transcript turn in its own task to avoid blocking the audio stream
        asyncio.create_task(process_and_respond(text))

    stt_session = SarvamStreamingSession(on_transcript_callback=on_transcript)
    await stt_session.start()

    # Send initial greeting
    asyncio.create_task(process_and_respond(f"[SYSTEM: This is your first turn. Introduce yourself as {ai_name} and greet the caller with: {greeting_text}]"))

    try:
        while True:
            message = await websocket.receive()

            if "bytes" in message and message["bytes"]:
                audio_chunk = message["bytes"]
                await stt_session.send_audio(audio_chunk)

            elif "text" in message:
                try:
                    text_msg = json.loads(message["text"])
                    if text_msg.get("type") == "ping":
                        await websocket.send_json({"type": "pong"})
                except json.JSONDecodeError:
                    pass

    except WebSocketDisconnect:
        logger.info(f"WebSocket call disconnected: {call_id}")
    except Exception as e:
        logger.error(f"WebSocket call error for {call_id}: {e}")
    finally:
        await stt_session.stop()
        logger.info(f"WebSocket call session ended: {call_id}")


@app.websocket("/ws/dashboard")
async def websocket_dashboard(websocket: WebSocket):
    await websocket.accept()
    _dashboard_connections.append(websocket)
    logger.info(f"Dashboard WebSocket connected. Total: {len(_dashboard_connections)}")

    try:
        while True:
            await asyncio.sleep(30)
            await websocket.send_json({"type": "ping"})
    except WebSocketDisconnect:
        logger.info("Dashboard WebSocket disconnected")
    except Exception as e:
        logger.error(f"Dashboard WebSocket error: {e}")
    finally:
        if websocket in _dashboard_connections:
            _dashboard_connections.remove(websocket)


async def _broadcast_scam_event(event_data: dict):
    if not _dashboard_connections:
        return

    dead = []
    for ws in _dashboard_connections:
        try:
            await ws.send_json({"type": "scam_event", "data": event_data})
        except Exception:
            dead.append(ws)

    for ws in dead:
        if ws in _dashboard_connections:
            _dashboard_connections.remove(ws)