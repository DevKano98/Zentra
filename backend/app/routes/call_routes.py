import asyncio
import base64
import hashlib
import logging
import re
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Request, Query
from fastapi import Depends
from pydantic import BaseModel
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.database.queries import (
    get_call_history,
    get_recent_calls,
    get_user_by_id,
    save_call_record,
    check_scam_db,
    add_to_scam_db,
)
from app.database.supabase_storage import upload_audio, upload_pdf
from app.ml.classifier import classify_call
from app.ml.emotion_detector import detect_emotion
from app.ml.scam_detector import detect_scam_keywords, detect_otp_request
from app.services.blockchain_service import hash_call_record, write_to_blockchain
from app.services.fir_service import generate_fir_pdf
from app.services.gemini_service import (
    build_system_prompt,
    generate_response,
    parse_signals,
    summarize_call,
)
from app.services.notification_service import (
    send_fcm_notification,
    send_scam_alert_telegram,
    send_call_summary_telegram,
)
from app.services.tts_service import synthesize

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/calls", tags=["calls"])
limiter = Limiter(key_func=get_remote_address)


class ProcessTurnRequest(BaseModel):
    user_id: str
    call_id: str
    caller_number: str
    transcript_turn: str
    conversation_history: list = []
    active_orders: list = []


class SaveRecordRequest(BaseModel):
    user_id: str
    call_id: str
    caller_number: str
    transcript: str
    duration_seconds: int = 0
    lat: Optional[float] = None
    lng: Optional[float] = None
    audio_bytes_b64: Optional[str] = None
    final_action: Optional[str] = None
    final_category: Optional[str] = "UNKNOWN"
    final_urgency: Optional[int] = 5


class ReportScamRequest(BaseModel):
    caller_number: str
    category: str = "SCAM"
    reported_by: Optional[str] = None


def _hash_phone(phone: str) -> str:
    return hashlib.sha256(phone.encode()).hexdigest()


def _extract_caller_name(transcript: str) -> Optional[str]:
    if not transcript:
        return None
    patterns = [
        r"(?:my name is|main|mera naam|i am|i'm)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)",
        r"(?:speaking with|this is)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)",
        r"(?:yahan se|yah)\s+([A-Za-z]+)\s+bol raha",
    ]
    for pattern in patterns:
        match = re.search(pattern, transcript, re.IGNORECASE)
        if match:
            return match.group(1).strip()
    return None


def _action_to_outcome(action: Optional[str]) -> str:
    mapping = {
        "BLOCK_OTP": "BLOCKED",
        "BLOCK_SCAM": "BLOCKED",
        "END_CALL": "COMPLETED",
        "TRANSFER": "TRANSFERRED",
        "DISMISS": "DISMISSED",
    }
    return mapping.get(action, "COMPLETED")


