"""
emotion_detector.py  —  Audio-based emotion detection via HuggingFace

Model: ehcalabres/wav2vec2-lg-xlsr-en-speech-emotion-recognition
  POST https://api-inference.huggingface.co/models/ehcalabres/wav2vec2-lg-xlsr-en-speech-emotion-recognition
  Header: Authorization: Bearer <HUGGINGFACE_API_KEY>
  Body:   raw audio bytes (WAV or PCM)
  Response: [{"label": "angry", "score": 0.82}, ...]

This is an audio model (wav2vec2), NOT a text model.
It receives the caller's raw audio and detects emotional state.
The result modifies the urgency score:
  anger / fear  → +2 urgency  (distressed caller — may be genuine emergency)
  sadness       → +1 urgency
  neutral       → +0
  joy / happy   → -1 urgency  (relaxed caller — probably not urgent)

Graceful degradation:
  503 Model loading  → neutral fallback (model cold-starting on HF free tier)
  Timeout (>8s)      → neutral fallback
  Any other error    → neutral fallback
  No API key         → neutral fallback (skip silently)

The call pipeline does NOT block on emotion detection — it runs concurrently
with Gemini response generation. If it times out, the neutral fallback is used
and the call continues normally.
"""

import logging
import time
import requests
from app.config import settings

logger = logging.getLogger(__name__)

# wav2vec2 audio model — takes raw audio bytes, returns emotion labels
HF_MODEL = "ehcalabres/wav2vec2-lg-xlsr-en-speech-emotion-recognition"
HF_API_URL = f"https://api-inference.huggingface.co/models/{HF_MODEL}"

# Returned when the model is unavailable or the audio is empty
NEUTRAL_FALLBACK: dict = {
    "dominant_emotion": "neutral",
    "emotions": [],
    "urgency_modifier": 0,
}

# How each detected emotion adjusts the urgency score from classify_call()
EMOTION_URGENCY_DELTA: dict[str, int] = {
    "angry":   2,
    "anger":   2,
    "fear":    2,
    "fearful": 2,
    "sad":     1,
    "sadness": 1,
    "disgust": 1,
    "neutral": 0,
    "calm":    0,
    "happy":   -1,
    "joy":     -1,
    "surprised": 0,
}


def detect_emotion(audio_bytes) -> dict:
    """
    Detect the dominant emotion in a caller's audio segment.

    Args:
        audio_bytes: Raw audio bytes (WAV or PCM) from the caller's voice,
                     or a text string passed for testing.

    Returns:
        {
            "dominant_emotion": str,           e.g. "angry"
            "emotions":         list            from HF API
            "urgency_modifier": int             -1, 0, 1, or 2
        }
    """
    if not audio_bytes:
        return NEUTRAL_FALLBACK

    if not settings.HUGGINGFACE_API_KEY:
        return NEUTRAL_FALLBACK

    headers = {
        "Authorization": f"Bearer {settings.HUGGINGFACE_API_KEY}",
        "Content-Type":  "audio/wav",
    }

    t0 = time.monotonic()

    try:
        response = requests.post(
            HF_API_URL,
            headers=headers,
            data=audio_bytes,      # raw bytes — NOT json=
            timeout=8,
        )

        elapsed_ms = int((time.monotonic() - t0) * 1000)

        # 503 = model still loading on HuggingFace free tier — common on cold start
        if response.status_code == 503:
            logger.warning(f"HuggingFace emotion model loading (503) at {elapsed_ms}ms — neutral fallback")
            return NEUTRAL_FALLBACK

        if response.status_code != 200:
            logger.warning(f"HuggingFace emotion API returned {response.status_code} at {elapsed_ms}ms")
            return NEUTRAL_FALLBACK

        raw = response.json()

        # Response is a list of {label, score} dicts
        if not isinstance(raw, list) or not raw:
            return NEUTRAL_FALLBACK

        # Flatten nested lists (HF sometimes wraps in an extra list)
        items = raw[0] if isinstance(raw[0], list) else raw

        emotions: dict[str, float] = {}
        for item in items:
            if "label" in item and "score" in item:
                label = item["label"].lower().strip()
                emotions[label] = float(item["score"])

        if not emotions:
            return NEUTRAL_FALLBACK

        dominant = max(emotions, key=lambda k: emotions[k])
        modifier = EMOTION_URGENCY_DELTA.get(dominant, 0)

        logger.debug(
            f"Emotion detected: {dominant} ({emotions.get(dominant, 0):.2f}) "
            f"→ urgency_modifier={modifier} [{elapsed_ms}ms]"
        )

        # Return emotions list in HF [{label, score}] format
        emotions_list = [{"label": k, "score": v} for k, v in emotions.items()]
        return {
            "dominant_emotion": dominant,
            "emotions":         emotions_list,
            "urgency_modifier": modifier,
        }

    except requests.Timeout:
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        logger.warning(f"HuggingFace emotion detection timed out at {elapsed_ms}ms — neutral fallback")
        return NEUTRAL_FALLBACK
    except Exception as e:
        logger.error(f"Emotion detection unexpected error: {e}")
        return NEUTRAL_FALLBACK


def apply_emotion_to_urgency(base_urgency: int, emotion_result: dict) -> int:
    """
    Apply the emotion urgency modifier to a base urgency score.

    Args:
        base_urgency:   Score from classify_call() or Gemini URGENCY signal (1-10).
        emotion_result: Result from detect_emotion_from_audio().

    Returns:
        Adjusted urgency score, clamped to [1, 10].
    """
    modifier = emotion_result.get("urgency_modifier", 0)
    return min(10, max(1, base_urgency + modifier))