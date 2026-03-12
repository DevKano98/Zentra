import hashlib
import logging
from typing import Optional
from app.database.supabase_client import supabase

logger = logging.getLogger(__name__)


def save_call_record(user_id: str, call_data: dict) -> None:
    call_data["user_id"] = user_id
    supabase.table("call_records").insert(call_data).execute()


def get_call_history(user_id: str, limit: int = 50) -> list:
    response = (
        supabase.table("call_records")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return response.data or []


def get_recent_calls(user_id: str, limit: int = 5) -> list:
    response = (
        supabase.table("call_records")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return response.data or []


def get_user_by_id(user_id: str) -> Optional[dict]:
    response = (
        supabase.table("users").select("*").eq("id", user_id).execute()
    )
    if response.data:
        return response.data[0]
    return None


def get_user_by_phone(phone_number: str) -> Optional[dict]:
    phone_hash = hashlib.sha256(phone_number.encode()).hexdigest()
    response = (
        supabase.table("users").select("*").eq("phone_hash", phone_hash).execute()
    )
    if response.data:
        return response.data[0]
    return None


def create_user(user_data: dict) -> dict:
    response = supabase.table("users").insert(user_data).execute()
    return response.data[0] if response.data else {}


def update_user_preferences(user_id: str, prefs: dict) -> None:
    supabase.table("users").update({"preferences": prefs}).eq("id", user_id).execute()


def check_scam_db(phone_hash: str) -> dict:
    response = (
        supabase.table("scam_numbers")
        .select("*")
        .eq("phone_hash", phone_hash)
        .execute()
    )
    if response.data:
        record = response.data[0]
        return {
            "is_known_scam": True,
            "count": record.get("report_count", 1),
            "category": record.get("category", "UNKNOWN"),
        }
    return {"is_known_scam": False, "count": 0, "category": None}


def add_to_scam_db(phone_hash: str, category: str) -> None:
    existing = (
        supabase.table("scam_numbers")
        .select("*")
        .eq("phone_hash", phone_hash)
        .execute()
    )
    if existing.data:
        current_count = existing.data[0].get("report_count", 1)
        supabase.table("scam_numbers").update(
            {"report_count": current_count + 1, "category": category}
        ).eq("phone_hash", phone_hash).execute()
    else:
        supabase.table("scam_numbers").insert(
            {"phone_hash": phone_hash, "category": category, "report_count": 1}
        ).execute()


def get_scam_heatmap_data() -> list:
    response = (
        supabase.table("call_records")
        .select("lat, lng, urgency_score, category")
        .eq("category", "SCAM")
        .not_.is_("lat", "null")
        .not_.is_("lng", "null")
        .execute()
    )
    result = []
    for row in response.data or []:
        if row.get("lat") and row.get("lng"):
            result.append(
                {
                    "lat": row["lat"],
                    "lng": row["lng"],
                    "intensity": row.get("urgency_score", 5),
                }
            )
    return result