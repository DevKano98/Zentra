"""
train_classifier.py  —  Train the Zentra call classifier

Reads labeled_calls.csv, trains TF-IDF + LogisticRegression, saves pkl files.

CSV format (backend/app/ml/labeled_calls.csv):
  transcript,category
  "Hello I am calling about your Amazon delivery package","DELIVERY"
  "Your account will be suspended please share OTP","SCAM"
  ...

Categories: SCAM, MEDICAL, FAMILY, GOVERNMENT, DELIVERY, BANK, UNKNOWN, TELEMARKETER
Minimum samples per category: 50 recommended (10 absolute minimum for stratified split)

scikit-learn spec:
  TfidfVectorizer(max_features=5000, ngram_range=(1,2), sublinear_tf=True, min_df=2)
  LogisticRegression(max_iter=1000, C=1.0, solver='lbfgs', multi_class='multinomial')

Usage:
  cd backend
  python -m app.ml.train_classifier

Output:
  app/ml/tfidf_vectorizer.pkl
  app/ml/call_classifier.pkl

After training:
  git add app/ml/tfidf_vectorizer.pkl app/ml/call_classifier.pkl
  git commit -m "chore: update trained classifier models"
"""

import csv
import logging
import pickle
import sys
from collections import Counter
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s — %(levelname)s — %(message)s",
)
logger = logging.getLogger(__name__)

MODEL_DIR = Path(__file__).parent
CSV_PATH  = MODEL_DIR / "labeled_calls.csv"

VALID_CATEGORIES = {
    "SCAM", "MEDICAL", "FAMILY", "GOVERNMENT",
    "DELIVERY", "BANK", "UNKNOWN", "TELEMARKETER",
}


def load_data(csv_path: Path) -> tuple[list[str], list[str]]:
    """Load and validate training data from CSV."""
    if not csv_path.exists():
        logger.error(f"Training data not found: {csv_path}")
        logger.error("Create labeled_calls.csv with columns: transcript,category")
        sys.exit(1)

    transcripts = []
    labels      = []
    skipped     = 0

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        if not reader.fieldnames or "transcript" not in reader.fieldnames or "category" not in reader.fieldnames:
            logger.error("CSV must have columns: transcript, category")
            sys.exit(1)

        for i, row in enumerate(reader, start=2):
            transcript = row.get("transcript", "").strip()
            category   = row.get("category",   "").strip().upper()

            if not transcript:
                logger.warning(f"Row {i}: empty transcript — skipping")
                skipped += 1
                continue

            if category not in VALID_CATEGORIES:
                logger.warning(f"Row {i}: unknown category '{category}' — skipping")
                skipped += 1
                continue

            transcripts.append(transcript)
            labels.append(category)

    logger.info(f"Loaded {len(transcripts)} samples, skipped {skipped}")

    if len(transcripts) < 16:
        logger.error(
            f"Only {len(transcripts)} valid samples — need at least 16 "
            f"(2 per category for train/test split)"
        )
        sys.exit(1)

    # Warn on thin categories
    counts = Counter(labels)
    logger.info("Category distribution:")
    for cat in sorted(VALID_CATEGORIES):
        count = counts.get(cat, 0)
        bar   = "█" * min(count, 40)
        warn  = " ⚠️  < 10 samples" if count < 10 else ""
        logger.info(f"  {cat:14s} {count:4d}  {bar}{warn}")

    return transcripts, labels


def train(csv_path: Path = CSV_PATH) -> None:
    try:
        from sklearn.feature_extraction.text import TfidfVectorizer
        from sklearn.linear_model         import LogisticRegression
        from sklearn.model_selection      import train_test_split, cross_val_score
        from sklearn.metrics              import accuracy_score, classification_report
        import numpy as np
    except ImportError:
        logger.error("scikit-learn not installed. Run: pip install scikit-learn")
        sys.exit(1)

    # ── Load data ──────────────────────────────────────────────────────
    transcripts, labels = load_data(csv_path)

    # ── Vectorise ──────────────────────────────────────────────────────
    vectorizer = TfidfVectorizer(
        max_features=5000,
        ngram_range=(1, 2),    # unigrams + bigrams
        sublinear_tf=True,     # log(tf+1) — reduces impact of frequent terms
        min_df=2,              # ignore terms in fewer than 2 documents
        strip_accents="unicode",
        analyzer="word",
        token_pattern=r"(?u)\b\w+\b",
    )

    X = vectorizer.fit_transform(transcripts)
    logger.info(f"Vocabulary size: {len(vectorizer.vocabulary_)} features")

    # ── Train / test split ─────────────────────────────────────────────
    # Use stratify to ensure all categories appear in both splits
    try:
        X_train, X_test, y_train, y_test = train_test_split(
            X, labels,
            test_size=0.2,
            random_state=42,
            stratify=labels,
        )
    except ValueError:
        logger.warning("Stratified split failed (too few samples) — using random split")
        X_train, X_test, y_train, y_test = train_test_split(
            X, labels, test_size=0.2, random_state=42
        )

    # ── Train classifier ───────────────────────────────────────────────
    clf = LogisticRegression(
        max_iter=1000,
        C=1.0,
        solver="lbfgs",
        multi_class="multinomial",
        class_weight="balanced",   # compensates for uneven category counts
    )
    clf.fit(X_train, y_train)

    # ── Evaluate ───────────────────────────────────────────────────────
    y_pred    = clf.predict(X_test)
    accuracy  = accuracy_score(y_test, y_pred)

    logger.info(f"\n{'═'*50}")
    logger.info(f"Test accuracy: {accuracy:.4f}  ({accuracy*100:.1f}%)")
    logger.info(f"\nClassification Report:\n"
                f"{classification_report(y_test, y_pred, zero_division=0)}")

    # 5-fold cross-validation on full dataset
    try:
        cv_scores = cross_val_score(clf, X, labels, cv=5, scoring="accuracy")
        logger.info(
            f"5-fold CV accuracy: {cv_scores.mean():.4f} ± {cv_scores.std():.4f}"
        )
    except Exception as e:
        logger.warning(f"Cross-validation failed: {e}")

    # ── Save models ────────────────────────────────────────────────────
    vec_path = MODEL_DIR / "tfidf_vectorizer.pkl"
    clf_path = MODEL_DIR / "call_classifier.pkl"

    with open(vec_path, "wb") as f:
        pickle.dump(vectorizer, f)
    with open(clf_path, "wb") as f:
        pickle.dump(clf, f)

    logger.info(f"\nModels saved:")
    logger.info(f"  {vec_path}")
    logger.info(f"  {clf_path}")

    # ── Next steps ─────────────────────────────────────────────────────
    logger.info("\n>>> Commit pkl files to git <<<")
    logger.info("  git add app/ml/tfidf_vectorizer.pkl app/ml/call_classifier.pkl")
    logger.info("  git commit -m 'chore: update trained classifier models'")
    logger.info("  git push")


if __name__ == "__main__":
    train()