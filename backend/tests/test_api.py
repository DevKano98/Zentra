"""
tests/test_api.py

Integration tests for all FastAPI routes.
All external services (Supabase, Gemini, Deepgram, Sarvam, Blockchain,
Firebase, Telegram) are mocked — no real credentials needed.

Run:
    cd backend
    pytest tests/test_api.py -v

Run a single class:
    pytest tests/test_api.py::TestHealthRoute -v
"""

import pytest
import uuid
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient


# -----------------------------------------------------------------------
# Shared test data
# -----------------------------------------------------------------------

FAKE_USER_ID   = str(uuid.uuid4())
FAKE_CALL_ID   = str(uuid.uuid4())
FAKE_FCM_TOKEN = "fake_fcm_token_abc123"

FAKE_USER = {
    "id": FAKE_USER_ID,
    "phone_number": "+919876543210",
    "phone_hash": "abc123hash",
    "name": "Priya Sharma",
    "city": "Mumbai",
    "fcm_token": FAKE_FCM_TOKEN,
    "telegram_chat_id": None,
    "email": None,
    "preferences": {
        "urgency_threshold": 5,
        "ai_language": "hindi",
        "ai_voice_gender": "female",
        "auto_block_scam": True,
        "telegram_alerts": False,
    },
}

FAKE_CALL_RECORD = {
    "id": FAKE_CALL_ID,
    "user_id": FAKE_USER_ID,
    "caller_number": "+911234567890",
    "caller_number_hash": "callerhash",
    "caller_name": "Rahul",
    "category": "DELIVERY",
    "urgency_score": 4,
    "call_outcome": "COMPLETED",
    "transcript": "Hi I am calling about your delivery.",
    "summary": "Delivery confirmation call.",
    "blockchain_tx_hash": "0xabc",
    "fir_pdf_url": None,
    "audio_path": None,
    "lat": 19.076,
    "lng": 72.877,
    "duration_seconds": 30,
    "created_at": "2025-01-01T12:00:00",
}


# -----------------------------------------------------------------------
# App fixture — patch all I/O before importing app
# -----------------------------------------------------------------------

@pytest.fixture(scope="module")
def client():
    """
    Create a TestClient with all external dependencies mocked at import time.
    """
    with patch("app.database.supabase_client.create_client", return_value=MagicMock()), \
         patch("app.services.gemini_service.genai.Client", return_value=MagicMock()), \
         patch("app.services.notification_service._firebase_initialized", False), \
         patch("app.ml.classifier._load_models", return_value=None):

        from app.main import app
        with TestClient(app, raise_server_exceptions=False) as c:
            yield c


# ═══════════════════════════════════════════════════════════════════════
# Health
# ═══════════════════════════════════════════════════════════════════════

