"""
classifier.py  —  Call category and urgency classifier

Two-tier approach:
  Tier 1: Trained TF-IDF + LogisticRegression model (pkl files)
          Loaded once at startup. If pkl files are absent (fresh install),
          falls through to Tier 2 automatically.

  Tier 2: Keyword-scoring fallback
          Covers all 8 categories using curated Hindi + English word lists.
          Always available — no file dependencies.

Category urgency base scores (aligned with Gemini URGENCY signal):
  SCAM        → 9   (high — needs immediate action)
  MEDICAL     → 8   (high — could be life-threatening)
  FAMILY      → 7   (medium-high — personal, potentially urgent)
  GOVERNMENT  → 6   (medium — official, needs attention)
  DELIVERY    → 6   (medium — user has active orders)
  BANK        → 5   (medium — financial but not always urgent)
  UNKNOWN     → 3   (low — gather more info)
  TELEMARKETER→ 2   (low — can safely dismiss)

Training data: backend/app/ml/labeled_calls.csv
  Columns: transcript (str), category (str matching above)
  Minimum: 50 samples per category recommended for good accuracy
  Run:     python -m app.ml.train_classifier
"""

import logging
import pickle
from pathlib import Path

logger = logging.getLogger(__name__)

CATEGORY_URGENCY_BASE: dict[str, int] = {
    "SCAM":         9,
    "MEDICAL":      8,
    "FAMILY":       7,
    "GOVERNMENT":   6,
    "DELIVERY":     6,
    "BANK":         5,
    "UNKNOWN":      3,
    "TELEMARKETER": 2,
}

VALID_CATEGORIES = set(CATEGORY_URGENCY_BASE.keys())

_MODEL_DIR  = Path(__file__).parent
_vectorizer = None
_clf        = None
_models_loaded = False


# ─────────────────────────────────────────────────────────────────────────────
# Model loading
# ─────────────────────────────────────────────────────────────────────────────

def _load_models() -> None:
    """
    Load trained pkl files from the ml/ directory.
    Called once at startup by main.py lifespan handler.
    Safe to call multiple times — idempotent.
    """
    global _vectorizer, _clf, _models_loaded
    if _models_loaded:
        return

    vec_path = _MODEL_DIR / "tfidf_vectorizer.pkl"
    clf_path = _MODEL_DIR / "call_classifier.pkl"

    if vec_path.exists() and clf_path.exists():
        try:
            with open(vec_path, "rb") as f:
                _vectorizer = pickle.load(f)
            with open(clf_path, "rb") as f:
                _clf = pickle.load(f)
            logger.info("ML call classifier loaded (TF-IDF + LogisticRegression)")
        except Exception as e:
            logger.warning(f"ML model load failed: {e} — keyword fallback will be used")
            _vectorizer = None
            _clf        = None
    else:
        logger.warning(
            "ML pkl files not found — using keyword fallback. "
            "Run: python -m app.ml.train_classifier to train."
        )

    _models_loaded = True


# ─────────────────────────────────────────────────────────────────────────────
# Keyword fallback
# ─────────────────────────────────────────────────────────────────────────────

