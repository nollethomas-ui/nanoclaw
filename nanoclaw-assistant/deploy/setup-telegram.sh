#!/bin/bash
# =============================================================================
# Setup Telegram Bot integration for NanoClaw
# Run on the VM: sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-telegram.sh <BOT_TOKEN>
# =============================================================================
set -euo pipefail

PROJECT_ID="nanoclaw-tnoll"
SECRET_NAME="TELEGRAM_BOT_TOKEN"
SERVICE_ACCOUNT="nanoclaw-vm-sa@${PROJECT_ID}.iam.gserviceaccount.com"
NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
ENV_FILE="${NANOCLAW_DIR}/.env"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Telegram Bot Setup ===${NC}"
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Telegram Bot erstellen (falls noch nicht gemacht): ║${NC}"
echo -e "${CYAN}║                                                      ║${NC}"
echo -e "${CYAN}║  1. Öffne Telegram und suche @BotFather              ║${NC}"
echo -e "${CYAN}║  2. Sende: /newbot                                   ║${NC}"
echo -e "${CYAN}║  3. Wähle einen Namen (z.B. 'Nano Assistant')        ║${NC}"
echo -e "${CYAN}║  4. Wähle einen Username (z.B. 'nano_tnoll_bot')     ║${NC}"
echo -e "${CYAN}║  5. BotFather gibt dir den Token (Format:            ║${NC}"
echo -e "${CYAN}║     123456789:ABCdefGHIjklMNOpqrsTUVwxyz)            ║${NC}"
echo -e "${CYAN}║                                                      ║${NC}"
echo -e "${CYAN}║  Optional — Bot-Einstellungen via BotFather:         ║${NC}"
echo -e "${CYAN}║  /setdescription — Beschreibung setzen               ║${NC}"
echo -e "${CYAN}║  /setuserpic — Profilbild setzen                     ║${NC}"
echo -e "${CYAN}║  /setcommands — Slash-Commands definieren            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Get bot token
if [ $# -ge 1 ]; then
    TOKEN="$1"
else
    echo -e "${YELLOW}Enter your Telegram Bot Token:${NC}"
    read -r TOKEN
fi

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Bot token cannot be empty${NC}"
    exit 1
fi

# Validate token format (roughly: digits:alphanumeric)
if ! echo "$TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]+$'; then
    echo -e "${RED}Warning: Token format looks unusual. Expected: 123456789:ABCdef...${NC}"
    echo -e "${YELLOW}Continue anyway? [y/N]${NC}"
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        exit 1
    fi
fi

echo -e "\n${GREEN}[1/4] Creating Secret Manager secret...${NC}"
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "Secret already exists, adding new version..."
    echo -n "$TOKEN" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
else
    echo -n "$TOKEN" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT_ID"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[2/4] Granting Secret Manager access...${NC}"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID" 2>/dev/null || true
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[3/4] Adding TELEGRAM_BOT_TOKEN to .env...${NC}"
if grep -q "^TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${TOKEN}|" "$ENV_FILE"
    echo "Updated existing TELEGRAM_BOT_TOKEN in .env"
else
    echo "" >> "$ENV_FILE"
    echo "# Telegram Bot" >> "$ENV_FILE"
    echo "TELEGRAM_BOT_TOKEN=${TOKEN}" >> "$ENV_FILE"
fi
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}[4/4] Updating systemd service + restarting NanoClaw...${NC}"
sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
sudo systemctl daemon-reload
sudo systemctl restart nanoclaw
echo -e "${GREEN}Done.${NC}"

echo -e "\n${GREEN}=== Telegram Bot Setup complete! ===${NC}"
echo -e ""
echo -e "${CYAN}Nächste Schritte:${NC}"
echo -e "  1. Öffne Telegram und sende eine Nachricht an deinen Bot"
echo -e "  2. NanoClaw registriert den Chat automatisch (via /add-telegram Skill)"
echo -e "  3. Falls der Bot nicht antwortet, registriere den Chat manuell:"
echo -e "     ${YELLOW}Sende via WhatsApp: \"Registriere meinen Telegram-Chat\"${NC}"
echo -e ""
echo -e "Check logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"
