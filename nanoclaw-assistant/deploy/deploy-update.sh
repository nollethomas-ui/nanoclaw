#!/bin/bash
# =============================================================================
# Deploy latest changes to NanoClaw VM
# Run on the VM: sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/deploy-update.sh
# =============================================================================
set -euo pipefail

NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Update Deployment ===${NC}"
echo -e "Date: $(date)"
echo ""

# Step 1: Stop service
echo -e "${YELLOW}[1/6] Stopping NanoClaw...${NC}"
systemctl stop nanoclaw || true
sleep 2
echo -e "${GREEN}Stopped.${NC}"

# Step 2: Git pull
echo -e "\n${YELLOW}[2/6] Pulling latest changes...${NC}"
cd "$NANOCLAW_DIR"
sudo -u nanoclaw git fetch origin
sudo -u nanoclaw git pull origin voice-support
echo -e "${GREEN}Git pull complete.${NC}"
git log --oneline -5

# Step 3: npm install (in case dependencies changed)
echo -e "\n${YELLOW}[3/6] Installing dependencies...${NC}"
sudo -u nanoclaw npm install --no-audit --no-fund 2>&1 | tail -3
echo -e "${GREEN}Dependencies installed.${NC}"

# Step 4: TypeScript build
echo -e "\n${YELLOW}[4/6] Building TypeScript...${NC}"
echo -e "  (This may take 30-40 min on e2-micro with swap)"
sudo -u nanoclaw NODE_OPTIONS='--max-old-space-size=1536' npx tsc --skipLibCheck
echo -e "${GREEN}Build complete.${NC}"

# Step 5: Ensure credential directories exist
echo -e "\n${YELLOW}[5/6] Ensuring credential directories...${NC}"
mkdir -p /home/nanoclaw/.gmail-mcp /home/nanoclaw/.gsheets-mcp
chown nanoclaw:nanoclaw /home/nanoclaw/.gmail-mcp /home/nanoclaw/.gsheets-mcp
echo -e "${GREEN}Done.${NC}"

# Step 6: Update systemd + restart
echo -e "\n${YELLOW}[6/6] Updating systemd service + restarting...${NC}"
cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
chmod +x "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/fetch-secrets.sh"
systemctl daemon-reload
systemctl start nanoclaw
sleep 3

# Verify
STATUS=$(systemctl is-active nanoclaw)
if [ "$STATUS" = "active" ]; then
    echo -e "${GREEN}NanoClaw is running!${NC}"
else
    echo -e "${RED}NanoClaw failed to start. Check: journalctl -u nanoclaw -n 30${NC}"
    exit 1
fi

echo -e "\n${GREEN}=== Deployment complete! ===${NC}"
echo -e "New features:"
echo -e "  - ElevenLabs TTS dual-provider (set TTS_PROVIDER=elevenlabs in .env)"
echo -e "  - Smart Voice Response (<voice> tags for short TTS + full text)"
echo -e "  - Roam Research MCP (setup-roam.sh)"
echo -e "  - Telegram Bot channel (setup-telegram.sh)"
echo -e "  - Gmail MCP (setup-gmail.sh)"
echo -e "  - Google Sheets MCP (setup-gsheets.sh)"
echo -e "  - External fetch-secrets.sh (snap gcloud compatible, required/optional secrets)"
echo -e ""
echo -e "Activate integrations:"
echo -e "  ${YELLOW}sudo bash .../deploy/setup-todoist.sh <TOKEN>${NC}"
echo -e "  ${YELLOW}sudo bash .../deploy/setup-roam.sh <TOKEN> <GRAPH>${NC}"
echo -e "  ${YELLOW}sudo bash .../deploy/setup-telegram.sh <BOT_TOKEN>${NC}"
echo -e "  ${YELLOW}sudo bash .../deploy/setup-gmail.sh${NC}  (shows OAuth instructions)"
echo -e "  ${YELLOW}sudo bash .../deploy/setup-gsheets.sh${NC}  (shows OAuth instructions)"
echo -e ""
echo -e "Logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"
