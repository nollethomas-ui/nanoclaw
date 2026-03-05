#!/bin/bash
# =============================================================================
# Setup Roam Research integration for NanoClaw
# Run on the VM: sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-roam.sh <ROAM_API_TOKEN> <GRAPH_NAME>
# =============================================================================
set -euo pipefail

PROJECT_ID="nanoclaw-tnoll"
SERVICE_ACCOUNT="nanoclaw-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com"
NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
ENV_FILE="${NANOCLAW_DIR}/.env"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Roam Research Setup ===${NC}"

# Step 1: Get API token
if [ $# -ge 1 ]; then
    ROAM_TOKEN="$1"
else
    echo -e "${YELLOW}Enter your Roam Research API Token (read+edit):${NC}"
    read -r ROAM_TOKEN
fi

if [ -z "$ROAM_TOKEN" ]; then
    echo -e "${RED}Error: Roam API Token cannot be empty${NC}"
    exit 1
fi

# Step 2: Get Graph Name
if [ $# -ge 2 ]; then
    GRAPH_NAME="$2"
else
    echo -e "${YELLOW}Enter your Roam Graph Name:${NC}"
    read -r GRAPH_NAME
fi

if [ -z "$GRAPH_NAME" ]; then
    echo -e "${RED}Error: Graph name cannot be empty${NC}"
    exit 1
fi

echo -e "\n${GREEN}[1/5] Creating ROAM_API_TOKEN secret...${NC}"
if gcloud secrets describe "ROAM_API_TOKEN" --project="$PROJECT_ID" &>/dev/null; then
    echo "Secret already exists, adding new version..."
    echo -n "$ROAM_TOKEN" | gcloud secrets versions add "ROAM_API_TOKEN" --data-file=- --project="$PROJECT_ID"
else
    echo -n "$ROAM_TOKEN" | gcloud secrets create "ROAM_API_TOKEN" --data-file=- --project="$PROJECT_ID"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[2/5] Creating ROAM_GRAPH_NAME secret...${NC}"
if gcloud secrets describe "ROAM_GRAPH_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "Secret already exists, adding new version..."
    echo -n "$GRAPH_NAME" | gcloud secrets versions add "ROAM_GRAPH_NAME" --data-file=- --project="$PROJECT_ID"
else
    echo -n "$GRAPH_NAME" | gcloud secrets create "ROAM_GRAPH_NAME" --data-file=- --project="$PROJECT_ID"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[3/5] Granting Secret Manager access...${NC}"
for SECRET in "ROAM_API_TOKEN" "ROAM_GRAPH_NAME"; do
    gcloud secrets add-iam-policy-binding "$SECRET" \
        --member="serviceAccount:${SERVICE_ACCOUNT}" \
        --role="roles/secretmanager.secretAccessor" \
        --project="$PROJECT_ID" 2>/dev/null || true
done
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[4/5] Adding Roam config to .env...${NC}"
# ROAM_API_TOKEN
if grep -q "^ROAM_API_TOKEN=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^ROAM_API_TOKEN=.*|ROAM_API_TOKEN=${ROAM_TOKEN}|" "$ENV_FILE"
    echo "Updated existing ROAM_API_TOKEN in .env"
else
    echo "" >> "$ENV_FILE"
    echo "# Roam Research (MCP)" >> "$ENV_FILE"
    echo "ROAM_API_TOKEN=${ROAM_TOKEN}" >> "$ENV_FILE"
fi

# ROAM_GRAPH_NAME
if grep -q "^ROAM_GRAPH_NAME=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^ROAM_GRAPH_NAME=.*|ROAM_GRAPH_NAME=${GRAPH_NAME}|" "$ENV_FILE"
    echo "Updated existing ROAM_GRAPH_NAME in .env"
else
    echo "ROAM_GRAPH_NAME=${GRAPH_NAME}" >> "$ENV_FILE"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[5/5] Updating systemd service + restarting NanoClaw...${NC}"
sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
sudo systemctl daemon-reload
sudo systemctl restart nanoclaw
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}=== Roam Research Setup complete! ===${NC}"
echo -e "Graph: ${YELLOW}${GRAPH_NAME}${NC}"
echo -e "Roam MCP server will start automatically when the agent container launches."
echo -e "Test by sending a WhatsApp message like: ${YELLOW}\"Such in Roam nach Einträgen mit Tag #erfasst\"${NC}"
echo -e "\nCheck logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"
