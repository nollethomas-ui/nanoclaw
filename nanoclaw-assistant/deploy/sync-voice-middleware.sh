#!/bin/bash
# =============================================================================
# Sync voice-middleware to GCP VM
# Usage: ./sync-voice-middleware.sh [PROJECT_ID] [ZONE]
# =============================================================================

set -euo pipefail

PROJECT_ID="${1:-nanoclaw-assistant}"
ZONE="${2:-us-central1-a}"
VM_NAME="nanoclaw-vm"
REMOTE_DIR="/opt/nanoclaw/voice-middleware"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOICE_DIR="$SCRIPT_DIR/../voice-middleware"

echo "=== Syncing voice-middleware to $VM_NAME ==="

# Build locally first
echo "[1/3] Building voice-middleware..."
cd "$VOICE_DIR"
npm run build

# Sync to VM
echo "[2/3] Uploading to VM..."
gcloud compute scp --recurse \
  "$VOICE_DIR/dist" "$VOICE_DIR/package.json" "$VOICE_DIR/package-lock.json" \
  "nanoclaw@$VM_NAME:$REMOTE_DIR/" \
  --zone="$ZONE" --project="$PROJECT_ID"

# Install & restart on VM
echo "[3/3] Installing on VM and restarting NanoClaw..."
gcloud compute ssh "nanoclaw@$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" -- \
  "cd $REMOTE_DIR && npm install --production && sudo systemctl restart nanoclaw"

echo "=== Sync complete. Checking status... ==="
gcloud compute ssh "nanoclaw@$VM_NAME" --zone="$ZONE" --project="$PROJECT_ID" -- \
  "sudo systemctl status nanoclaw --no-pager -l"
