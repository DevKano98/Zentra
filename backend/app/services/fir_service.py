import logging
import re
from datetime import datetime
from pathlib import Path
from jinja2 import Environment, FileSystemLoader, select_autoescape
from app.database.supabase_storage import upload_pdf

logger = logging.getLogger(__name__)

TEMPLATES_DIR = Path(__file__).parent.parent / "templates"

_jinja_env = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=select_autoescape(["html"]),
)

SCAM_INDICATORS = [
    "otp", "pin", "password", "cvv", "aadhaar", "account number",
    "credit card", "debit card", "kyc", "verify your", "urgent",
    "suspended", "arrested", "police", "narcotics", "money laundering",
    "lottery", "prize", "won", "reward", "insurance claim", "refund",
    "bank official", "rbi", "income tax", "emi waiver", "loan approved",
]


def _highlight_scam_phrases(transcript: str) -> str:
    if not transcript:
        return ""
    highlighted = transcript
    for phrase in SCAM_INDICATORS:
        pattern = re.compile(re.escape(phrase), re.IGNORECASE)
        highlighted = pattern.sub(
            f'<span style="color:red;font-weight:bold;">{phrase.upper()}</span>',
            highlighted,
        )
    return highlighted


async def generate_fir_pdf(call_record: dict) -> bytes:
    transcript = call_record.get("transcript", "")
    highlighted_transcript = _highlight_scam_phrases(transcript)

    template_context = {
        "report_id": call_record.get("id", "N/A"),
        "generated_at": datetime.utcnow().strftime("%d %B %Y, %H:%M UTC"),
        "user_id": call_record.get("user_id", "N/A"),
        "caller_number": call_record.get("caller_number", "Unknown"),
        "caller_name": call_record.get("caller_name", "Unknown"),
        "category": call_record.get("category", "UNKNOWN"),
        "urgency_score": call_record.get("urgency_score", 0),
        "call_outcome": call_record.get("call_outcome", "N/A"),
        "duration_seconds": call_record.get("duration_seconds", 0),
        "created_at": call_record.get("created_at", "N/A"),
        "summary": call_record.get("summary", "No summary available."),
        "highlighted_transcript": highlighted_transcript,
        "blockchain_tx_hash": call_record.get("blockchain_tx_hash", "Pending"),
        "lat": call_record.get("lat"),
        "lng": call_record.get("lng"),
        "verification_url": f"https://zentra.app/verify/{call_record.get('id', '')}",
    }

    try:
        from weasyprint import HTML  # lazy import — GTK DLLs only needed at call time
        template = _jinja_env.get_template("fir_report.html")
        rendered_html = template.render(**template_context)
        pdf_bytes = HTML(string=rendered_html).write_pdf()
        return pdf_bytes
    except Exception as e:
        logger.error(f"FIR PDF generation failed: {e}")
        raise