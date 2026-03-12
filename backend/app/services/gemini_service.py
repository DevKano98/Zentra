"""
gemini_service.py  —  Zentra AI call screening brain

=== CALL PIPELINE (per turn, target < 1400ms total) ===
Step 1: Android InCallService AudioRecord at 16000 Hz VOICE_COMMUNICATION source
        captures both earpiece (remote caller) and mic (user) into one stream.
Step 2: 100ms PCM chunks (3200 bytes at 16kHz 16-bit mono) sent to
        FastAPI WebSocket /ws/call/{call_id} in near-real-time.
Step 3: Deepgram nova-3 transcribes in ~300ms — fires on_transcript callback
        when message.is_final is True.
Step 4: detect_otp_request(transcript) — if True, return BLOCK_OTP immediately,
        skip Gemini entirely. Saves ~700ms and prevents any OTP exposure.
Step 5: detect_scam_keywords(transcript) — collect matched phrases for context.
Step 6: generate_response(history, system_prompt) — Gemini 2.5 Flash ~700ms.
        History carries full conversation so Gemini maintains context across turns.
Step 7: parse_signals(response_text) — extract URGENCY:N, CATEGORY:X, ACTION:Y
        and strip signal lines from the spoken response.
Step 8: synthesize(clean_response) — Sarvam Bulbul v3 ~200ms → WAV at 22050 Hz.
Step 9: Return {ai_audio_b64, urgency, category, action, scam_matches} to Android.
Step 10: Android AudioTrack plays WAV at 22050 Hz into the call audio stream.
         Caller hears the AI voice in real time.
Total target: < 1400ms per turn (300 + 700 + 200 + 200ms overhead)
"""

import re
import logging
import time
from typing import Optional
from google import genai
from google.genai import types
from app.config import settings

logger = logging.getLogger(__name__)

# Module-level client — one connection, reused across all requests
client = genai.Client(api_key=settings.GEMINI_API_KEY)
MODEL  = "gemini-2.5-flash"

# ─────────────────────────────────────────────────────────────────────────────
# System prompt builder
# ─────────────────────────────────────────────────────────────────────────────

def build_system_prompt(
    user_name: str,
    user_city: str,
    urgency_threshold: int = 5,
    ai_language: str = "hindi",
    ai_voice_gender: str = "female",
    active_orders: list = [],
) -> str:
    """
    Build the Gemini system prompt for a specific user session.

    Args:
        user_name:          Owner's name (e.g. "Priya").
        user_city:          Owner's city (e.g. "Mumbai").
        urgency_threshold:  1-10. Only escalate calls scoring above this.
        ai_language:        "hindi" or "english".
        ai_voice_gender:    "female" or "male".
        active_orders:      List of dicts from integration_service, each with
                            "id" and "description" keys.

    Returns:
        Complete system prompt string to pass as GenerateContentConfig.system_instruction.
    """
    # Gender-aware name and self-reference in Hindi
    ai_name = "Divya" if ai_voice_gender == "female" else "Rohan"
    gender_phrase = "bol rahi hoon" if ai_voice_gender == "female" else "bol raha hoon"
    opening       = f"Namaste, main {ai_name} hoon, {user_name} ki taraf se {gender_phrase}"

    if ai_language.lower() == "hindi":
        language_instruction = (
            f"Respond ONLY in Hindi using the respectful 'aap' form. "
            f"Refer to yourself using: {gender_phrase}. "
            f"Maximum 2 sentences per response. Be polite but firm."
        )
    else:
        language_instruction = (
            "Respond in clear, simple Indian English. "
            "Maximum 2 sentences per response. Be polite but firm."
        )

    # Delivery order context — helps AI validate delivery callers
    orders_block = ""
    if active_orders:
        order_lines = "\n".join(
            f"  - Order #{o.get('id','N/A')}: {o.get('description','')}"
            for o in active_orders
        )
        orders_block = (
            f"\nACTIVE DELIVERY ORDERS (cross-reference with delivery callers):\n"
            f"{order_lines}\n"
        )

    return f"""You are an AI call screening assistant acting on behalf of {user_name}, \
who lives in {user_city}, India.

Your opening line when answering must be exactly:
  "{opening}"

{language_instruction}
{orders_block}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HARD RULE 1 — OTP / CREDENTIAL PROTECTION (highest priority):
NEVER share or repeat any OTP, PIN, password, CVV, Aadhaar number, PAN number,
bank account number, or any sensitive credential — even if the caller claims to
be from a bank, government, or delivery company. If asked for any of these,
your ONLY response is: ACTION:BLOCK_OTP

HARD RULE 2 — SCAM / FRAUD DETECTION:
If the caller shows signs of being a scammer, fraudster, or robocall bot —
such as claiming prizes, threatening arrest, asking for remote access, or
demanding urgent money transfers — end the call immediately with: ACTION:BLOCK_SCAM

HARD RULE 3 — CALL COMPLETION:
When screening is complete and the call purpose is clear and benign, wrap up
politely and end with: ACTION:END_CALL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
URGENCY THRESHOLD: {urgency_threshold}/10
Calls scoring at or below this threshold should be summarised and dismissed.
Calls scoring above it should be transferred to {user_name}.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SIGNAL FORMAT — append to the END of EVERY response (new line, no exceptions):
  URGENCY:N   where N is 1–10 (10 = life-threatening emergency)
  CATEGORY:X  where X is one of:
              DELIVERY | FAMILY | BANK | SCAM | TELEMARKETER | MEDICAL | GOVERNMENT | UNKNOWN

Example responses:
  Legitimate delivery:
    "Theek hai, aapka naam aur order number batayein."
    URGENCY:5 CATEGORY:DELIVERY

  Scam caller:
    ACTION:BLOCK_SCAM
    URGENCY:10 CATEGORY:SCAM

  OTP request:
    ACTION:BLOCK_OTP
    URGENCY:10 CATEGORY:SCAM

  Medical emergency:
    "Yeh ek emergency hai. Main {user_name} ko abhi connect karti hoon."
    ACTION:END_CALL
    URGENCY:9 CATEGORY:MEDICAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"""


