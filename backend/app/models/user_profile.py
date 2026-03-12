from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class UserPreferences(BaseModel):
    urgency_threshold: int = Field(default=5, ge=1, le=10)
    ai_language: str = Field(default="hindi", description="hindi or english")
    ai_voice_gender: str = Field(default="female", description="female or male")
    auto_block_scam: bool = True
    telegram_alerts: bool = False


class UserProfile(BaseModel):
    id: Optional[str] = None
    phone_number: Optional[str] = None
    phone_hash: Optional[str] = None
    name: str
    city: str
    fcm_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    preferences: UserPreferences = Field(default_factory=UserPreferences)
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    class Config:
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "Priya Sharma",
                "city": "Mumbai",
                "fcm_token": "fcm_token_here",
                "telegram_chat_id": "123456789",
                "preferences": {
                    "urgency_threshold": 5,
                    "ai_language": "hindi",
                    "ai_voice_gender": "female",
                    "auto_block_scam": True,
                    "telegram_alerts": True,
                },
            }
        }