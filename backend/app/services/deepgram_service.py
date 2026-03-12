"""
backend/app/services/deepgram_service.py

Speech-to-text using Sarvam AI STT API.
Replaces Deepgram — same interface, drop-in replacement.
Sarvam handles Hindi far better than Deepgram nova-3.

API: POST https://api.sarvam.ai/speech-to-text
Header: api-subscription-key: SARVAM_API_KEY
Body: multipart/form-data
  - file: audio bytes (WAV, 16kHz, mono, 16-bit PCM)
  - model: saarika:v2
  - language_code: hi-IN
Response: {"transcript": "..."}
"""

import asyncio
import io
import logging
import struct
import wave
import httpx
from app.config import settings

logger = logging.getLogger(__name__)

SARVAM_STT_URL = "https://api.sarvam.ai/speech-to-text"
SARVAM_STT_MODEL = "saarika:v2"
SAMPLE_RATE = 16000
CHUNK_DURATION_MS = 2000   # Reduced to 2 seconds for faster response
CHUNK_SIZE_BYTES = SAMPLE_RATE * 2 * (CHUNK_DURATION_MS // 1000)  # 64000 bytes


def _pcm_to_wav(pcm_bytes: bytes, sample_rate: int = 16000) -> bytes:
    """Convert raw PCM bytes to WAV format for Sarvam API."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)   # 16-bit
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


async def _sarvam_transcribe(pcm_bytes: bytes) -> str:
    """Send PCM audio to Sarvam STT and return transcript."""
    if len(pcm_bytes) < 3200:   # Less than 100ms — skip
        return ""

    wav_bytes = _pcm_to_wav(pcm_bytes)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                SARVAM_STT_URL,
                headers={"api-subscription-key": settings.SARVAM_API_KEY},
                files={"file": ("audio.wav", wav_bytes, "audio/wav")},
                data={
                    "model": SARVAM_STT_MODEL,
                    "language_code": "hi-IN",
                },
            )
            response.raise_for_status()
            data = response.json()
            transcript = data.get("transcript", "").strip()
            if transcript:
                logger.info(f"Sarvam STT transcript: {transcript[:80]}")
            return transcript

    except httpx.HTTPStatusError as e:
        logger.warning(f"Sarvam STT HTTP error {e.response.status_code}: {e.response.text[:200]}")
        return ""
    except Exception as e:
        logger.warning(f"Sarvam STT error: {e}")
        return ""


class SarvamStreamingSession:
    """
    Drop-in replacement for Deepgram using Sarvam STT.
    Accumulates PCM chunks and sends every 3 seconds.
    Same interface as before — nothing else needs to change.
    """

    def __init__(self, on_transcript_callback):
        self.on_transcript = on_transcript_callback
        self._audio_buffer = bytearray()
        self._running = False
        self._task: asyncio.Task | None = None
        self._lock = asyncio.Lock()

    async def start(self):
        self._running = True
        self._task = asyncio.create_task(self._flush_loop())
        logger.info("Sarvam STT session started")

    async def _flush_loop(self):
        """Every 3 seconds, send accumulated audio to Sarvam STT."""
        while self._running:
            await asyncio.sleep(CHUNK_DURATION_MS / 1000)
            await self._flush()

    async def _flush(self):
        """Send buffered audio to Sarvam and fire callback if transcript found."""
        async with self._lock:
            if len(self._audio_buffer) < 3200:
                return
            pcm_data = bytes(self._audio_buffer)
            self._audio_buffer.clear()

        logger.info(f"STT: Flushing {len(pcm_data)} bytes to Sarvam...")
        transcript = await _sarvam_transcribe(pcm_data)
        if transcript:
            try:
                await self.on_transcript(transcript)
            except Exception as e:
                logger.warning(f"Transcript callback error: {e}")
        else:
            logger.debug("STT: No transcript found for this chunk")

    async def send_audio(self, audio_bytes: bytes):
        """Buffer incoming PCM audio chunk."""
        if self._running and audio_bytes:
            async with self._lock:
                self._audio_buffer.extend(audio_bytes)

            # Debug log every ~100 chunks to avoid spamming
            if len(self._audio_buffer) % (3200 * 10) == 0:
                logger.debug(f"STT: Buffer size is {len(self._audio_buffer)} bytes")

            # If buffer is very large (>5 seconds), flush immediately
            if len(self._audio_buffer) > SAMPLE_RATE * 2 * 5:
                await self._flush()

    async def stop(self):
        """Stop session and flush any remaining audio."""
        self._running = False

        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

        # Final flush
        await self._flush()
        self._audio_buffer.clear()
        logger.info("Sarvam STT session stopped")
