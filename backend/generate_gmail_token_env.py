"""
generate_gmail_token_env.py

Run this ONCE on your local PC to convert your gmail pickle token
into a base64 string you can paste into Render as an env var.

Usage:
    cd backend
    python generate_gmail_token_env.py

Then copy the output and add it to Render as:
    GMAIL_TOKEN_JSON = <paste output here>
"""

import base64
import os
from pathlib import Path

# Find the token file — check common locations
possible_paths = [
    Path('gmail_tokens'),
    Path('app/services/gmail_tokens'),
    Path('../gmail_tokens'),
]

token_file = None
for folder in possible_paths:
    if folder.exists():
        pickles = list(folder.glob('*.pickle'))
        if pickles:
            token_file = pickles[0]
            break

if not token_file:
    print('ERROR: No .pickle file found in gmail_tokens/ folder')
    print('Make sure you have run the Gmail OAuth flow at least once locally')
    exit(1)

print(f'Found token file: {token_file}')

with open(token_file, 'rb') as f:
    pickle_bytes = f.read()

b64 = base64.b64encode(pickle_bytes).decode()

print('\n' + '='*60)
print('Copy this value into Render environment variables')
print('Variable name: GMAIL_TOKEN_JSON')
print('='*60)
print(b64)
print('='*60)
print(f'\nToken size: {len(b64)} characters')
print('Done!')