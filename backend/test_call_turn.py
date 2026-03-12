from dotenv import load_dotenv
load_dotenv()
import requests

BASE_URL = "http://localhost:8000"
TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5YjY3MDM5Ny0zYWY2LTQ5YTUtODZiMi1iYWI2ZGY4ZWQxODciLCJleHAiOjE3NzMzMTg1OTV9.XLDtIu1D4uRNHdgvTP3C25xLA6EpWEju_HjsILaUuNc"
USER_ID = "9b670397-3af6-49a5-86b2-bab6df8ed187"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}

print("=== CALL TURN TEST ===\n")

# Turn 1 — Delivery call
print("Turn 1 — Delivery call:")
resp = requests.post(f"{BASE_URL}/calls/process-turn", headers=HEADERS, json={
    "user_id": USER_ID,
    "call_id": "test-call-001",
    "caller_number": "+911234567890",
    "transcript_turn": "Namaste main Zomato delivery person bol raha hoon order number 45821 gate pe aao",
    "conversation_history": []
})
data = resp.json()
print(f"  Status:   {resp.status_code}")
print(f"  Category: {data.get('category')}")
print(f"  Urgency:  {data.get('urgency')}")
print(f"  Action:   {data.get('action')}")
print(f"  AI said:  {data.get('ai_response','')[:80]}")
print(f"  Audio:    {len(data.get('ai_audio_b64',''))} chars base64")

# Turn 2 — OTP blocked
print("\nTurn 2 — OTP steal attempt:")
resp2 = requests.post(f"{BASE_URL}/calls/process-turn", headers=HEADERS, json={
    "user_id": USER_ID,
    "call_id": "test-call-002",
    "caller_number": "+910000000001",
    "transcript_turn": "Please share your OTP to verify your SBI account immediately",
    "conversation_history": []
})
data2 = resp2.json()
print(f"  Action:   {data2.get('action')} ← should be BLOCK_OTP")
print(f"  Urgency:  {data2.get('urgency')} ← should be 10")
print(f"  Category: {data2.get('category')} ← should be SCAM")

# Turn 3 — Scam call
print("\nTurn 3 — RBI scam:")
resp3 = requests.post(f"{BASE_URL}/calls/process-turn", headers=HEADERS, json={
    "user_id": USER_ID,
    "call_id": "test-call-003",
    "caller_number": "+910000000002",
    "transcript_turn": "Main RBI officer bol raha hoon aapka account band ho jayega digital arrest hoga",
    "conversation_history": []
})
data3 = resp3.json()
print(f"  Category: {data3.get('category')} ← should be SCAM")
print(f"  Urgency:  {data3.get('urgency')} ← should be 8-10")
print(f"  Scam:     {data3.get('scam_matches', [])}")

print("\n=== CALL TURN TEST COMPLETE ===")
