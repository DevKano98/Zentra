"""
backend/app/services/deepgram_service.py

Speech-to-text using Sarvam AI STT API via WebSocket Streaming.
"""

import asyncio
import logging
import traceback
from app.config import settings
from sarvamai import AsyncSarvamAI

logger = logging.getLogger(__name__)

# Note: The SDK requires base64 encoded strings for the audio parameter
import base64

class SarvamStreamingSession:
    """
    Real-time streaming STT using Sarvam's official saaras:v3 WebSocket API.
    """

    def __init__(self, on_transcript_callback):
        self.on_transcript = on_transcript_callback
        self._running = False
        self._client = AsyncSarvamAI(api_subscription_key=settings.SARVAM_API_KEY)
        self._ws = None
        self._receive_task = None
        self._ws_ready = asyncio.Event()

    async def start(self):
        self._running = True
        self._receive_task = asyncio.create_task(self._session_loop())
        logger.info("Sarvam WebSocket STT session starting...")

    async def _session_loop(self):
        """Main loop that holds the websocket context open."""
        try:
            async with self._client.speech_to_text_streaming.connect(
                model="saaras:v3",
                mode="transcribe",
                language_code="hi-IN",
                high_vad_sensitivity=True,
                vad_signals=True, # We will get speech_start and speech_end correctly
                sample_rate=16000
            ) as ws:
                self._ws = ws
                self._ws_ready.set()
                logger.info("Sarvam WebSocket connected")
                
                async for message in ws:
                    if not self._running:
                        break
                    
                    msg_type = message.get("type")
                    if msg_type == "transcript":
                        text = message.get("text", "").strip()
                        if text:
                            logger.info(f"Sarvam STT transcript: {text[:80]}")
                            try:
                                await self.on_transcript(text)
                            except Exception as e:
                                logger.warning(f"Transcript callback error: {e}")
                    elif msg_type == "speech_error":
                        logger.error(f"Sarvam WebSocket Error: {message}")
                        
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Sarvam session loop error: {e}\n{traceback.format_exc()}")
        finally:
            self._ws = None
            self._ws_ready.clear()

    async def send_audio(self, audio_bytes: bytes):
        """Send base64-encoded PCM audio chunk to Sarvam WebSocket continuously."""
        if not self._running or not audio_bytes:
            return
            
        # Wait up to 2 seconds for WS to be ready before giving up on this chunk
        try:
            await asyncio.wait_for(self._ws_ready.wait(), timeout=2.0)
        except asyncio.TimeoutError:
            return
            
        if self._ws:
            try:
                # The SDK transcribe method expects base64 encoded audio
                b64_audio = base64.b64encode(audio_bytes).decode("utf-8")
                await self._ws.transcribe(
                    audio=b64_audio,
                    encoding="pcm_s16le", # PCM 16-bit little-endian
                    sample_rate=16000
                )
            except Exception as e:
                logger.warning(f"Failed to send audio to Sarvam WS: {e}")

    async def stop(self):
        """Stop session."""
        self._running = False
        
        if self._receive_task and not self._receive_task.done():
            self._receive_task.cancel()
            try:
                await self._receive_task
            except asyncio.CancelledError:
                pass
                
        logger.info("Sarvam WebSocket STT session stopped")
