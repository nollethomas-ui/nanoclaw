#!/bin/bash
# =============================================================================
# Refresh OAuth tokens for Gmail (and optionally Calendar) before service start.
#
# Called by systemd ExecStartPre AFTER fetch-secrets.sh.
# Checks if OAuth credentials.json exists and tries to refresh the token
# using Python's google-auth library. This prevents expired tokens from
# causing MCP server failures inside the Docker container.
#
# Prerequisites:
#   pip3 install google-auth google-auth-oauthlib (on VM as root)
# =============================================================================
set -e

GMAIL_DIR="/home/nanoclaw/.gmail-mcp"
GCALENDAR_DIR="/home/nanoclaw/.gcalendar-mcp"

refresh_token() {
    local dir="$1"
    local name="$2"
    local token_file="$dir/credentials.json"
    local keys_file="$dir/gcp-oauth.keys.json"

    if [ ! -f "$token_file" ]; then
        echo "SKIP: $name — no credentials.json found at $token_file"
        return 0
    fi

    if [ ! -f "$keys_file" ]; then
        echo "SKIP: $name — no OAuth keys file found at $keys_file"
        return 0
    fi

    echo "Checking $name token..."

    # Use Python to check and refresh the token
    python3 -c "
import json, sys
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request

token_path = '$token_file'
keys_path = '$keys_file'

try:
    creds = Credentials.from_authorized_user_file(token_path)
except Exception as e:
    print(f'ERROR: Cannot load $name token: {e}', file=sys.stderr)
    sys.exit(0)  # Non-fatal — MCP may handle it

if creds.valid:
    print(f'OK: $name token is valid (expires: {creds.expiry})')
    sys.exit(0)

if not creds.expired:
    print(f'OK: $name token not yet expired')
    sys.exit(0)

if not creds.refresh_token:
    print(f'WARN: $name token expired but no refresh_token — needs manual re-auth', file=sys.stderr)
    sys.exit(0)

try:
    print(f'Refreshing $name token...')
    creds.refresh(Request())
    # Write refreshed token back
    with open(token_path, 'w') as f:
        f.write(creds.to_json())
    print(f'OK: $name token refreshed (new expiry: {creds.expiry})')
except Exception as e:
    print(f'WARN: $name token refresh failed: {e}', file=sys.stderr)
    # Non-fatal — let the service start, MCP may retry
" 2>&1 || true

    # Ensure nanoclaw user can read the file
    chown nanoclaw:nanoclaw "$token_file" 2>/dev/null || true
}

echo "=== OAuth Token Refresh ==="
refresh_token "$GMAIL_DIR" "Gmail"
refresh_token "$GCALENDAR_DIR" "Calendar"
echo "=== Done ==="
