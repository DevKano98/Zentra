"""
tts_service.py  —  Sarvam Bulbul v3 Text-to-Speech

Sarvam API spec (requests only — no SDK):
  POST https://api.sarvam.ai/text-to-speech
  Header: api-subscription-key: <SARVAM_API_KEY>   ← NOT "Authorization Bearer"
  Body JSON:
    inputs:               [text_string]
    target_language_code: "hi-IN" | "en-IN"
    speaker:              "Priya" | "Rahul" | "Ritu" | "Rohan"
    model:                "bulbul:v3"
    speech_sample_rate:   22050
    enable_preprocessing: true   (normalises numbers, abbreviations)
    pace:                 0.9    (slightly slower = clearer for phone calls)
  Response:
    audios[0] — base64-encoded WAV at 22050 Hz

Android playback:
  AudioTrack plays returned WAV at 22050 Hz into the call stream.
  The AI voice is injected back into the active call so the caller hears it.
  Target latency for this step: ~200ms

Voice selection matrix:
  Language  Gender   Speaker  Code
  Hindi     Female   Priya    hi-IN   ← default
  Hindi     Male     Rahul    hi-IN
  English   Female   Ritu     en-IN
  English   Male     Rohan    en-IN
"""

import base64
import logging
import time
import requests
from app.config import settings

logger = logging.getLogger(__name__)

SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"

# (language, gender) → Sarvam speaker name
VOICE_MAP: dict[tuple[str, str], str] = {
    ("hindi",   "female"): "priya",
    ("hindi",   "male"):   "rahul",
    ("english", "female"): "ritu",
    ("english", "male"):   "rohan",
}

# language → BCP-47 code
LANG_CODE_MAP: dict[str, str] = {
    "hindi":   "hi-IN",
    "english": "en-IN",
}

# Sarvam has a 500-char limit per request — longer text must be chunked
_MAX_INPUT_CHARS = 500


def _chunk_text(text: str, max_chars: int = _MAX_INPUT_CHARS) -> list[str]:
    """
    Split text on sentence boundaries to stay under Sarvam's character limit.
    Tries to split on '. ', '! ', '? ', '। ' (Hindi danda) before hard-splitting.
    """
    if len(text) <= max_chars:
        return [text]

    chunks = []
    remaining = text.strip()
    while len(remaining) > max_chars:
        # Find last sentence break before the limit
        cut = max_chars
        for sep in [". ", "! ", "? ", "। ", ", "]:
            idx = remaining.rfind(sep, 0, max_chars)
            if idx != -1:
                cut = idx + len(sep)
                break
        chunks.append(remaining[:cut].strip())
        remaining = remaining[cut:].strip()

    if remaining:
        chunks.append(remaining)

    return chunks


def synthesize(text: str, language: str = "hindi", gender: str = "female") -> bytes:
    """
    Convert text to speech using Sarvam Bulbul v3.

    Args:
        text:     The AI response to speak. Signal lines must be stripped first
                  (use parse_signals().clean_response).
        language: "hindi" or "english" — selects voice and language code.
        gender:   "female" or "male" — selects speaker.

    Returns:
        Raw WAV bytes at 22050 Hz, ready for Android AudioTrack.
        Returns b"" on any failure — caller must handle silence gracefully.

    Notes:
        - Long text is automatically chunked and WAV segments are concatenated.
        - WAV headers from each segment are preserved so Android can parse them.
    """
    if not text or not text.strip():
        return b""

    t0 = time.monotonic()

    lang_key    = language.lower()
    gender_key  = gender.lower()
    speaker     = VOICE_MAP.get((lang_key, gender_key), "Priya")
    lang_code   = LANG_CODE_MAP.get(lang_key, "hi-IN")

    headers = {
        "api-subscription-key": settings.SARVAM_API_KEY,
        "Content-Type": "application/json",
    }

    chunks      = _chunk_text(text.strip())
    wav_segments: list[bytes] = []

    for chunk in chunks:
        if not chunk:
            continue

        payload = {
            "inputs":               [chunk],
            "target_language_code": lang_code,
            "speaker":              speaker,
            "model":                "bulbul:v3",
            "speech_sample_rate":   22050,
            "enable_preprocessing": True,
            "pace":                 0.9,
        }

        try:
            resp = requests.post(
                SARVAM_TTS_URL,
                json=payload,
                headers=headers,
                timeout=10,
            )
            resp.raise_for_status()

            audios = resp.json().get("audios", [])
            if not audios:
                logger.error("Sarvam TTS returned empty audios list")
                return b""

            wav_bytes = base64.b64decode(audios[0])
            wav_segments.append(wav_bytes)

        except requests.Timeout:
            logger.error("Sarvam TTS request timed out")
            return b""
        except requests.HTTPError as e:
            logger.error(f"Sarvam TTS HTTP error {e.response.status_code}: {e.response.text[:200]}")
            return b""
        except requests.RequestException as e:
            logger.error(f"Sarvam TTS request failed: {e}")
            return b""
        except (KeyError, IndexError, ValueError) as e:
            logger.error(f"Sarvam TTS response parse failed: {e}")
            return b""

    if not wav_segments:
        return b""

    elapsed_ms = int((time.monotonic() - t0) * 1000)
    logger.debug(
        f"Sarvam TTS: {len(chunks)} chunk(s), "
        f"{sum(len(s) for s in wav_segments)} bytes, "
        f"{elapsed_ms}ms"
    )

    # Single chunk — return directly
    if len(wav_segments) == 1:
        return wav_segments[0]

    # Multiple chunks — concatenate raw bytes
    # Android AudioTrack can handle concatenated WAV segments
    return b"".join(wav_segments)


def get_voice_info(language: str = "hindi", gender: str = "female") -> dict:
    """Return metadata about the selected voice for logging/debugging."""
    lang_key   = language.lower()
    gender_key = gender.lower()
    return {
        "speaker":   VOICE_MAP.get((lang_key, gender_key), "Priya"),
        "lang_code": LANG_CODE_MAP.get(lang_key, "hi-IN"),
        "language":  language,
        "gender":    gender,
    }