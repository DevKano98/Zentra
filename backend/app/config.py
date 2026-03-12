from dotenv import load_dotenv
load_dotenv()

import os


class Settings:
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    DEEPGRAM_API_KEY: str = os.getenv("DEEPGRAM_API_KEY", "")
    SARVAM_API_KEY: str = os.getenv("SARVAM_API_KEY", "")
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
    SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "")
    SUPABASE_STORAGE_BUCKET: str = os.getenv("SUPABASE_STORAGE_BUCKET", "zentra-files")
    ALCHEMY_RPC: str = os.getenv("ALCHEMY_RPC", "")
    CONTRACT_ADDRESS: str = os.getenv("CONTRACT_ADDRESS", "")
    DEPLOYER_PRIVATE_KEY: str = os.getenv("DEPLOYER_PRIVATE_KEY", "")
    FIREBASE_CREDENTIALS_JSON: str = os.getenv("FIREBASE_CREDENTIALS_JSON", "")
    TELEGRAM_BOT_TOKEN: str = os.getenv("TELEGRAM_BOT_TOKEN", "")
    HUGGINGFACE_API_KEY: str = os.getenv("HUGGINGFACE_API_KEY", "")
    APP_SECRET_KEY: str = os.getenv("APP_SECRET_KEY", "")

    def __init__(self):
        required = [
            "GEMINI_API_KEY",
            "DEEPGRAM_API_KEY",
            "SARVAM_API_KEY",
            "SUPABASE_URL",
            "SUPABASE_KEY",
            "SUPABASE_STORAGE_BUCKET",
            "ALCHEMY_RPC",
            "DEPLOYER_PRIVATE_KEY",
            "HUGGINGFACE_API_KEY",
            "APP_SECRET_KEY",
        ]
        missing = [key for key in required if not getattr(self, key)]
        if missing:
            raise RuntimeError(
                f"Missing required environment variables: {', '.join(missing)}"
            )


settings = Settings()