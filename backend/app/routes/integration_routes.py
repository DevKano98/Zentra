import logging
import re
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/integrations", tags=["integrations"])


class NotificationPayload(BaseModel):
    package_name: str
    title: Optional[str] = None
    body: Optional[str] = None
    ticker: Optional[str] = None
    user_id: Optional[str] = None


ORDER_PATTERNS = {
    "amazon": {
        "patterns": [
            r"(?:out for delivery|will be delivered|arriving|delivered)",
            r"order\s*#?\s*([A-Z0-9\-]+)",
        ],
        "name": "Amazon",
    },
    "flipkart": {
        "patterns": [
            r"(?:out for delivery|shipped|delivered|arriving)",
            r"order\s*id\s*:?\s*([A-Z0-9]+)",
        ],
        "name": "Flipkart",
    },
    "zomato": {
        "patterns": [
            r"(?:on its way|arriving in|delivered|picked up)",
            r"order\s*#?\s*(\d+)",
        ],
        "name": "Zomato",
    },
    "swiggy": {
        "patterns": [
            r"(?:on its way|arriving|delivered|out for delivery)",
            r"order\s*#?\s*(\d+)",
        ],
        "name": "Swiggy",
    },
    "blinkit": {
        "patterns": [
            r"(?:on its way|arriving|delivered|packed)",
        ],
        "name": "Blinkit",
    },
    "meesho": {
        "patterns": [
            r"(?:shipped|out for delivery|delivered)",
            r"order\s*id\s*:?\s*([A-Z0-9]+)",
        ],
        "name": "Meesho",
    },
}


def _parse_order_from_notification(package_name: str, title: str, body: str) -> Optional[dict]:
    text = f"{title or ''} {body or ''}".lower()

    matched_app = None
    for pkg_key, app_info in ORDER_PATTERNS.items():
        if pkg_key in package_name.lower():
            matched_app = app_info
            break

    if not matched_app:
        for pkg_key, app_info in ORDER_PATTERNS.items():
            if pkg_key in text:
                matched_app = app_info
                break

    if not matched_app:
        return None

    order_id = None
    for pattern in matched_app.get("patterns", []):
        match = re.search(pattern, text, re.IGNORECASE)
        if match and match.lastindex:
            order_id = match.group(1)
            break

    status = "unknown"
    status_keywords = {
        "out for delivery": "out_for_delivery",
        "delivered": "delivered",
        "shipped": "shipped",
        "arriving": "arriving",
        "on its way": "on_the_way",
        "packed": "packed",
        "picked up": "picked_up",
    }
    for keyword, status_value in status_keywords.items():
        if keyword in text:
            status = status_value
            break

    return {
        "app": matched_app["name"],
        "order_id": order_id,
        "status": status,
        "raw_title": title,
        "raw_body": body,
    }


@router.post("/parse-notification")
async def parse_notification(body: NotificationPayload):
    order_info = _parse_order_from_notification(
        package_name=body.package_name,
        title=body.title or "",
        body=body.body or "",
    )

    if order_info:
        return {
            "parsed": True,
            "type": "delivery_order",
            "order": order_info,
            "context_for_ai": (
                f"Active {order_info['app']} order"
                + (f" #{order_info['order_id']}" if order_info["order_id"] else "")
                + f" — Status: {order_info['status']}"
            ),
        }

    return {
        "parsed": False,
        "type": "unknown",
        "order": None,
        "context_for_ai": None,
    }