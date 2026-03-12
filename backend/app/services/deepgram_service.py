
import asyncio
import logging
from deepgram import DeepgramClient
from deepgram.core.events import EventType
from app.config import settings

logger = logging.getLogger(__name__)

_dg_client = DeepgramClient(api_key=settings.DEEPGRAM_API_KEY)


class DeepgramStreamingSession:
    """
    Wraps Deepgram v2 live transcription for use inside FastAPI async context.
    
    Usage:
        session = DeepgramStreamingSession(on_transcript_callback)
        await session.start()
        await session.send_audio(pcm_bytes)
        await session.stop()
    """

    def __init__(self, on_transcript_callback):
        self.on_transcript = on_transcript_callback
        self._audio_queue: asyncio.Queue = asyncio.Queue()
        self._running = False
        self._task: asyncio.Task | None = None
        self._loop: asyncio.AbstractEventLoop | None = None

    async def start(self):
        """Start the Deepgram streaming session."""
        self._running = True
        self._loop = asyncio.get_event_loop()
        self._task = asyncio.create_task(self._run())
        logger.info("Deepgram streaming session started")

    async def _run(self):
        """Main loop — opens Deepgram connection and feeds audio from queue."""
        try:
            with _dg_client.listen.v2.connect(
                model="nova-3",
                encoding="linear16",
                sample_rate=16000,
                language="hi",
            ) as conn:

                def on_message(message):
                    try:
                        transcript = message.channel.alternatives[0].transcript
                        if transcript and message.is_final:
                            asyncio.run_coroutine_threadsafe(
                                self.on_transcript(transcript),
                                self._loop,
                            )
                    except Exception as e:
                        logger.warning(f"Transcript parse error: {e}")

                def on_error(error):
                    logger.error(f"Deepgram error: {error}")

                def on_close(_):
                    logger.info("Deepgram connection closed")

                conn.on(EventType.MESSAGE, on_message)
                conn.on(EventType.ERROR, on_error)
                conn.on(EventType.CLOSE, on_close)
                conn.start_listening()

                # Feed audio chunks from async queue to Deepgram synchronously
                while self._running:
                    try:
                        chunk = await asyncio.wait_for(
                            self._audio_queue.get(),
                            timeout=0.1,
                        )
                        conn.send(chunk)
                    except asyncio.TimeoutError:
                        continue
                    except Exception as e:
                        logger.warning(f"Audio chunk send error: {e}")
                        break

        except Exception as e:
            logger.error(f"Deepgram session failed: {e}")
        finally:
            self._running = False
            logger.info("Deepgram session ended")

    async def send_audio(self, audio_bytes: bytes):
        """Queue a PCM audio chunk for sending to Deepgram."""
        if self._running and audio_bytes:
            await self._audio_queue.put(audio_bytes)

    async def stop(self):
        """Stop the session gracefully."""
        self._running = False
        if self._task and not self._task.done():
            try:
                await asyncio.wait_for(self._task, timeout=3.0)
            except asyncio.TimeoutError:
                self._task.cancel()
                try:
                    await self._task
                except asyncio.CancelledError:
                    pass
        self._task = None
        logger.info("Deepgram session stopped")


