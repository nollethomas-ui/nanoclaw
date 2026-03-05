#!/usr/bin/env python3
"""
Generate Google Sheets/Drive OAuth token for NanoClaw Google Sheets MCP server.
Saves to ~/.gsheets-mcp/credentials.json

Scopes: drive.readonly (read spreadsheets + export docs)
"""
import json
import os
import sys

try:
    from google.auth.transport.requests import Request
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.oauth2.credentials import Credentials
except ImportError:
    print("Install dependencies: pip install google-auth-oauthlib google-auth-httplib2")
    sys.exit(1)

SCOPES = [
    'https://www.googleapis.com/auth/drive.readonly',
]

CRED_DIR = os.path.expanduser('~/.gsheets-mcp')
KEYS_PATH = os.path.join(CRED_DIR, 'gcp-oauth.keys.json')
TOKEN_PATH = os.path.join(CRED_DIR, 'credentials.json')

def main():
    os.makedirs(CRED_DIR, exist_ok=True)

    if not os.path.exists(KEYS_PATH):
        print(f"ERROR: OAuth app credentials not found at {KEYS_PATH}")
        print("Copy from newsletter-agent/config/credentials.json:")
        print(f"  cp newsletter-agent/config/credentials.json {KEYS_PATH}")
        sys.exit(1)

    creds = None
    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            print("Refreshing expired token...")
            creds.refresh(Request())
        else:
            print(f"Starting OAuth flow for scopes: {SCOPES}")
            print("A browser window will open for authentication.")
            flow = InstalledAppFlow.from_client_secrets_file(KEYS_PATH, SCOPES)
            creds = flow.run_local_server(port=0)

        with open(TOKEN_PATH, 'w') as f:
            f.write(creds.to_json())
        print(f"Token saved to {TOKEN_PATH}")
    else:
        print(f"Token already valid at {TOKEN_PATH}")

    print("\nNext steps:")
    print(f"  1. Upload to VM:")
    print(f"     gcloud compute scp {TOKEN_PATH} nanoclaw-vm:/tmp/gsheets-credentials.json --zone=us-central1-a --project=nanoclaw-tnoll")
    print(f"     gcloud compute scp {KEYS_PATH} nanoclaw-vm:/tmp/gsheets-oauth-keys.json --zone=us-central1-a --project=nanoclaw-tnoll")
    print(f"  2. On VM:")
    print(f"     sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-gsheets.sh --install-from-tmp")

if __name__ == '__main__':
    main()
