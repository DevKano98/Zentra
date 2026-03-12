"""
tests/test_ml.py

Unit tests for all ML and signal-processing modules:
  - scam_detector     (keyword detection, OTP detection)
  - classifier        (keyword fallback, urgency base scores)
  - emotion_detector  (neutral fallback, urgency modifier)
  - gemini_service    (parse_signals, build_system_prompt)
  - tts_service       (voice map, empty-text guard)
  - integration_service (parse_android_notification, build_orders_context_string)

All external API calls (Gemini, Deepgram, Sarvam, HuggingFace) are mocked
so these tests run fully offline with no API keys.

Run:
    cd backend
    pytest tests/test_ml.py -v
"""

import pytest
from unittest.mock import patch, MagicMock


# -----------------------------------------------------------------------
# Fixtures
# -----------------------------------------------------------------------

SCAM_TEXT_EN = (
    "Please share your OTP and KYC verify karo. "
    "Your account band ho jayega. aapko arrest kiya jayega."
)
SCAM_TEXT_HI = "lottery winner aapne lucky draw jeeta crore ka prize"
CLEAN_TEXT    = "Hi, I am calling from the delivery team about your Amazon package."
OTP_TEXT_EN   = "Please share the OTP to confirm your order."
OTP_TEXT_HI   = "OTP batao please"
EMPTY_TEXT    = ""


# ═══════════════════════════════════════════════════════════════════════
# scam_detector
# ═══════════════════════════════════════════════════════════════════════