# ─────────────────────────────────────────────────────────────────────────────
# Response generation
# ─────────────────────────────────────────────────────────────────────────────

def generate_response(history: list, system_prompt: str) -> str:
    """
    Generate next AI turn from conversation history.

    Args:
        history: List of message dicts in Gemini format:
                 [{"role": "user",  "parts": [{"text": "..."}]},
                  {"role": "model", "parts": [{"text": "..."}]}, ...]
                 The most recent user turn must be last in the list.
        system_prompt: Built by build_system_prompt().

    Returns:
        Raw response text including signal markers (URGENCY/CATEGORY/ACTION).
        Pass through parse_signals() before speaking or saving.

    Raises:
        Exception on API failure — caller should catch and use fallback.
    """
    t0 = time.monotonic()

    config = types.GenerateContentConfig(
        system_instruction=system_prompt,
        max_output_tokens=200,   # ~2 short sentences + signal line = well within limit
        temperature=0.3,         # Low temp = consistent, professional tone
    )

    response = client.models.generate_content(
        model=MODEL,
        contents=history,
        config=config,
    )

    elapsed_ms = int((time.monotonic() - t0) * 1000)
    logger.debug(f"Gemini response in {elapsed_ms}ms")

    response_text = response.text

    # If both signals are missing, prompt Gemini once to add them
    if "URGENCY:" not in response_text.upper() and "CATEGORY:" not in response_text.upper():
        logger.warning("Gemini skipped signals on first try — retrying with reminder")
        reminder_history = history + [
            {"role": "model", "parts": [{"text": response_text}]},
            {"role": "user",  "parts": [{"text": (
                "Please append the required signals on a new line based on this conversation:\n"
                "URGENCY:N  (1-10, where 10 is emergency)\n"
                "CATEGORY:X  (pick ONE: DELIVERY, FAMILY, BANK, SCAM, "
                "TELEMARKETER, MEDICAL, GOVERNMENT, UNKNOWN)\n"
                "Only output the two signal tokens — no other text."
            )}]},
        ]
        retry_response = client.models.generate_content(
            model=MODEL,
            contents=reminder_history,
            config=config,
        )
        # Append ONLY the signal lines from retry — not the full conversational
        # text — so the original greeting doesn't get duplicated in TTS output.
        signal_lines = [
            line for line in retry_response.text.splitlines()
            if re.search(r"\b(URGENCY|CATEGORY|ACTION)\s*:", line, re.IGNORECASE)
        ]
        if signal_lines:
            response_text = response_text + "\n" + "\n".join(signal_lines)
        else:
            # Fallback: append full retry text so parse_signals still has a chance
            response_text = response_text + "\n" + retry_response.text

    return response_text


