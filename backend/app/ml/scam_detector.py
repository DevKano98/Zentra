"""
scam_detector.py  —  Fast rule-based scam and OTP detection

Runs BEFORE Gemini in the call pipeline (Step 4-5) as a low-latency guard.
These checks are microseconds vs Gemini's 700ms — they act as an early
exit that saves API cost and response time for obvious cases.

Two detection functions:

1. detect_otp_request(text)
   → Detects if the caller is asking the AI (or user) to share an OTP,
     PIN, CVV, Aadhaar, or any credential.
   → If True: return ACTION:BLOCK_OTP immediately, skip Gemini.
   → Uses regex patterns to catch English and Hindi/Hinglish variants.

2. detect_scam_keywords(text)
   → Checks text against a curated list of 70+ Indian scam phrases
     loaded from scam_keywords.json.
   → Returns matched phrases so Gemini context can be enriched.
   → is_scam=True only if 2+ phrases match (reduces false positives).
   → Used to augment (not replace) Gemini's judgement.
"""

import json
import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

_KEYWORDS_PATH = Path(__file__).parent / "scam_keywords.json"
_scam_keywords: list[str] = []

try:
    with open(_KEYWORDS_PATH, encoding="utf-8") as f:
        _scam_keywords = json.load(f)
    logger.info(f"Loaded {len(_scam_keywords)} scam keywords from scam_keywords.json")
except FileNotFoundError:
    logger.warning("scam_keywords.json not found — keyword scam detection disabled")
except json.JSONDecodeError as e:
    logger.error(f"scam_keywords.json is malformed: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# OTP / credential request detection (regex-based)
# ─────────────────────────────────────────────────────────────────────────────

# Covers English, Hinglish, and Hindi romanised variants
# Each pattern is a compiled regex for speed
_OTP_PATTERNS: list[re.Pattern] = [re.compile(p, re.IGNORECASE) for p in [
    # English
    r"\botp\b",
    r"\bone[\s\-]?time[\s\-]?password\b",
    r"\bverification[\s\-]?code\b",
    r"\bsecurity[\s\-]?code\b",
    r"\bsend[\s\w]{0,10}code\b",
    r"\bshare[\s\w]{0,10}code\b",
    r"\btell[\s\w]{0,10}code\b",
    r"\bgive[\s\w]{0,10}code\b",
    r"\bpin\b",
    r"\bcvv\b",
    r"\bcard[\s\-]?number\b",
    r"\baadhaar\b",
    r"\baadhar\b",
    r"\bpan[\s\-]?number\b",
    r"\bpassword\b",
    r"\baccount[\s\-]?number\b",
    r"\bbank[\s\w]{0,10}details\b",
    # Hinglish — share.*otp / batao.*otp style
    r"\bshare\b.{0,20}\botp\b",
    r"\bbatao\b.{0,20}\botp\b",
    r"\botp\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\bcode\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\bpin\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\bpassword\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\bnumber\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\baadhaar\s+(?:batao|bhejo|bata|do|dena|share)\b",
    r"\b(?:apna|aapka|mujhe|humein)\s+otp\b",
    r"\b(?:apna|aapka|mujhe|humein)\s+password\b",
]]


def detect_otp_request(text: str) -> bool:
    """
    Detect if the caller is requesting an OTP, PIN, CVV, or other credential.

    This is the HIGHEST priority check in the call pipeline.
    If True, the AI must return ACTION:BLOCK_OTP immediately without
    generating any further response — to avoid any chance of leaking credentials.

    Args:
        text: Transcript of the current caller turn.

    Returns:
        True if an OTP or credential request is detected.
    """
    if not text or not text.strip():
        return False

    for pattern in _OTP_PATTERNS:
        if pattern.search(text):
            logger.warning(f"OTP request detected: pattern='{pattern.pattern}' text='{text[:80]}'")
            return True

    return False


# ─────────────────────────────────────────────────────────────────────────────
# Scam keyword detection (JSON list-based)
# ─────────────────────────────────────────────────────────────────────────────

def detect_scam_keywords(text: str) -> dict:
    """
    Check transcript against the curated Indian scam phrase list.

    Requires 2 or more phrase matches to flag is_scam=True — this avoids
    false positives from single common words appearing in legitimate calls.

    Args:
        text: Any amount of transcript text (turn or full call).

    Returns:
        {
            "is_scam":        bool
            "matched_phrases": list[str]   — all matching phrases
            "match_count":    int
        }
    """
    if not text or not _scam_keywords:
        return {"is_scam": False, "matched_phrases": [], "match_count": 0}

    text_lower = text.lower()
    matched    = []

    for keyword in _scam_keywords:
        if isinstance(keyword, str) and keyword.lower() in text_lower:
            matched.append(keyword)

    # Deduplicate while preserving order
    seen = set()
    unique_matched = []
    for m in matched:
        if m.lower() not in seen:
            seen.add(m.lower())
            unique_matched.append(m)

    return {
        "is_scam":        len(unique_matched) >= 2,
        "matched_phrases": unique_matched,
        "match_count":    len(unique_matched),
    }


def get_scam_context_for_gemini(matched_phrases: list[str]) -> str:
    """
    Build a context string to prepend to the Gemini history when scam
    phrases are detected. Helps Gemini respond more aggressively.

    Args:
        matched_phrases: From detect_scam_keywords()["matched_phrases"].

    Returns:
        Context string to add as a system note, or "" if no matches.
    """
    if not matched_phrases:
        return ""

    phrases_str = ", ".join(f'"{p}"' for p in matched_phrases[:5])
    return (
        f"[SYSTEM ALERT: Scam indicators detected in caller speech: {phrases_str}. "
        f"Treat this caller with maximum suspicion. Do NOT share any information.]"
    )