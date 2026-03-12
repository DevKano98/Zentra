"""
Supabase client initialization.

=== FULL SQL SCHEMA ===

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number TEXT UNIQUE NOT NULL,
    phone_hash TEXT UNIQUE NOT NULL,
    name TEXT,
    city TEXT,
    fcm_token TEXT,
    telegram_chat_id TEXT,
    preferences JSONB DEFAULT '{
        "urgency_threshold": 5,
        "ai_language": "hindi",
        "ai_voice_gender": "female",
        "auto_block_scam": true,
        "telegram_alerts": false
    }',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Call records table
CREATE TABLE IF NOT EXISTS call_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    caller_number TEXT NOT NULL,
    caller_number_hash TEXT NOT NULL,
    caller_name TEXT,
    category TEXT DEFAULT 'UNKNOWN',
    urgency_score INTEGER DEFAULT 0,
    call_outcome TEXT CHECK (call_outcome IN ('BLOCKED','DISMISSED','TRANSFERRED','COMPLETED')),
    transcript TEXT,
    summary TEXT,
    blockchain_tx_hash TEXT,
    fir_pdf_url TEXT,
    audio_path TEXT,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    duration_seconds INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Scam numbers table
CREATE TABLE IF NOT EXISTS scam_numbers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_hash TEXT UNIQUE NOT NULL,
    category TEXT,
    report_count INTEGER DEFAULT 1,
    last_reported_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_call_records_user_id ON call_records(user_id);
CREATE INDEX IF NOT EXISTS idx_call_records_created_at ON call_records(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_records_caller_hash ON call_records(caller_number_hash);
CREATE INDEX IF NOT EXISTS idx_scam_numbers_phone_hash ON scam_numbers(phone_hash);

=== END SQL SCHEMA ===
"""

from supabase import create_client, Client
from app.config import settings

supabase: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)