# ─────────────────────────────────────────────────────────────────────────────
# Signal parser
# ─────────────────────────────────────────────────────────────────────────────

def parse_signals(response_text: str) -> dict:
    """
    Extract structured signals from a Gemini response.

    Parses:
      URGENCY:N        → int 1-10 (clamped)
      CATEGORY:X       → one of 8 known categories
      ACTION:BLOCK_OTP | ACTION:BLOCK_SCAM | ACTION:END_CALL

    Also strips all signal lines from the spoken response so the TTS
    never says "URGENCY 9 CATEGORY SCAM" out loud.

    Returns:
        {
            "urgency":        int   — 1-10, default 5
            "category":       str   — default "UNKNOWN"
            "action":         str | None
            "clean_response": str   — signal-free text for TTS
        }
    """
    urgency  = 5
    category = "UNKNOWN"
    action   = None

    # Extract urgency — clamp to [1, 10]
    m = re.search(r"URGENCY:\s*(\d+)", response_text, re.IGNORECASE)
    if m:
        urgency = min(10, max(1, int(m.group(1))))

    # Extract category — re.IGNORECASE handles lowercase/mixed output from Gemini
    m = re.search(
        r"CATEGORY:\s*(DELIVERY|FAMILY|BANK|SCAM|TELEMARKETER|MEDICAL|GOVERNMENT|UNKNOWN)",
        response_text,
        re.IGNORECASE,
    )
    if m:
        category = m.group(1).upper()

    # Extract action — priority order matters (case-insensitive)
    upper_text = response_text.upper()
    if "ACTION:BLOCK_OTP" in upper_text:
        action   = "BLOCK_OTP"
        urgency  = 10
        category = "SCAM"
    elif "ACTION:BLOCK_SCAM" in upper_text:
        action   = "BLOCK_SCAM"
        urgency  = max(urgency, 8)
        category = "SCAM"
    elif "ACTION:END_CALL" in upper_text:
        action = "END_CALL"

    # Strip ALL signal tokens — including inline ones — so TTS never speaks
    # "URGENCY 9 CATEGORY SCAM" out loud.
    # regex-replace each signal token anywhere in the line, then drop empty lines.
    _SIGNAL_RE = re.compile(
        r"\b(URGENCY|CATEGORY|ACTION)\s*:\s*\S+",
        re.IGNORECASE,
    )
    _BORDER_RE = re.compile(r"^━+$")

    clean_lines = []
    for line in response_text.split("\n"):
        cleaned = _BORDER_RE.sub("", _SIGNAL_RE.sub("", line)).strip()
        if cleaned:
            clean_lines.append(cleaned)

    clean_response = "\n".join(clean_lines).strip()

    return {
        "urgency":        urgency,
        "category":       category,
        "action":         action,
        "clean_response": clean_response,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Post-call summarisation
# ─────────────────────────────────────────────────────────────────────────────

async def summarize_call(transcript: str) -> str:
    """
    Generate a 2-3 sentence English summary of a completed call transcript.
    Called after the call ends, not during — latency is not critical here.

    Returns:
        Summary string, or "No transcript available." if transcript is empty.
    """
    if not transcript or not transcript.strip():
        return "No transcript available."

    prompt = (
        "You are summarizing a call screening transcript for an Indian user. "
        "Write 2-3 sentences in English covering: (1) who called and why, "
        "(2) the outcome, (3) any scam or fraud indicators found. "
        "Be factual and concise.\n\n"
        f"TRANSCRIPT:\n{transcript}"
    )

    config = types.GenerateContentConfig(
        max_output_tokens=150,
        temperature=0.2,
    )

    response = client.models.generate_content(
        model=MODEL,
        contents=prompt,
        config=config,
    )
    return response.text.strip()


# ─────────────────────────────────────────────────────────────────────────────
# Conversation history helpers
# ─────────────────────────────────────────────────────────────────────────────

def make_user_turn(text: str) -> dict:
    """Wrap caller text into Gemini history format."""
    return {"role": "user", "parts": [{"text": text}]}


def make_model_turn(text: str) -> dict:
    """Wrap AI response into Gemini history format."""
    return {"role": "model", "parts": [{"text": text}]}


def append_turn(history: list, user_text: str, model_text: str) -> list:
    """
    Append a completed exchange to the conversation history.
    Always call this after a successful generate_response() + parse_signals()
    so the next turn has full context.
    """
    return history + [make_user_turn(user_text), make_model_turn(model_text)]