class TestScamDetector:

    def test_detect_scam_keywords_positive(self):
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords(SCAM_TEXT_EN)
        assert result["is_scam"] is True
        assert len(result["matched_phrases"]) >= 2

    def test_detect_scam_keywords_hindi(self):
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords(SCAM_TEXT_HI)
        assert result["is_scam"] is True

    def test_detect_scam_keywords_clean(self):
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords(CLEAN_TEXT)
        assert result["is_scam"] is False

    def test_detect_scam_keywords_empty(self):
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords(EMPTY_TEXT)
        assert result["is_scam"] is False
        assert result["matched_phrases"] == []

    def test_detect_scam_keywords_returns_dict_shape(self):
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords(CLEAN_TEXT)
        assert "is_scam" in result
        assert "matched_phrases" in result
        assert isinstance(result["matched_phrases"], list)

    def test_detect_otp_request_english(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request(OTP_TEXT_EN) is True

    def test_detect_otp_request_hindi(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request(OTP_TEXT_HI) is True

    def test_detect_otp_request_cvv(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request("please tell me your CVV number") is True

    def test_detect_otp_request_aadhaar(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request("share your Aadhaar number with me") is True

    def test_detect_otp_request_clean(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request(CLEAN_TEXT) is False

    def test_detect_otp_request_empty(self):
        from app.ml.scam_detector import detect_otp_request
        assert detect_otp_request(EMPTY_TEXT) is False

    def test_single_keyword_not_scam(self):
        """One matching keyword alone should not trigger is_scam=True."""
        from app.ml.scam_detector import detect_scam_keywords
        result = detect_scam_keywords("Please do KYC update karo")
        # Only one keyword — should not be flagged
        assert result["is_scam"] is False


# ═══════════════════════════════════════════════════════════════════════
# classifier
# ═══════════════════════════════════════════════════════════════════════

class TestClassifier:

    def test_classify_scam_transcript(self):
        from app.ml.classifier import classify_call
        result = classify_call("lottery winner you have won crore prize arrested police narcotics")
        assert result["category"] == "SCAM"
        assert result["urgency_base"] == 9

    def test_classify_medical_transcript(self):
        from app.ml.classifier import classify_call
        result = classify_call("hospital emergency accident ambulance doctor")
        assert result["category"] == "MEDICAL"
        assert result["urgency_base"] == 8

    def test_classify_delivery_transcript(self):
        from app.ml.classifier import classify_call
        result = classify_call("delivery package courier Amazon Flipkart order dispatch")
        assert result["category"] == "DELIVERY"
        assert result["urgency_base"] == 6

    def test_classify_telemarketer_transcript(self):
        from app.ml.classifier import classify_call
        result = classify_call("special offer plan subscription upgrade discount deal")
        assert result["category"] == "TELEMARKETER"
        assert result["urgency_base"] == 2

    def test_classify_bank_transcript(self):
        from app.ml.classifier import classify_call
        result = classify_call("bank account transaction UPI NEFT transfer")
        assert result["category"] == "BANK"
        assert result["urgency_base"] == 5

    def test_classify_empty_returns_unknown(self):
        from app.ml.classifier import classify_call
        result = classify_call("")
        assert result["category"] == "UNKNOWN"
        assert result["confidence"] == 0.0

    def test_classify_returns_required_keys(self):
        from app.ml.classifier import classify_call
        result = classify_call("hello how are you")
        assert "category" in result
        assert "confidence" in result
        assert "urgency_base" in result

    def test_classify_confidence_in_range(self):
        from app.ml.classifier import classify_call
        result = classify_call("delivery package")
        assert 0.0 <= result["confidence"] <= 1.0

    def test_urgency_base_all_categories(self):
        from app.ml.classifier import CATEGORY_URGENCY_BASE
        assert CATEGORY_URGENCY_BASE["SCAM"]        == 9
        assert CATEGORY_URGENCY_BASE["MEDICAL"]     == 8
        assert CATEGORY_URGENCY_BASE["FAMILY"]      == 7
        assert CATEGORY_URGENCY_BASE["GOVERNMENT"]  == 6
        assert CATEGORY_URGENCY_BASE["DELIVERY"]    == 6
        assert CATEGORY_URGENCY_BASE["BANK"]        == 5
        assert CATEGORY_URGENCY_BASE["UNKNOWN"]     == 3
        assert CATEGORY_URGENCY_BASE["TELEMARKETER"]== 2


# ═══════════════════════════════════════════════════════════════════════
# emotion_detector
# ═══════════════════════════════════════════════════════════════════════

class TestEmotionDetector:

    def test_returns_neutral_fallback_on_empty(self):
        from app.ml.emotion_detector import detect_emotion, NEUTRAL_FALLBACK
        result = detect_emotion("")
        assert result == NEUTRAL_FALLBACK

    def test_returns_neutral_on_503(self):
        from app.ml.emotion_detector import detect_emotion, NEUTRAL_FALLBACK
        mock_resp = MagicMock()
        mock_resp.status_code = 503
        with patch("app.ml.emotion_detector.requests.post", return_value=mock_resp):
            result = detect_emotion("I am so angry")
        assert result == NEUTRAL_FALLBACK

    def test_returns_neutral_on_request_exception(self):
        import requests as req
        from app.ml.emotion_detector import detect_emotion, NEUTRAL_FALLBACK
        with patch("app.ml.emotion_detector.requests.post", side_effect=req.Timeout):
            result = detect_emotion("help me please")
        assert result == NEUTRAL_FALLBACK

    def test_parses_anger_correctly(self):
        from app.ml.emotion_detector import detect_emotion
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = [[
            {"label": "anger", "score": 0.75},
            {"label": "neutral", "score": 0.15},
            {"label": "fear", "score": 0.10},
        ]]
        with patch("app.ml.emotion_detector.requests.post", return_value=mock_resp):
            result = detect_emotion("This is outrageous!")
        assert result["dominant_emotion"] == "anger"
        assert result["urgency_modifier"] == 2

    def test_parses_joy_gives_negative_modifier(self):
        from app.ml.emotion_detector import detect_emotion
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = [[
            {"label": "joy", "score": 0.9},
            {"label": "neutral", "score": 0.1},
        ]]
        with patch("app.ml.emotion_detector.requests.post", return_value=mock_resp):
            result = detect_emotion("I am so happy!")
        assert result["dominant_emotion"] == "joy"
        assert result["urgency_modifier"] == -1

    def test_result_has_required_keys(self):
        from app.ml.emotion_detector import detect_emotion, NEUTRAL_FALLBACK
        with patch("app.ml.emotion_detector.requests.post", side_effect=Exception("err")):
            result = detect_emotion("test")
        assert "dominant_emotion" in result
        assert "emotions" in result
        assert "urgency_modifier" in result


# ═══════════════════════════════════════════════════════════════════════
# gemini_service — parse_signals & build_system_prompt (no API calls)
# ═══════════════════════════════════════════════════════════════════════

class TestGeminiService:

    def test_parse_signals_urgency_and_category(self):
        from app.services.gemini_service import parse_signals
        text = "Aapka kaam ho gaya.\nURGENCY:7 CATEGORY:DELIVERY"
        result = parse_signals(text)
        assert result["urgency"] == 7
        assert result["category"] == "DELIVERY"
        assert result["action"] is None

    def test_parse_signals_block_scam(self):
        from app.services.gemini_service import parse_signals
        text = "Yeh scammer hai.\nURGENCY:9 CATEGORY:SCAM\nACTION:BLOCK_SCAM"
        result = parse_signals(text)
        assert result["action"] == "BLOCK_SCAM"
        assert result["category"] == "SCAM"
        assert result["urgency"] == 9

    def test_parse_signals_block_otp(self):
        from app.services.gemini_service import parse_signals
        text = "Main OTP share nahi kar sakti.\nACTION:BLOCK_OTP URGENCY:10 CATEGORY:SCAM"
        result = parse_signals(text)
        assert result["action"] == "BLOCK_OTP"

    def test_parse_signals_end_call(self):
        from app.services.gemini_service import parse_signals
        text = "Theek hai, dhanyavaad.\nURGENCY:3 CATEGORY:DELIVERY\nACTION:END_CALL"
        result = parse_signals(text)
        assert result["action"] == "END_CALL"

    def test_parse_signals_clean_response_strips_markers(self):
        from app.services.gemini_service import parse_signals
        text = "Hello caller.\nURGENCY:5 CATEGORY:UNKNOWN"
        result = parse_signals(text)
        assert "URGENCY:" not in result["clean_response"]
        assert "CATEGORY:" not in result["clean_response"]
        assert "Hello caller." in result["clean_response"]

    def test_parse_signals_urgency_clamped_to_10(self):
        from app.services.gemini_service import parse_signals
        result = parse_signals("URGENCY:99 CATEGORY:SCAM")
        assert result["urgency"] == 10

    def test_parse_signals_urgency_clamped_to_1(self):
        from app.services.gemini_service import parse_signals
        result = parse_signals("URGENCY:0 CATEGORY:UNKNOWN")
        assert result["urgency"] == 1

    def test_parse_signals_defaults_on_missing(self):
        from app.services.gemini_service import parse_signals
        result = parse_signals("Namaste, main aapki madad kar sakti hoon.")
        assert result["urgency"] == 5
        assert result["category"] == "UNKNOWN"
        assert result["action"] is None

    def test_build_system_prompt_contains_user_name(self):
        from app.services.gemini_service import build_system_prompt
        prompt = build_system_prompt("Priya", "Mumbai")
        assert "Priya" in prompt

    def test_build_system_prompt_contains_city(self):
        from app.services.gemini_service import build_system_prompt
        prompt = build_system_prompt("Rahul", "Delhi")
        assert "Delhi" in prompt

    def test_build_system_prompt_hindi_female(self):
        from app.services.gemini_service import build_system_prompt
        prompt = build_system_prompt("Priya", "Mumbai", ai_language="hindi", ai_voice_gender="female")
        assert "bol rahi hoon" in prompt

    def test_build_system_prompt_hindi_male(self):
        from app.services.gemini_service import build_system_prompt
        prompt = build_system_prompt("Rahul", "Delhi", ai_language="hindi", ai_voice_gender="male")
        assert "bol raha hoon" in prompt

    def test_build_system_prompt_includes_hard_rules(self):
        from app.services.gemini_service import build_system_prompt
        prompt = build_system_prompt("User", "Mumbai")
        assert "OTP" in prompt
        assert "ACTION:BLOCK_OTP" in prompt
        assert "ACTION:BLOCK_SCAM" in prompt

    def test_build_system_prompt_active_orders(self):
        from app.services.gemini_service import build_system_prompt
        orders = [{"id": "12345", "description": "Zomato order #12345 is out for delivery"}]
        prompt = build_system_prompt("User", "Mumbai", active_orders=orders)
        assert "12345" in prompt


# ═══════════════════════════════════════════════════════════════════════
# tts_service — voice map and guard clauses (no real API call)
# ═══════════════════════════════════════════════════════════════════════

class TestTTSService:

    def test_voice_map_hindi_female(self):
        from app.services.tts_service import VOICE_MAP
        assert VOICE_MAP[("hindi", "female")] == "Priya"

    def test_voice_map_hindi_male(self):
        from app.services.tts_service import VOICE_MAP
        assert VOICE_MAP[("hindi", "male")] == "Rahul"

    def test_voice_map_english_female(self):
        from app.services.tts_service import VOICE_MAP
        assert VOICE_MAP[("english", "female")] == "Ritu"

    def test_voice_map_english_male(self):
        from app.services.tts_service import VOICE_MAP
        assert VOICE_MAP[("english", "male")] == "Rohan"

    def test_synthesize_empty_text_returns_empty_bytes(self):
        from app.services.tts_service import synthesize
        assert synthesize("") == b""
        assert synthesize("   ") == b""

    def test_synthesize_returns_bytes_on_success(self):
        import base64
        from app.services.tts_service import synthesize
        fake_wav = base64.b64encode(b"RIFF....fake_wav_data").decode()
        mock_resp = MagicMock()
        mock_resp.raise_for_status = MagicMock()
        mock_resp.json.return_value = {"audios": [fake_wav]}
        with patch("app.services.tts_service.requests.post", return_value=mock_resp):
            result = synthesize("Namaste", language="hindi", gender="female")
        assert isinstance(result, bytes)
        assert len(result) > 0

    def test_synthesize_returns_empty_on_request_error(self):
        import requests as req
        from app.services.tts_service import synthesize
        with patch("app.services.tts_service.requests.post", side_effect=req.RequestException("fail")):
            result = synthesize("Hello", language="english", gender="female")
        assert result == b""

    def test_synthesize_returns_empty_on_bad_response(self):
        from app.services.tts_service import synthesize
        mock_resp = MagicMock()
        mock_resp.raise_for_status = MagicMock()
        mock_resp.json.return_value = {"audios": []}   # missing audio
        with patch("app.services.tts_service.requests.post", return_value=mock_resp):
            result = synthesize("Hello")
        assert result == b""


# ═══════════════════════════════════════════════════════════════════════
# integration_service — Android notification parsing
# ═══════════════════════════════════════════════════════════════════════

class TestIntegrationService:

    def test_parse_zomato_notification(self):
        from app.services.integration_service import parse_android_notification
        notif = {
            "package_name": "com.application.zomato",
            "title": "Order #45821",
            "body": "Your Zomato driver is nearby. Order arriving soon.",
        }
        result = parse_android_notification(notif)
        assert result is not None
        assert result["platform"] == "Zomato"
        assert result["order_id"] == "45821"
        assert "arriving" in result["status"]

    def test_parse_amazon_notification(self):
        from app.services.integration_service import parse_android_notification
        notif = {
            "package_name": "com.amazon.mShop.android.shopping",
            "title": "Your package is out for delivery",
            "body": "Order #407-1234567 will arrive today.",
        }
        result = parse_android_notification(notif)
        assert result is not None
        assert result["platform"] == "Amazon"
        assert result["status"] == "out for delivery"

    def test_parse_swiggy_notification(self):
        from app.services.integration_service import parse_android_notification
        notif = {
            "package_name": "in.swiggy.android",
            "title": "Order Delivered!",
            "body": "Your Swiggy order has been delivered.",
        }
        result = parse_android_notification(notif)
        assert result is not None
        assert result["platform"] == "Swiggy"
        assert result["status"] == "delivered"

    def test_parse_unknown_package_returns_none(self):
        from app.services.integration_service import parse_android_notification
        notif = {
            "package_name": "com.random.app",
            "title": "Hello",
            "body": "Some random notification.",
        }
        result = parse_android_notification(notif)
        assert result is None

    def test_parse_notification_no_order_id(self):
        from app.services.integration_service import parse_android_notification
        notif = {
            "package_name": "com.application.zomato",
            "title": "Your food is on the way",
            "body": "Driver nearby.",
        }
        result = parse_android_notification(notif)
        assert result is not None
        assert result["order_id"] is None

    def test_build_orders_context_string_empty(self):
        from app.services.gmail_service import build_orders_context_string
        assert build_orders_context_string([]) == ""

    def test_build_orders_context_string_with_orders(self):
        from app.services.gmail_service import build_orders_context_string
        orders = [
            {"platform": "zomato", "order_id": "45821", "status": "out for delivery"},
            {"platform": "amazon", "order_id": "407-123", "status": "shipped"},
        ]
        result = build_orders_context_string(orders)
        assert "45821" in result
        assert "407-123" in result
        assert "out for delivery" in result

    def test_to_active_orders_list_parses_context(self):
        from app.services.integration_service import to_active_orders_list
        context = (
            "Active delivery orders:\n"
            "  - Zomato order #45821 is out for delivery\n"
            "  - Amazon order #407-123 has been shipped"
        )
        orders = to_active_orders_list(context)
        assert len(orders) == 2
        ids = [o["id"] for o in orders]
        assert "45821" in ids
        assert "407-123" in ids

    @pytest.mark.asyncio
    async def test_build_delivery_context_no_gmail_no_notifs(self):
        from app.services.integration_service import build_delivery_context
        with patch("app.services.integration_service.get_recent_order_emails", return_value=[]):
            result = await build_delivery_context(user_id="user_123")
        assert result == ""

    @pytest.mark.asyncio
    async def test_build_delivery_context_deduplicates(self):
        from app.services.integration_service import build_delivery_context
        gmail_orders = [{"platform": "zomato", "order_id": "111", "status": "shipped"}]
        notifs = [{
            "package_name": "com.application.zomato",
            "title": "Order #111",
            "body": "Zomato order out for delivery",
        }]
        with patch("app.services.integration_service.get_recent_order_emails", return_value=gmail_orders):
            result = await build_delivery_context(user_id="user_123", pending_notifications=notifs)
        # Order #111 should appear only once
        assert result.count("111") == 1