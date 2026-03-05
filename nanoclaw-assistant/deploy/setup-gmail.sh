#!/bin/bash
# =============================================================================
# Setup Gmail MCP integration for NanoClaw
# Run on the VM: sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-gmail.sh [--install-from-tmp]
#
# Gmail uses OAuth (browser-based), not a simple API token.
# Workflow:
#   1. Run setup_gmail_oauth.py LOCALLY (opens browser)
#   2. SCP credentials to VM: /tmp/gmail-credentials.json + /tmp/gmail-oauth-keys.json
#   3. Run this script with --install-from-tmp on the VM
# =============================================================================
set -euo pipefail

NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
GMAIL_DIR="/home/nanoclaw/.gmail-mcp"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Gmail MCP Setup ===${NC}"

if [ "${1:-}" = "--install-from-tmp" ]; then
    # =========================================================================
    # Mode: Install from /tmp (after SCP upload)
    # =========================================================================
    echo -e "\n${GREEN}Installing Gmail credentials from /tmp...${NC}"

    CRED_FILE="/tmp/gmail-credentials.json"
    KEYS_FILE="/tmp/gmail-oauth-keys.json"

    if [ ! -f "$CRED_FILE" ]; then
        echo -e "${RED}Error: $CRED_FILE not found.${NC}"
        echo -e "Upload first: gcloud compute scp ~/.gmail-mcp/credentials.json nanoclaw-vm:/tmp/gmail-credentials.json"
        exit 1
    fi

    if [ ! -f "$KEYS_FILE" ]; then
        echo -e "${RED}Error: $KEYS_FILE not found.${NC}"
        echo -e "Upload first: gcloud compute scp ~/.gmail-mcp/gcp-oauth.keys.json nanoclaw-vm:/tmp/gmail-oauth-keys.json"
        exit 1
    fi

    echo -e "\n${GREEN}[1/4] Creating Gmail credential directory...${NC}"
    mkdir -p "$GMAIL_DIR"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[2/4] Moving credentials...${NC}"
    cp "$CRED_FILE" "${GMAIL_DIR}/credentials.json"
    cp "$KEYS_FILE" "${GMAIL_DIR}/gcp-oauth.keys.json"
    rm -f "$CRED_FILE" "$KEYS_FILE"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[3/4] Setting permissions...${NC}"
    chown -R nanoclaw:nanoclaw "$GMAIL_DIR"
    chmod 700 "$GMAIL_DIR"
    chmod 600 "${GMAIL_DIR}/credentials.json"
    chmod 600 "${GMAIL_DIR}/gcp-oauth.keys.json"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[4/4] Updating systemd service + restarting NanoClaw...${NC}"
    sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
    sudo systemctl daemon-reload
    sudo systemctl restart nanoclaw
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}=== Gmail Setup complete! ===${NC}"
    echo -e "Credentials installed at: ${YELLOW}${GMAIL_DIR}/${NC}"
    echo -e "Test by sending a WhatsApp message like: ${YELLOW}\"Zeig mir meine letzten 3 E-Mails\"${NC}"
    echo -e "\nCheck logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"

else
    # =========================================================================
    # Mode: Show instructions for local OAuth flow
    # =========================================================================
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Gmail verwendet OAuth — der Token muss LOKAL erstellt      ║${NC}"
    echo -e "${CYAN}║  werden (Browser-Flow), dann auf die VM kopiert.            ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 1: Lokal auf deinem PC                             ║${NC}"
    echo -e "${CYAN}║  ─────────────────────────────────────                       ║${NC}"
    echo -e "${CYAN}║  mkdir ~/.gmail-mcp                                          ║${NC}"
    echo -e "${CYAN}║  cp newsletter-agent/config/credentials.json \\               ║${NC}"
    echo -e "${CYAN}║     ~/.gmail-mcp/gcp-oauth.keys.json                         ║${NC}"
    echo -e "${CYAN}║  cd nanoclaw-fork                                            ║${NC}"
    echo -e "${CYAN}║  python setup_gmail_oauth.py                                 ║${NC}"
    echo -e "${CYAN}║  (Browser öffnet sich → Google-Konto autorisieren)           ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 2: Dateien auf VM kopieren                          ║${NC}"
    echo -e "${CYAN}║  ──────────────────────────────────                          ║${NC}"
    echo -e "${CYAN}║  gcloud compute scp ~/.gmail-mcp/credentials.json \\          ║${NC}"
    echo -e "${CYAN}║    nanoclaw-vm:/tmp/gmail-credentials.json \\                 ║${NC}"
    echo -e "${CYAN}║    --zone=us-central1-a --project=nanoclaw-tnoll             ║${NC}"
    echo -e "${CYAN}║  gcloud compute scp ~/.gmail-mcp/gcp-oauth.keys.json \\      ║${NC}"
    echo -e "${CYAN}║    nanoclaw-vm:/tmp/gmail-oauth-keys.json \\                  ║${NC}"
    echo -e "${CYAN}║    --zone=us-central1-a --project=nanoclaw-tnoll             ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 3: Auf der VM installieren                          ║${NC}"
    echo -e "${CYAN}║  ──────────────────────────────────                          ║${NC}"
    echo -e "${CYAN}║  sudo bash .../setup-gmail.sh --install-from-tmp             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
fi