class TestHealthRoute:

    def test_health_ok(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["version"] == "1.0.0"


# ═══════════════════════════════════════════════════════════════════════
# /users — register, login, profile, preferences
# ═══════════════════════════════════════════════════════════════════════

class TestUserRoutes:

    def test_register_new_user(self, client):
        with patch("app.routes.user_routes.get_user_by_phone", return_value=None), \
             patch("app.routes.user_routes.create_user", return_value=FAKE_USER):
            resp = client.post("/users/register", json={
                "phone_number": "+919876543210",
                "name": "Priya Sharma",
                "city": "Mumbai",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert "token" in data
        assert data["is_new"] is True

    def test_register_existing_user_returns_token(self, client):
        with patch("app.routes.user_routes.get_user_by_phone", return_value=FAKE_USER):
            resp = client.post("/users/register", json={
                "phone_number": "+919876543210",
                "name": "Priya Sharma",
                "city": "Mumbai",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["is_new"] is False
        assert "token" in data

    def test_login_existing_user(self, client):
        with patch("app.routes.user_routes.get_user_by_phone", return_value=FAKE_USER):
            resp = client.post("/users/login", json={"phone_number": "+919876543210"})
        assert resp.status_code == 200
        assert "token" in resp.json()

    def test_login_unknown_user_returns_404(self, client):
        with patch("app.routes.user_routes.get_user_by_phone", return_value=None):
            resp = client.post("/users/login", json={"phone_number": "+910000000000"})
        assert resp.status_code == 404

    def test_get_profile(self, client):
        with patch("app.routes.user_routes.get_user_by_id", return_value=FAKE_USER):
            resp = client.get(f"/users/profile/{FAKE_USER_ID}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["name"] == "Priya Sharma"
        # phone_number should be stripped from profile response
        assert "phone_number" not in data

    def test_get_profile_not_found(self, client):
        with patch("app.routes.user_routes.get_user_by_id", return_value=None):
            resp = client.get(f"/users/profile/{FAKE_USER_ID}")
        assert resp.status_code == 404

    def test_update_preferences(self, client):
        with patch("app.routes.user_routes.get_user_by_id", return_value=FAKE_USER), \
             patch("app.routes.user_routes.update_user_preferences", return_value=None):
            resp = client.put(f"/users/preferences/{FAKE_USER_ID}", json={
                "urgency_threshold": 7,
                "ai_language": "english",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["preferences"]["urgency_threshold"] == 7
        assert data["preferences"]["ai_language"] == "english"

    def test_update_preferences_user_not_found(self, client):
        with patch("app.routes.user_routes.get_user_by_id", return_value=None):
            resp = client.put(f"/users/preferences/{FAKE_USER_ID}", json={"urgency_threshold": 3})
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════════════
# /calls — process-turn, save-record, history, recent, report-scam
# ═══════════════════════════════════════════════════════════════════════

class TestCallRoutes:

    def _mock_process_turn_deps(self):
        """Context manager stack for process-turn endpoint."""
        return [
            patch("app.routes.call_routes.get_user_by_id",      return_value=FAKE_USER),
            patch("app.routes.call_routes.detect_otp_request",  return_value=False),
            patch("app.routes.call_routes.detect_scam_keywords",return_value={"is_scam": False, "matched_phrases": []}),
            patch("app.routes.call_routes.check_scam_db",       return_value={"is_known_scam": False, "count": 0, "category": None}),
            patch("app.routes.call_routes.generate_response",   return_value="Theek hai. URGENCY:4 CATEGORY:DELIVERY"),
            patch("app.routes.call_routes.parse_signals",       return_value={
                "urgency": 4, "category": "DELIVERY",
                "clean_response": "Theek hai.", "action": None,
            }),
            patch("app.routes.call_routes.synthesize",          return_value=b"fake_wav"),
        ]

    def test_process_turn_clean_call(self, client):
        patches = self._mock_process_turn_deps()
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5], patches[6]:
            resp = client.post("/calls/process-turn", json={
                "user_id":           FAKE_USER_ID,
                "call_id":           FAKE_CALL_ID,
                "caller_number":     "+911234567890",
                "transcript_turn":   "Hi, I am calling about your delivery.",
                "conversation_history": [],
            })
        assert resp.status_code == 200
        data = resp.json()
        assert "ai_response" in data
        assert "ai_audio_b64" in data
        assert "urgency" in data
        assert "category" in data
        assert data["category"] == "DELIVERY"
        assert data["action"] is None

    def test_process_turn_otp_request_blocked_immediately(self, client):
        with patch("app.routes.call_routes.get_user_by_id",     return_value=FAKE_USER), \
             patch("app.routes.call_routes.detect_otp_request", return_value=True), \
             patch("app.routes.call_routes.synthesize",         return_value=b"fake_wav"):
            resp = client.post("/calls/process-turn", json={
                "user_id":         FAKE_USER_ID,
                "call_id":         FAKE_CALL_ID,
                "caller_number":   "+911234567890",
                "transcript_turn": "Please send me the OTP",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["action"] == "BLOCK_OTP"
        assert data["category"] == "SCAM"
        assert data["urgency"] == 10

    def test_process_turn_known_scam_number(self, client):
        patches = self._mock_process_turn_deps()
        with patches[0], patches[1], \
             patch("app.routes.call_routes.detect_scam_keywords", return_value={"is_scam": False, "matched_phrases": []}), \
             patch("app.routes.call_routes.check_scam_db",        return_value={"is_known_scam": True, "count": 5, "category": "SCAM"}), \
             patch("app.routes.call_routes.generate_response",    return_value="Suspicious caller. URGENCY:9 CATEGORY:SCAM"), \
             patch("app.routes.call_routes.parse_signals",        return_value={
                 "urgency": 9, "category": "SCAM",
                 "clean_response": "Suspicious caller.", "action": "BLOCK_SCAM",
             }), \
             patches[6]:
            resp = client.post("/calls/process-turn", json={
                "user_id":         FAKE_USER_ID,
                "call_id":         FAKE_CALL_ID,
                "caller_number":   "+911234567890",
                "transcript_turn": "Hello I am calling from the bank",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["category"] == "SCAM"

    def test_process_turn_user_not_found(self, client):
        with patch("app.routes.call_routes.get_user_by_id", return_value=None):
            resp = client.post("/calls/process-turn", json={
                "user_id":         "nonexistent",
                "call_id":         FAKE_CALL_ID,
                "caller_number":   "+911234567890",
                "transcript_turn": "Hello",
            })
        assert resp.status_code == 404

    def test_save_record_clean_call(self, client):
        with patch("app.routes.call_routes.summarize_call",       new_callable=AsyncMock, return_value="Delivery call."), \
             patch("app.routes.call_routes.upload_audio",         return_value="audio/fake.wav"), \
             patch("app.routes.call_routes.write_to_blockchain",  new_callable=AsyncMock, return_value="0xtxhash"), \
             patch("app.routes.call_routes.save_call_record",     return_value=None), \
             patch("app.routes.call_routes.get_user_by_id",       return_value=FAKE_USER), \
             patch("app.routes.call_routes.add_to_scam_db",       return_value=None):
            resp = client.post("/calls/save-record", json={
                "user_id":       FAKE_USER_ID,
                "call_id":       FAKE_CALL_ID,
                "caller_number": "+911234567890",
                "transcript":    "Hi I am calling about your Amazon delivery.",
                "duration_seconds": 45,
                "final_action":  "END_CALL",
                "final_category":"DELIVERY",
                "final_urgency": 4,
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "saved"
        assert data["call_id"] == FAKE_CALL_ID

    def test_save_record_scam_generates_fir(self, client):
        with patch("app.routes.call_routes.summarize_call",      new_callable=AsyncMock, return_value="Scam call."), \
             patch("app.routes.call_routes.write_to_blockchain", new_callable=AsyncMock, return_value="0xtxhash"), \
             patch("app.routes.call_routes.generate_fir_pdf",   new_callable=AsyncMock, return_value=b"%PDF-fake"), \
             patch("app.routes.call_routes.upload_pdf",         return_value="https://storage/fir.pdf"), \
             patch("app.routes.call_routes.add_to_scam_db",     return_value=None), \
             patch("app.routes.call_routes.save_call_record",   return_value=None), \
             patch("app.routes.call_routes.get_user_by_id",     return_value=FAKE_USER):
            resp = client.post("/calls/save-record", json={
                "user_id":       FAKE_USER_ID,
                "call_id":       FAKE_CALL_ID,
                "caller_number": "+911234567890",
                "transcript":    "OTP batao aapka account suspend ho jayega",
                "duration_seconds": 20,
                "final_action":  "BLOCK_SCAM",
                "final_category":"SCAM",
                "final_urgency": 9,
            })
        assert resp.status_code == 200
        assert resp.json()["status"] == "saved"

    def test_call_history(self, client):
        with patch("app.routes.call_routes.get_call_history", return_value=[FAKE_CALL_RECORD]):
            resp = client.get(f"/calls/history/{FAKE_USER_ID}")
        assert resp.status_code == 200
        data = resp.json()
        assert "calls" in data
        assert len(data["calls"]) == 1
        assert data["calls"][0]["id"] == FAKE_CALL_ID

    def test_call_history_empty(self, client):
        with patch("app.routes.call_routes.get_call_history", return_value=[]):
            resp = client.get(f"/calls/history/{FAKE_USER_ID}")
        assert resp.status_code == 200
        assert resp.json()["calls"] == []

    def test_recent_calls(self, client):
        with patch("app.routes.call_routes.get_recent_calls", return_value=[FAKE_CALL_RECORD]):
            resp = client.get(f"/calls/recent/{FAKE_USER_ID}")
        assert resp.status_code == 200
        assert len(resp.json()["calls"]) == 1

    def test_report_scam(self, client):
        with patch("app.routes.call_routes.add_to_scam_db", return_value=None):
            resp = client.post("/calls/report-scam", json={
                "caller_number": "+911234567890",
                "category": "SCAM",
            })
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "reported"
        assert "phone_hash" in data


# ═══════════════════════════════════════════════════════════════════════
# /dashboard
# ═══════════════════════════════════════════════════════════════════════

class TestDashboardRoutes:

    def _mock_supabase_stats(self):
        mock_sb = MagicMock()
        # total_calls
        mock_sb.table.return_value.select.return_value.execute.return_value.count = 100
        return mock_sb

    def test_statistics_returns_expected_keys(self, client):
        with patch("app.routes.dashboard_routes.supabase") as mock_sb:
            # Chain all the supabase calls to return sensible values
            def make_chain(count=0, data=None):
                m = MagicMock()
                m.count = count
                m.data = data or []
                return m

            mock_sb.table.return_value.select.return_value.execute.return_value = make_chain(50)
            mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value = make_chain(10)
            mock_sb.table.return_value.select.return_value.order.return_value.range.return_value.execute.return_value = make_chain(data=[])

            resp = client.get("/dashboard/statistics")
        assert resp.status_code == 200
        data = resp.json()
        for key in ["total_calls", "scam_calls", "blocked_calls", "category_breakdown", "avg_urgency_score"]:
            assert key in data

    def test_scam_heatmap(self, client):
        with patch("app.routes.dashboard_routes.get_scam_heatmap_data", return_value=[
            {"lat": 19.076, "lng": 72.877, "intensity": 9},
            {"lat": 28.613, "lng": 77.209, "intensity": 7},
        ]):
            resp = client.get("/dashboard/scam-heatmap")
        assert resp.status_code == 200
        data = resp.json()
        assert "heatmap" in data
        assert data["total_points"] == 2
        assert data["heatmap"][0]["lat"] == 19.076

    def test_call_log(self, client):
        with patch("app.routes.dashboard_routes.supabase") as mock_sb:
            chain = MagicMock()
            chain.data = [FAKE_CALL_RECORD]
            mock_sb.table.return_value.select.return_value.order.return_value.range.return_value.execute.return_value = chain
            resp = client.get("/dashboard/call-log")
        assert resp.status_code == 200
        data = resp.json()
        assert "calls" in data

    def test_call_log_limit_param(self, client):
        with patch("app.routes.dashboard_routes.supabase") as mock_sb:
            chain = MagicMock()
            chain.data = []
            mock_sb.table.return_value.select.return_value.order.return_value.range.return_value.execute.return_value = chain
            resp = client.get("/dashboard/call-log?limit=10&offset=0")
        assert resp.status_code == 200
        assert resp.json()["limit"] == 10


# ═══════════════════════════════════════════════════════════════════════
# /reports
# ═══════════════════════════════════════════════════════════════════════

class TestReportRoutes:

    def test_generate_fir_new(self, client):
        record_no_fir = {**FAKE_CALL_RECORD, "category": "SCAM", "fir_pdf_url": None}
        with patch("app.routes.report_routes._get_call_record", return_value=record_no_fir), \
             patch("app.routes.report_routes.generate_fir_pdf",  new_callable=AsyncMock, return_value=b"%PDF-fake"), \
             patch("app.routes.report_routes.upload_pdf",        return_value="https://storage/fir.pdf"), \
             patch("app.routes.report_routes.supabase") as mock_sb:
            mock_sb.table.return_value.update.return_value.eq.return_value.execute.return_value = MagicMock()
            resp = client.post(f"/reports/generate-fir/{FAKE_CALL_ID}")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "generated"
        assert "fir_pdf_url" in data

    def test_generate_fir_already_exists(self, client):
        record_with_fir = {**FAKE_CALL_RECORD, "fir_pdf_url": "https://storage/existing.pdf"}
        with patch("app.routes.report_routes._get_call_record", return_value=record_with_fir):
            resp = client.post(f"/reports/generate-fir/{FAKE_CALL_ID}")
        assert resp.status_code == 200
        assert resp.json()["status"] == "already_exists"

    def test_generate_fir_not_found(self, client):
        with patch("app.routes.report_routes._get_call_record", return_value=None):
            resp = client.post(f"/reports/generate-fir/{FAKE_CALL_ID}")
        assert resp.status_code == 404

    def test_download_fir_returns_signed_url(self, client):
        record_with_fir = {**FAKE_CALL_RECORD, "fir_pdf_url": "https://storage/fir.pdf"}
        with patch("app.routes.report_routes._get_call_record", return_value=record_with_fir), \
             patch("app.routes.report_routes.get_signed_url",   return_value="https://signed.url/fir.pdf"):
            resp = client.get(f"/reports/download/{FAKE_CALL_ID}")
        assert resp.status_code == 200
        assert "fir_signed_url" in resp.json()

    def test_download_fir_not_found(self, client):
        with patch("app.routes.report_routes._get_call_record", return_value=None):
            resp = client.get(f"/reports/download/{FAKE_CALL_ID}")
        assert resp.status_code == 404


# ═══════════════════════════════════════════════════════════════════════
# /integrations
# ═══════════════════════════════════════════════════════════════════════

class TestIntegrationRoutes:

    def test_parse_zomato_notification(self, client):
        resp = client.post("/integrations/parse-notification", json={
            "package_name": "com.application.zomato",
            "title": "Order #45821",
            "body": "Your Zomato driver is nearby. Arriving soon.",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["parsed"] is True
        assert data["type"] == "delivery_order"
        assert data["order"]["app"] == "Zomato"

    def test_parse_amazon_notification(self, client):
        resp = client.post("/integrations/parse-notification", json={
            "package_name": "com.amazon.mShop.android.shopping",
            "title": "Your package",
            "body": "Out for delivery today.",
        })
        assert resp.status_code == 200
        assert resp.json()["parsed"] is True

    def test_parse_unknown_notification(self, client):
        resp = client.post("/integrations/parse-notification", json={
            "package_name": "com.random.unrelated.app",
            "title": "Hello",
            "body": "Just a random notification.",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["parsed"] is False
        assert data["type"] == "unknown"
        assert data["order"] is None

    def test_parse_notification_context_for_ai(self, client):
        resp = client.post("/integrations/parse-notification", json={
            "package_name": "in.swiggy.android",
            "title": "Order on its way",
            "body": "Swiggy order #88999 will arrive in 10 minutes.",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["parsed"] is True
        assert data["context_for_ai"] is not None
        assert "Swiggy" in data["context_for_ai"]