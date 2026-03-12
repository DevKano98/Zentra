import hashlib
import logging
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException
from jose import JWTError, jwt
from pydantic import BaseModel

from app.config import settings
from app.database.queries import (
    create_user,
    get_user_by_id,
    get_user_by_phone,
    update_user_preferences,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/users", tags=["users"])

JWT_ALGORITHM = "HS256"
JWT_EXPIRY_MINUTES = 30


def _hash_phone(phone: str) -> str:
    return hashlib.sha256(phone.encode()).hexdigest()


def _create_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=JWT_EXPIRY_MINUTES)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.APP_SECRET_KEY, algorithm=JWT_ALGORITHM)


class RegisterRequest(BaseModel):
    phone_number: str
    name: str
    city: str
    fcm_token: Optional[str] = None
    telegram_chat_id: Optional[str] = None


class LoginRequest(BaseModel):
    phone_number: str


class UpdatePreferencesRequest(BaseModel):
    urgency_threshold: Optional[int] = None
    ai_language: Optional[str] = None
    ai_voice_gender: Optional[str] = None
    auto_block_scam: Optional[bool] = None
    telegram_alerts: Optional[bool] = None


@router.post("/register")
async def register(body: RegisterRequest):
    phone_hash = _hash_phone(body.phone_number)

    existing = get_user_by_phone(body.phone_number)
    if existing:
        token = _create_token(existing["id"])
        return {"token": token, "is_new": False}

    user_data = {
        "phone_number": body.phone_number,
        "phone_hash": phone_hash,
        "name": body.name,
        "city": body.city,
        "fcm_token": body.fcm_token,
        "telegram_chat_id": body.telegram_chat_id,
        "preferences": {
            "urgency_threshold": 5,
            "ai_language": "hindi",
            "ai_voice_gender": "female",
            "auto_block_scam": True,
            "telegram_alerts": False,
        },
    }

    user = create_user(user_data)
    if not user:
        raise HTTPException(status_code=500, detail="Failed to create user")

    token = _create_token(user["id"])
    return {"user": user, "token": token, "is_new": True}


@router.post("/login")
async def login(body: LoginRequest):
    user = get_user_by_phone(body.phone_number)

    if not user:
        raise HTTPException(status_code=404, detail="User not found. Please register first.")

    token = _create_token(user["id"])
    return {"token": token}


@router.get("/profile/{user_id}")
async def get_profile(user_id: str):
    user = get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    safe_user = {k: v for k, v in user.items() if k not in ("phone_number",)}
    return safe_user


@router.put("/preferences/{user_id}")
async def update_preferences(user_id: str, body: UpdatePreferencesRequest):
    user = get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    current_prefs = user.get("preferences", {})
    updates = body.dict(exclude_none=True)
    merged_prefs = {**current_prefs, **updates}

    update_user_preferences(user_id, merged_prefs)
    return {"status": "updated", "preferences": merged_prefs}