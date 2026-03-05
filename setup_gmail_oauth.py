#!/usr/bin/env python3
"""
Generate Gmail OAuth token for NanoClaw Gmail channel + MCP server.
Saves to ~/.gmail-mcp/credentials.json

Scopes: gmail.modify (read+modify) + gmail.send
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
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/gmail.send',
]

CRED_DIR = os.path.expanduser('~/.gmail-mcp')
KEYS_PATH = os.path.join(CRED_DIR, 'gcp-oauth.keys.json')
TOKEN_PATH = os.path.join(CRED_DIR, 'credentials.json')

def main():
    os.makedirs(CRED_DIR, exist_ok=True)

    if not os.path.exists(KEYS_PATH):
        print(f"ERROR: OAuth app credentials not found at {KEYS_PATH}")
        print("Copy from newsletter-agent/config/credentials.json")
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
    print(f"  scp {TOKEN_PATH} nanoclaw-vm:~/.gmail-mcp/credentials.json")
    print(f"  scp {KEYS_PATH} nanoclaw-vm:~/.gmail-mcp/gcp-oauth.keys.json")

if __name__ == '__main__':
    main()
