import logging
from fastapi import APIRouter, Query
from app.database.queries import get_scam_heatmap_data
from app.database.supabase_client import supabase

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/statistics")
async def get_statistics():
    try:
        total_response = supabase.table("call_records").select("id", count="exact").execute()
        total_calls = total_response.count or 0

        scam_response = (
            supabase.table("call_records")
            .select("id", count="exact")
            .eq("category", "SCAM")
            .execute()
        )
        scam_calls = scam_response.count or 0

        blocked_response = (
            supabase.table("call_records")
            .select("id", count="exact")
            .eq("call_outcome", "BLOCKED")
            .execute()
        )
        blocked_calls = blocked_response.count or 0

        scam_db_response = supabase.table("scam_numbers").select("id", count="exact").execute()
        known_scam_numbers = scam_db_response.count or 0

        categories_response = (
            supabase.table("call_records")
            .select("category")
            .execute()
        )
        category_counts = {}
        for row in categories_response.data or []:
            cat = row.get("category", "UNKNOWN")
            category_counts[cat] = category_counts.get(cat, 0) + 1

        avg_urgency_response = (
            supabase.table("call_records").select("urgency_score").execute()
        )
        urgency_scores = [
            r["urgency_score"]
            for r in (avg_urgency_response.data or [])
            if r.get("urgency_score") is not None
        ]
        avg_urgency = sum(urgency_scores) / len(urgency_scores) if urgency_scores else 0

        return {
            "total_calls": total_calls,
            "scam_calls": scam_calls,
            "blocked_calls": blocked_calls,
            "known_scam_numbers": known_scam_numbers,
            "category_breakdown": category_counts,
            "avg_urgency_score": round(avg_urgency, 2),
            "scam_block_rate": round((blocked_calls / total_calls * 100) if total_calls > 0 else 0, 2),
        }
    except Exception as e:
        logger.error(f"Dashboard statistics error: {e}")
        return {
            "total_calls": 0,
            "scam_calls": 0,
            "blocked_calls": 0,
            "known_scam_numbers": 0,
            "category_breakdown": {},
            "avg_urgency_score": 0,
            "scam_block_rate": 0,
        }


@router.get("/scam-heatmap")
async def scam_heatmap():
    data = get_scam_heatmap_data()
    return {"heatmap": data, "total_points": len(data)}


@router.get("/call-log")
async def call_log(limit: int = Query(default=100, le=500), offset: int = 0):
    try:
        response = (
            supabase.table("call_records")
            .select("id, caller_number, caller_name, category, urgency_score, call_outcome, created_at, duration_seconds, blockchain_tx_hash")
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return {
            "calls": response.data or [],
            "limit": limit,
            "offset": offset,
        }
    except Exception as e:
        logger.error(f"Call log error: {e}")
        return {"calls": [], "limit": limit, "offset": offset}