import logging
from app.config import settings
from app.database.supabase_client import supabase

logger = logging.getLogger(__name__)

BUCKET = settings.SUPABASE_STORAGE_BUCKET


def upload_pdf(call_id: str, pdf_bytes: bytes) -> str:
    path = f"fir-reports/{call_id}.pdf"
    supabase.storage.from_(BUCKET).upload(
        path,
        pdf_bytes,
        file_options={"content-type": "application/pdf", "upsert": "true"},
    )
    return f"{settings.SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{path}"


def upload_audio(call_id: str, audio_bytes: bytes) -> str:
    path = f"audio/{call_id}.wav"
    supabase.storage.from_(BUCKET).upload(
        path,
        audio_bytes,
        file_options={"content-type": "audio/wav", "upsert": "true"},
    )
    return path


def get_signed_url(path: str, expires_in: int = 3600) -> str:
    response = supabase.storage.from_(BUCKET).create_signed_url(path, expires_in)
    return response["signedURL"]


def get_public_url(path: str) -> str:
    return f"{settings.SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{path}"