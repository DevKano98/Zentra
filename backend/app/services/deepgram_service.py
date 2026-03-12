"""
deepgram_service.py  —  Real-time and file transcription via Deepgram nova-3

deepgram-sdk==6.0.1 verified import patterns:
  from deepgram import DeepgramClient
  from deepgram.core.events import EventType
  conn = client.listen.v2.connect(model='nova-3', encoding='linear16',
    sample_rate=16000, punctuate=True, language='en-IN')
  conn.on(EventType.MESSAGE, handler)
  conn.start() / conn.send(audio_bytes) / conn.finish()
  handler signature: def on_message(self_ref, message, **kwargs)
  check message.is_final — only fire callback on final transcripts

Audio spec from Android:
  Source:      AudioRecord VOICE_COMMUNICATION (suppresses echo, optimises for speech)
  Sample rate: 16000 Hz
  Encoding:    PCM 16-bit mono (linear16)
  Chunk size:  ~3200 bytes = 100ms of audio
  Sent as:     raw bytes over WebSocket
  Expected latency from audio to final transcript: ~300ms
"""

import asyncio
import logging
import time
from typing import Callable, Optional

from deepgram import DeepgramClient
from deepgram.core.events import EventType
from app.config import settings

logger = logging.getLogger(__name__)

# One shared client — thread-safe, reused across all sessions
_dg_client = DeepgramClient(api_key=settings.DEEPGRAM_API_KEY)

# nova-3 is Deepgram's latest model — best accuracy for Indian English (en-IN)
_STREAM_PARAMS = dict(
    model="nova-3",
    encoding="linear16",
    sample_rate=16000,
    punctuate=True,
    language="en-IN",
    smart_format=True,        # capitalisation, numbers, currency
    interim_results=False,    # only fire on final — reduces callback noise
    utterance_end_ms=1000,    # silence gap that triggers a final transcript
)


# ─────────────────────────────────────────────────────────────────────────────
# Live streaming session
# ─────────────────────────────────────────────────────────────────────────────

class DeepgramStreamingSession:
    """
    Manages a single live Deepgram streaming connection for one call.

    Lifecycle:
        session = DeepgramStreamingSession(on_transcript_callback=my_fn)
        await session.start()                   # open WebSocket to Deepgram
        await session.send_audio(pcm_chunk)     # called for every 100ms chunk
        await session.stop()                    # close connection
        full_text = session.get_full_transcript()

    The on_transcript_callback fires once per final utterance.
    It is called from a background thread (Deepgram SDK internals) — ensure
    the callback is thread-safe (appending to a list is safe).
    """

    def __init__(self, on_transcript_callback: Callable[[str], None]):
        self.on_transcript_callback = on_transcript_callback
        self.conn = None
        self._transcript_parts: list[str] = []
        self._started = False
        self._start_time: float = 0.0

    async def start(self) -> None:
        """Open a live streaming connection to Deepgram."""
        self._start_time = time.monotonic()
        self.conn = _dg_client.listen.v2.connect(**_STREAM_PARAMS)

        def on_message(self_ref, message, **kwargs):
            """
            Fired by Deepgram SDK on every transcript event.
            message.is_final distinguishes utterance-complete from interim.
            We only act on final transcripts — this is the correct v6 pattern.
            """
            try:
                if not message.is_final:
                    return

                transcript = ""
                if (
                    message.channel
                    and message.channel.alternatives
                    and len(message.channel.alternatives) > 0
                ):
                    transcript = message.channel.alternatives[0].transcript or ""

                if not transcript.strip():
                    return

                elapsed_ms = int((time.monotonic() - self._start_time) * 1000)
                logger.debug(f"Deepgram final transcript at {elapsed_ms}ms: '{transcript}'")

                self._transcript_parts.append(transcript)
                self.on_transcript_callback(transcript)

            except Exception as e:
                logger.error(f"Deepgram on_message handler error: {e}")

        def on_error(self_ref, error, **kwargs):
            logger.error(f"Deepgram streaming error: {error}")

        def on_close(self_ref, close, **kwargs):
            logger.info("Deepgram streaming connection closed")

        self.conn.on(EventType.MESSAGE, on_message)
        self.conn.on(EventType.ERROR,   on_error)
        self.conn.on(EventType.CLOSE,   on_close)

        self.conn.start()
        self._started = True
        logger.info("Deepgram streaming session started (nova-3, en-IN, 16kHz)")

    async def send_audio(self, audio_bytes: bytes) -> None:
        """
        Send a raw PCM chunk to Deepgram.
        Called for every ~100ms chunk from the WebSocket handler.
        audio_bytes must be 16-bit mono linear PCM at 16000 Hz.
        """
        if self.conn and self._started:
            self.conn.send(audio_bytes)

    async def stop(self) -> None:
        """
        Signal end-of-stream to Deepgram and close the connection.
        Deepgram will fire any remaining final transcripts before closing.
        """
        if self.conn and self._started:
            self.conn.finish()
            self._started = False
            duration_s = round(time.monotonic() - self._start_time, 2)
            logger.info(f"Deepgram session stopped after {duration_s}s")

    def get_full_transcript(self) -> str:
        """Return all final transcripts joined into a single string."""
        return " ".join(self._transcript_parts).strip()

    def get_transcript_parts(self) -> list[str]:
        """Return individual final utterances for turn-by-turn processing."""
        return list(self._transcript_parts)


# ─────────────────────────────────────────────────────────────────────────────
# File transcription (post-call, for FIR / summary)
# ─────────────────────────────────────────────────────────────────────────────

async def transcribe_audio_file(audio_bytes: bytes) -> str:
    """
    Transcribe a complete audio file using the Deepgram v1 prerecorded API.
    Used after a call ends to get a clean full transcript for FIR generation
    and call summarisation — latency is not critical here.

    Args:
        audio_bytes: Raw WAV or PCM bytes of the complete call recording.

    Returns:
        Full transcript string, or "" on failure.
    """
    if not audio_bytes:
        return ""

    # Streaming the file through the live API gives consistent results
    # and avoids the v1 prerecorded API differences in the SDK
    transcript_parts: list[str] = []
    done = asyncio.Event()

    def on_transcript(text: str) -> None:
        transcript_parts.append(text)

    session = DeepgramStreamingSession(on_transcript_callback=on_transcript)

    try:
        await session.start()

        # Feed in 4096-byte chunks with small delays to simulate real-time
        # Deepgram needs a continuous stream, not all bytes at once
        chunk_size = 4096
        for i in range(0, len(audio_bytes), chunk_size):
            await session.send_audio(audio_bytes[i : i + chunk_size])
            await asyncio.sleep(0.005)  # 5ms between chunks — fast but not overwhelming

        # Give Deepgram time to finalise any remaining utterances
        await asyncio.sleep(1.5)
        await session.stop()

        return session.get_full_transcript()

    except Exception as e:
        logger.error(f"transcribe_audio_file failed: {e}")
        await session.stop()
        return " ".join(transcript_parts)  # return whatever we got before failure