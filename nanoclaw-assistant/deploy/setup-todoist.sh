#!/bin/bash
# =============================================================================
# Setup Todoist integration for NanoClaw
# Run on the VM: bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-todoist.sh
# =============================================================================
set -euo pipefail

PROJECT_ID="nanoclaw-tnoll"
SECRET_NAME="TODOIST_API_TOKEN"
SERVICE_ACCOUNT="nanoclaw-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com"
NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
ENV_FILE="${NANOCLAW_DIR}/.env"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Todoist Setup ===${NC}"

# Step 1: Check if token is provided as argument or prompt
if [ $# -ge 1 ]; then
    TOKEN="$1"
else
    echo -e "${YELLOW}Enter your Todoist API Token:${NC}"
    read -r TOKEN
fi

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Token cannot be empty${NC}"
    exit 1
fi

echo -e "\n${GREEN}[1/4] Creating Secret Manager secret...${NC}"
# Create secret if it doesn't exist
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "Secret already exists, adding new version..."
    echo -n "$TOKEN" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
else
    echo -n "$TOKEN" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[2/4] Granting Secret Manager access to service account...${NC}"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID" 2>/dev/null || true
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[3/4] Adding TODOIST_API_TOKEN to .env...${NC}"
if grep -q "TODOIST_API_TOKEN" "$ENV_FILE" 2>/dev/null; then
    # Update existing line
    sed -i "s|^TODOIST_API_TOKEN=.*|TODOIST_API_TOKEN=${TOKEN}|" "$ENV_FILE"
    echo "Updated existing TODOIST_API_TOKEN in .env"
else
    # Append
    echo "" >> "$ENV_FILE"
    echo "# Todoist Task Management" >> "$ENV_FILE"
    echo "TODOIST_API_TOKEN=${TOKEN}" >> "$ENV_FILE"
    echo "Added TODOIST_API_TOKEN to .env"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[4/4] Updating systemd service + restarting NanoClaw...${NC}"
# Copy updated service file
sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
sudo systemctl daemon-reload
sudo systemctl restart nanoclaw
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}=== Setup complete! ===${NC}"
echo -e "Todoist MCP server will start automatically when the agent container launches."
echo -e "Test by sending a WhatsApp message like: ${YELLOW}\"Was steht auf meiner Todoist-Liste?\"${NC}"
echo -e "\nCheck logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"
