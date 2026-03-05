#!/bin/bash
# =============================================================================
# Setup ElevenLabs TTS for NanoClaw
# Run on the VM: bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-elevenlabs.sh <API_KEY> <VOICE_ID>
# =============================================================================
set -euo pipefail

PROJECT_ID="nanoclaw-tnoll"
SECRET_NAME="ELEVENLABS_API_KEY"
SERVICE_ACCOUNT="nanoclaw-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com"
COMPUTE_SA="813344178199-compute@developer.gserviceaccount.com"
NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
ENV_FILE="${NANOCLAW_DIR}/.env"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw ElevenLabs TTS Setup ===${NC}"

# Step 1: Get API key
if [ $# -ge 1 ]; then
    API_KEY="$1"
else
    echo -e "${YELLOW}Enter your ElevenLabs API Key:${NC}"
    read -r API_KEY
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: API key cannot be empty${NC}"
    exit 1
fi

# Step 2: Get Voice ID
if [ $# -ge 2 ]; then
    VOICE_ID="$2"
else
    echo -e "${YELLOW}Enter ElevenLabs Voice ID (from https://elevenlabs.io/voice-library):${NC}"
    read -r VOICE_ID
fi

if [ -z "$VOICE_ID" ]; then
    echo -e "${RED}Error: Voice ID cannot be empty${NC}"
    exit 1
fi

echo -e "\n${GREEN}[1/4] Creating Secret Manager secret...${NC}"
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "Secret already exists, adding new version..."
    echo -n "$API_KEY" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
else
    echo -n "$API_KEY" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[2/4] Granting Secret Manager access to service accounts...${NC}"
for SA in "$SERVICE_ACCOUNT" "$COMPUTE_SA"; do
    gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
        --member="serviceAccount:${SA}" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID" 2>/dev/null || true
done
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[3/4] Updating .env with ElevenLabs config...${NC}"
# TTS_PROVIDER
if grep -q "^TTS_PROVIDER=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^TTS_PROVIDER=.*|TTS_PROVIDER=elevenlabs|" "$ENV_FILE"
else
    echo "" >> "$ENV_FILE"
    echo "# ElevenLabs TTS (female voice)" >> "$ENV_FILE"
    echo "TTS_PROVIDER=elevenlabs" >> "$ENV_FILE"
fi

# ELEVENLABS_API_KEY
if grep -q "^ELEVENLABS_API_KEY=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^ELEVENLABS_API_KEY=.*|ELEVENLABS_API_KEY=${API_KEY}|" "$ENV_FILE"
else
    echo "ELEVENLABS_API_KEY=${API_KEY}" >> "$ENV_FILE"
fi

# ELEVENLABS_VOICE_ID
if grep -q "^ELEVENLABS_VOICE_ID=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^ELEVENLABS_VOICE_ID=.*|ELEVENLABS_VOICE_ID=${VOICE_ID}|" "$ENV_FILE"
else
    echo "ELEVENLABS_VOICE_ID=${VOICE_ID}" >> "$ENV_FILE"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[4/4] Updating systemd service + restarting NanoClaw...${NC}"
sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
sudo systemctl daemon-reload
sudo systemctl restart nanoclaw
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}=== ElevenLabs Setup complete! ===${NC}"
echo -e "TTS provider switched to ElevenLabs with voice ID: ${YELLOW}${VOICE_ID}${NC}"
echo -e "Test by sending a voice message via WhatsApp."
echo -e "\nCheck logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"
