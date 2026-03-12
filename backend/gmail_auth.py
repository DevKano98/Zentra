"""
Run this script once on your PC to generate the Gmail OAuth token.
    cd D:\MyProjects\ZentraDialer\backend
    python gmail_auth.py
"""
from google_auth_oauthlib.flow import InstalledAppFlow
import pickle
import os

SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
]

print('Starting Gmail OAuth flow...')
print('A browser window will open — log in and click Allow')

flow = InstalledAppFlow.from_client_secrets_file('gmail_credentials.json', SCOPES)
creds = flow.run_local_server(port=0)

os.makedirs('gmail_tokens', exist_ok=True)
with open('gmail_tokens/token.pickle', 'wb') as f:
    pickle.dump(creds, f)

print('Done! Token saved to gmail_tokens/token.pickle')
print('Now run: python generate_gmail_token_env.py')