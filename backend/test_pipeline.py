from dotenv import load_dotenv
load_dotenv()

print("=== TEST 1: ML CLASSIFIER ===")
from app.ml.classifier import classify_call
tests = [
    ("Namaste main Zomato delivery ke liye aa raha hoon order 45821", "DELIVERY"),
    ("Main RBI officer bol raha hoon aapka account band ho jayega", "SCAM"),
    ("Doctor ne appointment di hai kal subah 10 baje", "MEDICAL"),
    ("Bhai main hoon naya number hai mera", "FAMILY"),
    ("Special insurance offer hai aapke liye", "TELEMARKETER"),
]
for transcript, expected in tests:
    result = classify_call(transcript)
    status = "✅" if result["category"] == expected else "❌"
    print(f"{status} Expected:{expected} Got:{result['category']} Confidence:{result['confidence']:.2f}")

print("\n=== TEST 2: SCAM DETECTOR ===")
from app.ml.scam_detector import detect_scam_keywords, detect_otp_request
scam_tests = [
    ("Main CBI officer bol raha hoon digital arrest ho sakta hai OTP share karo", True),
    ("Aapka Amazon package deliver karne aa raha hoon", False),
    ("lottery winner aapne lucky draw jeeta crore ka prize", True),
]
for text, expected in scam_tests:
    result = detect_scam_keywords(text)
    status = "✅" if result["is_scam"] == expected else "❌"
    print(f"{status} is_scam:{result['is_scam']} phrases:{result['matched_phrases']}")

print("\n=== TEST 3: OTP DETECTOR ===")
otp_tests = [
    ("Please share the OTP to verify your account", True),
    ("OTP batao please abhi", True),
    ("Main delivery ke liye aa raha hoon", False),
]
for text, expected in otp_tests:
    result = detect_otp_request(text)
    status = "✅" if result == expected else "❌"
    print(f"{status} otp_detected:{result}")

print("\n=== TEST 4: GEMINI AI ===")
from app.services.gemini_service import build_system_prompt, generate_response, parse_signals
system_prompt = build_system_prompt("Priya Sharma", "Mumbai", ai_language="hindi", ai_voice_gender="female")
print(f"✅ System prompt built — {len(system_prompt)} chars")
print(f"   OTP rule present: {'BLOCK_OTP' in system_prompt}")
conversation_history = [
    {"role": "user", "parts": [{"text": "Namaste main Zomato delivery ke liye call kar raha hoon order 45821"}]}
]
print("   Calling Gemini 2.5 Flash...")
response = generate_response(conversation_history, system_prompt)
signals = parse_signals(response)
print(f"✅ Gemini responded")
print(f"   Urgency:  {signals['urgency']}")
print(f"   Category: {signals['category']}")
print(f"   Action:   {signals['action']}")
print(f"   AI said:  {signals['clean_response'][:80]}")

print("\n=== TEST 5: SARVAM TTS ===")
from app.services.tts_service import synthesize
tts_tests = [
    ("Namaste main Priya bol rahi hoon aap kaise hain", "hindi", "female"),
    ("Namaste main Rahul bol raha hoon", "hindi", "male"),
    ("Hello this is Ritu speaking how may I help you", "english", "female"),
]
for text, lang, gender in tts_tests:
    audio = synthesize(text, language=lang, gender=gender)
    status = "✅" if len(audio) > 0 else "❌"
    print(f"{status} {lang}/{gender}: {len(audio)} bytes")

print("\n=== ALL PIPELINE TESTS DONE ===")