# Comprehensive bilingual (Hindi + English) keyword lists per category
_KEYWORD_LISTS: dict[str, list[str]] = {
    "SCAM": [
        # English
        "otp", "lottery", "prize", "won", "winner", "lucky draw",
        "arrested", "police case", "narcotics", "money laundering",
        "suspend", "suspended", "block", "kyc", "verify account",
        "remote access", "anydesk", "teamviewer", "gift card",
        "insurance claim", "refund", "emi waiver", "loan approved",
        "custom duty", "parcel seized", "fedex", "dhl blocked",
        "income tax notice", "trai", "rbi official", "cbi officer",
        "drug parcel", "share screen", "google play card",
        # Hindi/Hinglish
        "inam", "jeet liya", "crore", "giraftaar", "giraftari",
        "account band", "band ho jayega",
        "abhi karo", "turant", "ghar pe mat batana", "secret rakho",
        "police ko mat", "kyc update", "aadhaar link",
    ],
    "MEDICAL": [
        "hospital", "emergency", "accident", "ambulance", "doctor",
        "surgery", "operation", "icu", "blood", "injury", "hurt",
        "medicine", "prescription", "clinic", "health",
        # Hindi
        "aspatal", "dawakhana", "dawa", "chot lagi", "haadsa",
        "doctor bulao", "tablet", "injection",
    ],
    "FAMILY": [
        "family", "mom", "mother", "dad", "father", "brother", "sister",
        "son", "daughter", "wife", "husband", "relative", "uncle", "aunt",
        "grandma", "grandpa", "cousin",
        # Hindi
        "mummy", "papa", "bhai", "behen", "beta", "beti", "patni",
        "pati", "ghar", "ghar wale", "maa", "baap", "dada", "dadi",
        "nana", "nani", "chacha", "chachi", "maama", "maami",
    ],
    "DELIVERY": [
        "delivery", "package", "parcel", "courier", "order",
        "dispatch", "shipped", "tracking", "out for delivery",
        "deliver", "amazon", "flipkart", "zomato", "swiggy",
        "blinkit", "meesho", "myntra", "bigbasket", "dunzo",
        # Hindi
        "delivery wala", "parcel aaya", "order aa gaya",
        "ghar pe deliver", "delivery boy",
    ],
    "BANK": [
        "bank", "account", "transaction", "transfer", "balance",
        "upi", "neft", "imps", "rtgs", "cheque", "loan", "emi",
        "credit card", "debit card", "atm", "statement", "ifsc",
        "savings", "current account", "fd", "fixed deposit",
        "hdfc", "icici", "sbi", "axis", "kotak", "paytm", "phonepe",
        # Hindi
        "khata", "paise", "kiraya", "EMI", "byaj", "bachat",
    ],
    "TELEMARKETER": [
        "offer", "plan", "subscription", "upgrade", "discount",
        "deal", "scheme", "cashback", "recharge", "broadband",
        "insurance", "mutual fund", "credit card offer",
        "special offer", "limited time", "free trial",
        "congratulations", "selected", "chosen",
        # Hindi
        "offer hai", "scheme hai", "plan lena", "free mein",
        "special price", "aaj ka offer",
    ],
    "GOVERNMENT": [
        "government", "tax", "income tax", "gst", "passport",
        "driving licence", "voter id", "ration card", "pension",
        "trai", "rbi", "sebi", "municipality", "panchayat",
        "electricity", "water bill", "property tax",
        # Hindi
        "sarkar", "sarkari", "vibhag", "bijli", "paani",
        "tehsildar", "collector", "adhikari", "notice",
    ],
}


def _keyword_classify(text: str) -> dict:
    """Score text against all category keyword lists and return best match."""
    text_lower = text.lower()

    scores: dict[str, int] = {cat: 0 for cat in VALID_CATEGORIES}

    for category, keywords in _KEYWORD_LISTS.items():
        for kw in keywords:
            if kw in text_lower:
                scores[category] += 1

    scores["UNKNOWN"] = 0  # UNKNOWN only wins if nothing else matches

    best_cat   = max(scores, key=lambda k: scores[k])
    best_score = scores[best_cat]

    if best_score == 0:
        return {
            "category":    "UNKNOWN",
            "confidence":  0.30,
            "urgency_base": CATEGORY_URGENCY_BASE["UNKNOWN"],
            "source":      "keyword_fallback",
        }

    # Rough confidence: more keyword hits = higher confidence, capped at 0.88
    confidence = min(0.88, 0.35 + best_score * 0.08)

    return {
        "category":    best_cat,
        "confidence":  round(confidence, 3),
        "urgency_base": CATEGORY_URGENCY_BASE[best_cat],
        "source":      "keyword_fallback",
    }


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

def classify_call(transcript: str) -> dict:
    """
    Classify a call transcript into one of 8 categories.

    Tries trained ML model first; falls back to keyword scoring if model
    is unavailable or raises an error.

    Args:
        transcript: Full or partial call transcript string.

    Returns:
        {
            "category":    str   — one of VALID_CATEGORIES
            "confidence":  float — 0.0-1.0
            "urgency_base": int  — base urgency score for this category (1-10)
            "source":      str   — "ml_model" | "keyword_fallback"
        }
    """
    _load_models()

    if not transcript or not transcript.strip():
        return {
            "category":    "UNKNOWN",
            "confidence":  0.0,
            "urgency_base": CATEGORY_URGENCY_BASE["UNKNOWN"],
            "source":      "empty_input",
        }

    # Tier 1: trained model
    if _vectorizer is not None and _clf is not None:
        try:
            features    = _vectorizer.transform([transcript])
            prediction  = _clf.predict(features)[0].upper()
            proba       = _clf.predict_proba(features)[0]
            confidence  = float(max(proba))

            if prediction not in VALID_CATEGORIES:
                prediction = "UNKNOWN"

            # Only trust the ML model if it is sufficiently confident.
            # Low-confidence predictions fall through to the keyword fallback.
            if confidence >= 0.50:
                return {
                    "category":    prediction,
                    "confidence":  round(confidence, 3),
                    "urgency_base": CATEGORY_URGENCY_BASE[prediction],
                    "source":      "ml_model",
                }
        except Exception as e:
            logger.error(f"ML classification error: {e} — falling back to keywords")

    # Tier 2: keyword fallback
    return _keyword_classify(transcript)