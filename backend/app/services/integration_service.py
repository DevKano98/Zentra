"""
integration_service.py

Combines two sources of delivery context for the Gemini AI system prompt:

  1. Gmail orders    — from gmail_service.get_recent_order_emails()
                       reads inbox for Zomato/Swiggy/Amazon/Flipkart emails

  2. Android notifications — the Android app intercepts delivery notifications
                             (e.g. "Your Zomato driver is nearby") and POSTs
                             them to /integrations/parse-notification.
                             Parsed results are passed in here.

Output is a single context string that gets injected into the Gemini
system prompt so the AI can say:
  "You have a Zomato order #45821 arriving today — if this caller says
   they are the delivery person, that checks out."

All functions degrade gracefully — if Gmail is not configured or no
notifications were received, the context string is empty and the AI
simply has no order context.
"""

import logging
from typing import Optional

from app.services.gmail_service import (
    get_recent_order_emails,
    build_orders_context_string,
)

logger = logging.getLogger(__name__)


# -----------------------------------------------------------------------
# Android notification → order dict
# -----------------------------------------------------------------------

NOTIFICATION_PLATFORM_MAP = {
    "com.application.zomato":              "Zomato",
    "in.swiggy.android":                   "Swiggy",
    "com.amazon.mShop.android.shopping":   "Amazon",
    "com.flipkart.android":                "Flipkart",
    "com.blinkit.app":                     "Blinkit",
    "com.meesho.supply":                   "Meesho",
    "com.myntra.android":                  "Myntra",
    "com.bigbasket.mobileapp":             "BigBasket",
    "com.dunzo.user":                      "Dunzo",
    "com.nykaa.android":                   "Nykaa",
}

STATUS_KEYWORDS = {
    "out for delivery":  "out for delivery",
    "arriving today":    "arriving today",
    "arriving in":       "arriving soon",
    "delivered":         "delivered",
    "shipped":           "shipped",
    "dispatched":        "dispatched",
    "on its way":        "on its way",
    "order confirmed":   "confirmed",
    "driver is nearby":  "arriving soon",
    "nearby":            "arriving soon",
    "picked up":         "picked up",
    "packed":            "packed",
}


def parse_android_notification(notification: dict) -> Optional[dict]:
    """
    Parse a raw Android notification dict into an order dict.

    Input (from /integrations/parse-notification):
        {
            "package_name": "com.application.zomato",
            "title": "Order #45821",
            "body": "Your Zomato driver is nearby. Order arriving soon.",
        }

    Returns:
        {"platform": "Zomato", "order_id": "45821", "status": "arriving soon"}
        or None if not a recognised delivery notification.
    """
    import re

    package = notification.get("package_name", "")
    title   = notification.get("title", "") or ""
    body    = notification.get("body", "") or ""
    text    = f"{title} {body}".lower()

    # Identify platform
    platform = None
    for pkg, name in NOTIFICATION_PLATFORM_MAP.items():
        if pkg in package:
            platform = name
            break
    if not platform:
        # Fallback: match platform name in notification text
        for pkg, name in NOTIFICATION_PLATFORM_MAP.items():
            if name.lower() in text:
                platform = name
                break
    if not platform:
        return None

    # Extract order id
    order_id = None
    m = re.search(r"(?:order\s*#?|#)\s*([A-Z0-9\-]{4,})", f"{title} {body}", re.IGNORECASE)
    if m:
        order_id = m.group(1)

    # Extract status
    status = "update"
    for keyword, label in STATUS_KEYWORDS.items():
        if keyword in text:
            status = label
            break

    return {"platform": platform, "order_id": order_id, "status": status}


# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

async def build_delivery_context(
    user_id: str,
    pending_notifications: Optional[list[dict]] = None,
) -> str:
    """
    Build a delivery context string for the Gemini system prompt.

    Merges:
      - Gmail order emails (last 24h, if Gmail is configured for this user)
      - Android push notifications forwarded by the app

    Args:
        user_id:               Zentra user id (used to load Gmail OAuth token).
        pending_notifications: List of raw Android notification dicts that the
                               app collected before / during this call.

    Returns:
        A human-readable multi-line string, or "" if no context found.

    Example return value:
        Active delivery orders:
          - Zomato order #45821 is out for delivery
          - Amazon order #407-1234 has been shipped  (from notification)
    """
    orders = []
    seen_ids = set()

    # 1. Gmail orders
    try:
        gmail_orders = await get_recent_order_emails(user_id)
        for o in gmail_orders:
            key = (o.get("platform", ""), o.get("order_id", ""))
            if key not in seen_ids:
                orders.append({**o, "source": "gmail"})
                seen_ids.add(key)
    except Exception as e:
        logger.error(f"Gmail order fetch failed: {e}")

    # 2. Android notifications
    for notif in (pending_notifications or []):
        try:
            parsed = parse_android_notification(notif)
            if parsed:
                key = (parsed.get("platform", ""), parsed.get("order_id", ""))
                if key not in seen_ids:
                    orders.append({**parsed, "source": "notification"})
                    seen_ids.add(key)
        except Exception as e:
            logger.debug(f"Notification parse error: {e}")

    return build_orders_context_string(orders)


def to_active_orders_list(context_string: str) -> list[dict]:
    """
    Convert the context string back into a list of dicts compatible with
    gemini_service.build_system_prompt(active_orders=[...]).

    Each line like "  - Zomato order #45821 is out for delivery"
    becomes {"id": "45821", "description": "Zomato order #45821 is out for delivery"}
    """
    import re
    orders = []
    for line in context_string.splitlines():
        stripped = line.strip()
        # Skip empty lines and the header line
        if not stripped or stripped.startswith("Active delivery"):
            continue
        stripped = stripped.lstrip("- ").strip()
        if not stripped:
            continue
        m = re.search(r"#([A-Z0-9\-]+)", stripped)
        orders.append({
            "id": m.group(1) if m else "N/A",
            "description": stripped,
        })
    return orders