"""
gmail_service.py

OPTIONAL feature — reads user's Gmail inbox to find delivery order emails
from Zomato, Swiggy, Amazon, Flipkart etc. and gives that context to the AI
so it can say "You have a Zomato order #45821 arriving today."

Requires gmail_credentials.json (OAuth2 Desktop app credentials from
Google Cloud Console) + per-user token exchange. This is NOT required for
the core app. If gmail_credentials.json is absent, all functions return
empty results silently — the app works perfectly without it.

To skip entirely for hackathon: leave gmail_credentials.json absent.
Everything stubs out automatically.
"""

import base64
import json
import logging
import os
import re
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

CREDENTIALS_PATH = Path(__file__).parent.parent.parent / "gmail_credentials.json"
TOKEN_STORE_PATH = Path(__file__).parent.parent.parent / "gmail_tokens"

SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]

# Delivery platforms to look for in sender / subject
DELIVERY_PLATFORMS = {
    "zomato":    ["zomato"],
    "swiggy":    ["swiggy"],
    "amazon":    ["amazon"],
    "flipkart":  ["flipkart"],
    "blinkit":   ["blinkit", "grofers"],
    "meesho":    ["meesho"],
    "myntra":    ["myntra"],
    "bigbasket": ["bigbasket"],
    "dunzo":     ["dunzo"],
    "nykaa":     ["nykaa"],
}

STATUS_KEYWORDS = [
    "out for delivery", "arriving today", "arriving in",
    "delivered", "shipped", "dispatched", "on its way",
    "order confirmed", "order placed", "picked up", "packed",
]

# -----------------------------------------------------------------------
# Check if Gmail integration is available
# -----------------------------------------------------------------------

def _gmail_available() -> bool:
    if not CREDENTIALS_PATH.exists():
        return False
    try:
        from googleapiclient.discovery import build  # noqa
        from google_auth_oauthlib.flow import InstalledAppFlow  # noqa
        from google.auth.transport.requests import Request  # noqa
        import pickle  # noqa
        return True
    except ImportError:
        return False


# -----------------------------------------------------------------------
# Auth helpers
# -----------------------------------------------------------------------

def _get_credentials(user_id: str):
    """Load stored OAuth2 credentials for a user, refresh if expired."""
    try:
        import pickle
        from google.auth.transport.requests import Request

        TOKEN_STORE_PATH.mkdir(exist_ok=True)
        token_file = TOKEN_STORE_PATH / f"{user_id}.pickle"

        creds = None
        if token_file.exists():
            with open(token_file, "rb") as f:
                creds = pickle.load(f)

        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
            with open(token_file, "wb") as f:
                pickle.dump(creds, f)

        return creds
    except Exception as e:
        logger.error(f"Gmail credentials load failed for user {user_id}: {e}")
        return None


def _build_service(user_id: str):
    creds = _get_credentials(user_id)
    if not creds or not creds.valid:
        return None
    from googleapiclient.discovery import build
    return build("gmail", "v1", credentials=creds, cache_discovery=False)


# -----------------------------------------------------------------------
# Email parsing helpers
# -----------------------------------------------------------------------

def _decode_body(part: dict) -> str:
    mime = part.get("mimeType", "")
    if mime == "text/plain":
        data = part.get("body", {}).get("data", "")
        if data:
            return base64.urlsafe_b64decode(data + "==").decode("utf-8", errors="replace")
    if mime.startswith("multipart/"):
        for sub in part.get("parts", []):
            result = _decode_body(sub)
            if result:
                return result
    return ""


def _get_header(headers: list, name: str) -> str:
    for h in headers:
        if h.get("name", "").lower() == name.lower():
            return h.get("value", "")
    return ""


def parse_order_email(body: str, platform: str) -> dict:
    """
    Extract order details from an email body for a known platform.
    Returns dict with order_id and status, or empty dict if nothing found.
    """
    if not body:
        return {}

    text = body.lower()

    # Extract order id
    order_id = None
    for pattern in [
        r"order\s*(?:id|#|no\.?)[:\s]*([A-Z0-9\-]+)",
        r"#([A-Z0-9\-]{6,})",
        r"order\s+([0-9]{5,})",
    ]:
        m = re.search(pattern, body, re.IGNORECASE)
        if m:
            order_id = m.group(1)
            break

    # Extract status
    status = None
    for keyword in STATUS_KEYWORDS:
        if keyword in text:
            status = keyword
            break

    if not status:
        return {}

    return {
        "platform": platform,
        "order_id": order_id,
        "status": status,
    }


# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

async def get_recent_order_emails(user_id: str, max_results: int = 10) -> list:
    """
    Fetch recent delivery-related emails from the user's Gmail inbox.

    Returns a list of dicts like:
        [{"platform": "Zomato", "order_id": "45821", "status": "out for delivery"}, ...]

    Returns [] if Gmail is not configured or user has not authorized.
    Never raises.
    """
    if not _gmail_available():
        return []

    try:
        service = _build_service(user_id)
        if not service:
            return []

        # Build search query for all delivery platforms
        sender_queries = []
        for platform, keywords in DELIVERY_PLATFORMS.items():
            for kw in keywords:
                sender_queries.append(f"from:{kw}")
        query = f"({' OR '.join(sender_queries)}) newer_than:1d"

        results = service.users().messages().list(
            userId="me", maxResults=max_results, q=query
        ).execute()

        messages = results.get("messages", [])
        orders = []

        for msg_meta in messages:
            try:
                msg = service.users().messages().get(
                    userId="me", id=msg_meta["id"], format="full"
                ).execute()
                payload = msg.get("payload", {})
                headers = payload.get("headers", [])
                sender  = _get_header(headers, "From").lower()
                body    = _decode_body(payload)

                # Identify platform from sender
                matched_platform = None
                for platform, keywords in DELIVERY_PLATFORMS.items():
                    if any(kw in sender for kw in keywords):
                        matched_platform = platform
                        break

                if not matched_platform:
                    continue

                parsed = parse_order_email(body, matched_platform)
                if parsed:
                    orders.append(parsed)

            except Exception as e:
                logger.debug(f"Skipping Gmail message {msg_meta['id']}: {e}")
                continue

        return orders

    except Exception as e:
        logger.error(f"get_recent_order_emails failed: {e}")
        return []


def build_orders_context_string(orders: list) -> str:
    """
    Convert order list into a human-readable string for the Gemini system prompt.

    Example output:
        Active delivery orders:
        - Zomato order #45821 is out for delivery
        - Amazon order #407-1234 has been shipped
    """
    if not orders:
        return ""

    lines = ["Active delivery orders:"]
    for o in orders:
        platform = o.get("platform", "Unknown").capitalize()
        order_id = f" #{o['order_id']}" if o.get("order_id") else ""
        status   = o.get("status", "update")
        lines.append(f"  - {platform} order{order_id} is {status}")

    return "\n".join(lines)