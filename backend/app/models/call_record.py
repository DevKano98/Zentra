from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class CallRecord(BaseModel):
    id: Optional[str] = None
    user_id: str
    caller_number: str
    caller_number_hash: str
    caller_name: Optional[str] = None
    category: str = "UNKNOWN"
    urgency_score: int = Field(default=0, ge=0, le=10)
    call_outcome: Optional[str] = Field(
        default=None,
        description="BLOCKED | DISMISSED | TRANSFERRED | COMPLETED",
    )
    transcript: Optional[str] = None
    summary: Optional[str] = None
    blockchain_tx_hash: Optional[str] = None
    fir_pdf_url: Optional[str] = None
    audio_path: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    duration_seconds: int = 0
    created_at: Optional[datetime] = None

    class Config:
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "user_id": "usr_abc123",
                "caller_number": "+919876543210",
                "caller_number_hash": "sha256_hash_here",
                "caller_name": "Rahul Sharma",
                "category": "SCAM",
                "urgency_score": 9,
                "call_outcome": "BLOCKED",
                "transcript": "Caller asked for OTP...",
                "summary": "Suspected scam call requesting OTP.",
                "blockchain_tx_hash": "0xabc123...",
                "fir_pdf_url": "https://storage.supabase.co/...",
                "audio_path": "audio/call_id.wav",
                "lat": 28.6139,
                "lng": 77.2090,
                "duration_seconds": 45,
                "created_at": "2025-01-01T12:00:00Z",
            }
        }