import os
import json
import base64
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)

SCOPES = ['https://www.googleapis.com/auth/gmail.send']


def _get_credentials() -> Credentials | None:
    """
    Load Gmail credentials entirely from environment variables.
    No files needed — works on Render, Railway, any ephemeral filesystem.
    """
    token_json = os.getenv('GMAIL_TOKEN_JSON')
    creds_json = os.getenv('GMAIL_CREDENTIALS_JSON')

    if not token_json or not creds_json:
        logger.warning('Gmail env vars not set — Gmail disabled')
        return None

    try:
        token_data = json.loads(token_json)
        creds = Credentials(
            token=token_data.get('token'),
            refresh_token=token_data.get('refresh_token'),
            token_uri=token_data.get('token_uri', 'https://oauth2.googleapis.com/token'),
            client_id=token_data.get('client_id'),
            client_secret=token_data.get('client_secret'),
            scopes=token_data.get('scopes', SCOPES),
        )

        # Refresh token if expired
        if creds.expired and creds.refresh_token:
            creds.refresh(Request())
            # Log new token so you can update the env var if needed
            logger.info('Gmail token refreshed — update GMAIL_TOKEN_JSON env var if persistent')

        return creds

    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f'Gmail credentials parse error: {e}')
        return None


def _build_service():
    creds = _get_credentials()
    if not creds:
        return None
    try:
        return build('gmail', 'v1', credentials=creds)
    except Exception as e:
        logger.error(f'Gmail service build failed: {e}')
        return None


async def send_email(
    to: str,
    subject: str,
    body_html: str,
    body_text: str = '',
) -> bool:
    """
    Send an email via Gmail API.
    Returns True on success, False on any failure.
    Never raises — safe to call from anywhere.
    """
    try:
        service = _build_service()
        if not service:
            logger.warning('Gmail service unavailable — skipping email')
            return False

        message = MIMEMultipart('alternative')
        message['to'] = to
        message['subject'] = subject

        if body_text:
            message.attach(MIMEText(body_text, 'plain'))
        message.attach(MIMEText(body_html, 'html'))

        encoded = base64.urlsafe_b64encode(message.as_bytes()).decode()
        result = service.users().messages().send(
            userId='me',
            body={'raw': encoded}
        ).execute()

        logger.info(f'Email sent to {to} — message ID: {result.get("id")}')
        return True

    except HttpError as e:
        logger.error(f'Gmail HTTP error: {e}')
        return False
    except Exception as e:
        logger.error(f'Gmail send failed: {e}')
        return False


async def send_scam_alert_email(to: str, call_data: dict) -> bool:
    """Send a scam call alert email to the user."""
    number = call_data.get('caller_number', 'Unknown')
    category = call_data.get('category', 'SCAM')
    urgency = call_data.get('urgency_score', 'N/A')
    summary = call_data.get('summary', 'No summary available')
    tx_hash = call_data.get('blockchain_tx_hash', '')
    fir_url = call_data.get('fir_pdf_url', '')

    verify_url = f'https://amoy.polygonscan.com/tx/{tx_hash}' if tx_hash else ''

    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto">
      <div style="background:#4F46E5;padding:20px;border-radius:8px 8px 0 0">
        <h1 style="color:white;margin:0">🛡️ Zentra Scam Alert</h1>
      </div>
      <div style="background:#fff;padding:24px;border:1px solid #e5e7eb;border-top:none">
        <div style="background:#FEF2F2;border:1px solid #FECACA;border-radius:8px;padding:16px;margin-bottom:20px">
          <h2 style="color:#DC2626;margin:0 0 8px">🚨 {category} Detected</h2>
          <p style="margin:0;color:#7f1d1d">Urgency Score: <strong>{urgency}/10</strong></p>
        </div>
        <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
          <tr style="border-bottom:1px solid #e5e7eb">
            <td style="padding:10px;color:#6b7280;width:40%">Caller Number</td>
            <td style="padding:10px;font-weight:600">••••{str(number)[-4:]}</td>
          </tr>
          <tr style="border-bottom:1px solid #e5e7eb">
            <td style="padding:10px;color:#6b7280">Category</td>
            <td style="padding:10px;font-weight:600">{category}</td>
          </tr>
          <tr>
            <td style="padding:10px;color:#6b7280">AI Summary</td>
            <td style="padding:10px">{summary}</td>
          </tr>
        </table>
        {'<a href="' + fir_url + '" style="display:inline-block;background:#DC2626;color:white;padding:12px 24px;border-radius:6px;text-decoration:none;margin-right:12px">📄 View FIR Report</a>' if fir_url else ''}
        {'<a href="' + verify_url + '" style="display:inline-block;background:#4F46E5;color:white;padding:12px 24px;border-radius:6px;text-decoration:none">🔗 Verify on Blockchain</a>' if verify_url else ''}
        <p style="margin-top:24px;color:#9ca3af;font-size:12px">
          This alert was generated by Zentra AI Call Screener.
          Your privacy is protected — caller number is masked.
        </p>
      </div>
    </div>
    """

    text = f"""
    Zentra Scam Alert
    -----------------
    Category: {category}
    Urgency: {urgency}/10
    Summary: {summary}
    FIR Report: {fir_url}
    Blockchain Verify: {verify_url}
    """

    return await send_email(
        to=to,
        subject=f'🚨 Zentra Alert: {category} call detected',
        body_html=html,
        body_text=text,
    )