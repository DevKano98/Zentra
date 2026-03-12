import json
import logging
from app.config import settings

logger = logging.getLogger(__name__)

_firebase_initialized = False

try:
    import firebase_admin
    from firebase_admin import credentials, messaging

    if settings.FIREBASE_CREDENTIALS_JSON:
        try:
            cred_dict = json.loads(settings.FIREBASE_CREDENTIALS_JSON)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info("Firebase Admin SDK initialized successfully")
        except json.JSONDecodeError as e:
            logger.warning(f"FIREBASE_CREDENTIALS_JSON is malformed JSON: {e}")
        except Exception as e:
            logger.warning(f"Firebase initialization failed: {e}")
    else:
        logger.warning("FIREBASE_CREDENTIALS_JSON is empty — FCM notifications disabled")
except ImportError:
    logger.warning("firebase-admin not installed — FCM notifications disabled")


async def send_fcm_notification(
    fcm_token: str, title: str, body: str, data: dict = {}
) -> bool:
    if not _firebase_initialized:
        logger.warning("FCM not initialized — skipping notification")
        return False

    if not fcm_token:
        return False

    try:
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="call_alerts",
                    sound="default",
                ),
            ),
        )
        messaging.send(message)
        logger.info(f"FCM notification sent to token: {fcm_token[:10]}...")
        return True
    except Exception as e:
        logger.error(f"FCM notification failed: {e}")
        return False


async def send_call_summary_telegram(chat_id: str, call_data: dict) -> None:
    if not settings.TELEGRAM_BOT_TOKEN or not chat_id:
        return

    try:
        from telegram import Bot

        bot = Bot(token=settings.TELEGRAM_BOT_TOKEN)

        category = call_data.get("category", "UNKNOWN")
        urgency = call_data.get("urgency_score", 0)
        caller = call_data.get("caller_number", "Unknown")
        caller_name = call_data.get("caller_name", "Unknown")
        outcome = call_data.get("call_outcome", "N/A")
        summary = call_data.get("summary", "No summary available.")

        emoji = "🚨" if category == "SCAM" else "📞"
        message_text = (
            f"{emoji} *Zentra Call Alert*\n\n"
            f"📱 Caller: {caller}\n"
            f"👤 Name: {caller_name}\n"
            f"📂 Category: {category}\n"
            f"⚡ Urgency: {urgency}/10\n"
            f"✅ Outcome: {outcome}\n\n"
            f"📝 Summary:\n{summary}"
        )

        await bot.send_message(
            chat_id=chat_id,
            text=message_text,
            parse_mode="Markdown",
        )
        logger.info(f"Telegram summary sent to chat_id: {chat_id}")
    except Exception as e:
        logger.error(f"Telegram notification failed: {e}")


async def send_scam_alert_telegram(chat_id: str, call_data: dict) -> None:
    if not settings.TELEGRAM_BOT_TOKEN or not chat_id:
        return

    try:
        from telegram import Bot

        bot = Bot(token=settings.TELEGRAM_BOT_TOKEN)

        caller = call_data.get("caller_number", "Unknown")
        category = call_data.get("category", "SCAM")
        tx_hash = call_data.get("blockchain_tx_hash", "N/A")
        fir_url = call_data.get("fir_pdf_url", "")

        message_text = (
            f"🚨 *SCAM CALL DETECTED & BLOCKED*\n\n"
            f"📱 Scammer Number: `{caller}`\n"
            f"📂 Category: {category}\n"
            f"🔗 Blockchain TX: `{tx_hash[:20]}...`\n"
        )
        if fir_url:
            message_text += f"📄 FIR Report: [Download]({fir_url})"

        await bot.send_message(
            chat_id=chat_id,
            text=message_text,
            parse_mode="Markdown",
        )
    except Exception as e:
        logger.error(f"Scam alert Telegram failed: {e}")