@router.post("/process-turn")
@limiter.limit("10/minute")
async def process_turn(request: Request, body: ProcessTurnRequest):
    user = get_user_by_id(body.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    prefs = user.get("preferences", {})
    user_name = user.get("name", "User")
    user_city = user.get("city", "India")
    ai_language = prefs.get("ai_language", "hindi")
    ai_voice_gender = prefs.get("ai_voice_gender", "female")
    urgency_threshold = prefs.get("urgency_threshold", 5)

    is_otp_request = detect_otp_request(body.transcript_turn)
    if is_otp_request:
        tts_audio = synthesize(
            "Maafi chahta/chahti hoon, main aapko koi bhi OTP ya sensitive information share nahi kar sakta/sakti.",
            language=ai_language,
            gender=ai_voice_gender,
        )
        audio_b64 = base64.b64encode(tts_audio).decode() if tts_audio else ""
        return {
            "ai_response": "I cannot share any OTP or sensitive information.",
            "ai_audio_b64": audio_b64,
            "urgency": 10,
            "category": "SCAM",
            "action": "BLOCK_OTP",
            "scam_matches": [],
        }

    scam_result = detect_scam_keywords(body.transcript_turn)

    phone_hash = _hash_phone(body.caller_number)
    known_scam = check_scam_db(phone_hash)

    system_prompt = build_system_prompt(
        user_name=user_name,
        user_city=user_city,
        urgency_threshold=urgency_threshold,
        ai_language=ai_language,
        ai_voice_gender=ai_voice_gender,
        active_orders=body.active_orders,
    )

    history = body.conversation_history + [
        {"role": "user", "parts": [{"text": body.transcript_turn}]}
    ]

    ai_text = generate_response(history=history, system_prompt=system_prompt)
    signals = parse_signals(ai_text)

    if scam_result["is_scam"] or known_scam["is_known_scam"]:
        signals["category"] = "SCAM"
        signals["urgency"] = max(signals["urgency"], 8)
        if not signals["action"]:
            signals["action"] = "BLOCK_SCAM"

    tts_text = signals["clean_response"] or ai_text
    tts_audio = synthesize(tts_text, language=ai_language, gender=ai_voice_gender)
    audio_b64 = base64.b64encode(tts_audio).decode() if tts_audio else ""

    return {
        "ai_response": signals["clean_response"],
        "ai_audio_b64": audio_b64,
        "urgency": signals["urgency"],
        "category": signals["category"],
        "action": signals["action"],
        "scam_matches": scam_result["matched_phrases"],
    }


@router.post("/save-record")
async def save_record(body: SaveRecordRequest):
    summary = ""
    tx_hash = ""
    
    try:
        summary = await summarize_call(body.transcript)
    except Exception as e:
        logger.warning(f"Summarize failed: {e}")

    phone_hash = _hash_phone(body.caller_number)
    caller_name = _extract_caller_name(body.transcript)
    call_outcome = _action_to_outcome(body.final_action)

    call_data = {
        "app_call_id": body.call_id,  # Store timestamp as text
        "caller_number": body.caller_number,
        "caller_number_hash": phone_hash,
        "caller_name": caller_name,
        "category": body.final_category or "UNKNOWN",
        "urgency_score": body.final_urgency or 5,
        "call_outcome": call_outcome,
        "transcript": body.transcript,
        "summary": summary,
        "duration_seconds": body.duration_seconds,
        "lat": body.lat,
        "lng": body.lng,
        "created_at": datetime.utcnow().isoformat(),
    }

    if body.audio_bytes_b64:
        try:
            audio_bytes = base64.b64decode(body.audio_bytes_b64)
            audio_path = upload_audio(body.call_id, audio_bytes)
            call_data["audio_path"] = audio_path
        except Exception as e:
            logger.error(f"Audio upload failed: {e}")

    is_scam = body.final_category == "SCAM" or body.final_action in ("BLOCK_SCAM", "BLOCK_OTP")
    timestamp = call_data["created_at"]
    call_hash = hash_call_record(body.transcript, body.caller_number, timestamp, body.final_category or "UNKNOWN")

    try:
        tx_hash = await write_to_blockchain(
            call_hash=call_hash,
            user_id=body.user_id,
            category=body.final_category or "UNKNOWN",
            is_scam=is_scam,
        )
    except Exception as e:
        logger.warning(f"Blockchain failed: {e}")
    
    call_data["blockchain_tx_hash"] = tx_hash

    if is_scam:
        add_to_scam_db(phone_hash, body.final_category or "SCAM")
        try:
            pdf_bytes = await generate_fir_pdf(call_data)
            fir_url = upload_pdf(body.call_id, pdf_bytes)
            call_data["fir_pdf_url"] = fir_url
        except Exception as e:
            logger.error(f"FIR generation failed: {e}")

    try:
        save_call_record(body.user_id, call_data)
    except Exception as e:
        logger.error(f"Supabase save failed: {e}")

    try:
        user = get_user_by_id(body.user_id)
        if user:
            fcm_token = user.get("fcm_token")
            telegram_chat_id = user.get("telegram_chat_id")

            if fcm_token:
                try:
                    asyncio.create_task(
                        send_fcm_notification(
                            fcm_token=fcm_token,
                            title="📞 Call Screened" if not is_scam else "🚨 Scam Call Blocked",
                            body=f"Category: {body.final_category} | Outcome: {call_outcome}",
                            data={"call_id": body.call_id, "category": body.final_category or ""},
                        )
                    )
                except Exception as e:
                    logger.warning(f"FCM notification failed: {e}")

            try:
                if telegram_chat_id and is_scam:
                    asyncio.create_task(send_scam_alert_telegram(telegram_chat_id, call_data))
                elif telegram_chat_id:
                    asyncio.create_task(send_call_summary_telegram(telegram_chat_id, call_data))
            except Exception as e:
                logger.warning(f"Telegram notification failed: {e}")
    except Exception as e:
        logger.warning(f"Post-save notifications failed: {e}")

    return {"status": "saved", "call_id": body.call_id, "blockchain_tx_hash": tx_hash}


@router.get("/history/{user_id}")
async def call_history(user_id: str, limit: int = 50, offset: int = 0):
    records = get_call_history(user_id, limit=limit)
    return {"calls": records, "total": len(records), "limit": limit, "offset": offset}


@router.get("/recent/{user_id}")
async def recent_calls(user_id: str):
    records = get_recent_calls(user_id, limit=5)
    return {"calls": records}



@router.get("/stats")
async def get_call_stats(user_id: Optional[str] = Query(None)):
    """Return total calls and scam count, optionally filtered by user_id."""
    try:
        from app.database.supabase_client import supabase

        query = supabase.table("call_records").select("id", count="exact")
        if user_id:
            query = query.eq("user_id", user_id)
        total = query.execute()

        scam_query = supabase.table("call_records").select("id", count="exact").eq("category", "SCAM")
        if user_id:
            scam_query = scam_query.eq("user_id", user_id)
        scam_result = scam_query.execute()

        return {
            "calls_today": total.count or 0,
            "scams_blocked": scam_result.count or 0,
        }
    except Exception as e:
        logger.warning(f"Stats query failed: {e}")
        return {"calls_today": 0, "scams_blocked": 0}


@router.post("/report-scam")
async def report_scam(body: ReportScamRequest):
    phone_hash = _hash_phone(body.caller_number)
    add_to_scam_db(phone_hash, body.category)
    return {"status": "reported", "phone_hash": phone_hash}