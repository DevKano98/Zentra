import logging
from fastapi import APIRouter, HTTPException
from app.database.queries import get_user_by_id
from app.database.supabase_client import supabase
from app.database.supabase_storage import upload_pdf, get_signed_url
from app.services.fir_service import generate_fir_pdf

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reports", tags=["reports"])


def _get_call_record(call_id: str) -> dict:
    response = (
        supabase.table("call_records").select("*").eq("id", call_id).execute()
    )
    if response.data:
        return response.data[0]
    return None


@router.post("/generate-fir/{call_id}")
async def generate_fir(call_id: str):
    call_record = _get_call_record(call_id)
    if not call_record:
        raise HTTPException(status_code=404, detail="Call record not found")

    if call_record.get("fir_pdf_url"):
        return {
            "status": "already_exists",
            "fir_pdf_url": call_record["fir_pdf_url"],
            "call_id": call_id,
        }

    try:
        pdf_bytes = await generate_fir_pdf(call_record)
        fir_url = upload_pdf(call_id, pdf_bytes)

        supabase.table("call_records").update({"fir_pdf_url": fir_url}).eq("id", call_id).execute()

        return {"status": "generated", "fir_pdf_url": fir_url, "call_id": call_id}
    except Exception as e:
        logger.error(f"FIR generation failed for call {call_id}: {e}")
        raise HTTPException(status_code=500, detail=f"FIR generation failed: {str(e)}")


@router.get("/download/{call_id}")
async def download_fir(call_id: str):
    call_record = _get_call_record(call_id)
    if not call_record:
        raise HTTPException(status_code=404, detail="Call record not found")

    audio_path = call_record.get("audio_path")
    fir_pdf_url = call_record.get("fir_pdf_url")

    result = {"call_id": call_id}

    if fir_pdf_url:
        fir_path = f"fir-reports/{call_id}.pdf"
        try:
            signed_url = get_signed_url(fir_path, expires_in=3600)
            result["fir_signed_url"] = signed_url
        except Exception as e:
            logger.warning(f"Could not get signed URL for FIR {call_id}: {e}")
            result["fir_pdf_url"] = fir_pdf_url

    if audio_path:
        try:
            audio_signed_url = get_signed_url(audio_path, expires_in=3600)
            result["audio_signed_url"] = audio_signed_url
        except Exception as e:
            logger.warning(f"Could not get signed URL for audio {call_id}: {e}")

    if not fir_pdf_url and not audio_path:
        raise HTTPException(status_code=404, detail="No report or audio found for this call")

    return result