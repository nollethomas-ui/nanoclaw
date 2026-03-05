#!/bin/bash
# =============================================================================
# Setup Google Sheets MCP integration for NanoClaw
# Run on the VM: sudo bash /opt/nanoclaw/nanoclaw/nanoclaw-assistant/deploy/setup-gsheets.sh [--install-from-tmp]
#
# Google Sheets uses OAuth (browser-based), not a simple API token.
# Workflow:
#   1. Run setup_gsheets_oauth.py LOCALLY (opens browser)
#   2. SCP credentials to VM: /tmp/gsheets-credentials.json + /tmp/gsheets-oauth-keys.json
#   3. Run this script with --install-from-tmp on the VM
# =============================================================================
set -euo pipefail

NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
GSHEETS_DIR="/home/nanoclaw/.gsheets-mcp"

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== NanoClaw Google Sheets MCP Setup ===${NC}"

if [ "${1:-}" = "--install-from-tmp" ]; then
    # =========================================================================
    # Mode: Install from /tmp (after SCP upload)
    # =========================================================================
    echo -e "\n${GREEN}Installing Google Sheets credentials from /tmp...${NC}"

    CRED_FILE="/tmp/gsheets-credentials.json"
    KEYS_FILE="/tmp/gsheets-oauth-keys.json"

    if [ ! -f "$CRED_FILE" ]; then
        echo -e "${RED}Error: $CRED_FILE not found.${NC}"
        echo -e "Upload first: gcloud compute scp ~/.gsheets-mcp/credentials.json nanoclaw-vm:/tmp/gsheets-credentials.json"
        exit 1
    fi

    if [ ! -f "$KEYS_FILE" ]; then
        echo -e "${RED}Error: $KEYS_FILE not found.${NC}"
        echo -e "Upload first: gcloud compute scp ~/.gsheets-mcp/gcp-oauth.keys.json nanoclaw-vm:/tmp/gsheets-oauth-keys.json"
        exit 1
    fi

    echo -e "\n${GREEN}[1/4] Creating Google Sheets credential directory...${NC}"
    mkdir -p "$GSHEETS_DIR"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[2/4] Moving credentials...${NC}"
    cp "$CRED_FILE" "${GSHEETS_DIR}/credentials.json"
    cp "$KEYS_FILE" "${GSHEETS_DIR}/gcp-oauth.keys.json"
    rm -f "$CRED_FILE" "$KEYS_FILE"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[3/4] Setting permissions...${NC}"
    chown -R nanoclaw:nanoclaw "$GSHEETS_DIR"
    chmod 700 "$GSHEETS_DIR"
    chmod 600 "${GSHEETS_DIR}/credentials.json"
    chmod 600 "${GSHEETS_DIR}/gcp-oauth.keys.json"
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}[4/4] Updating systemd service + restarting NanoClaw...${NC}"
    sudo cp "${NANOCLAW_DIR}/nanoclaw-assistant/deploy/nanoclaw.service" /etc/systemd/system/nanoclaw.service
    sudo systemctl daemon-reload
    sudo systemctl restart nanoclaw
    echo -e "${GREEN}Done.${NC}"

    echo -e "\n${GREEN}=== Google Sheets Setup complete! ===${NC}"
    echo -e "Credentials installed at: ${YELLOW}${GSHEETS_DIR}/${NC}"
    echo -e "Test by sending a WhatsApp message like: ${YELLOW}\"Lies die erste Zeile aus Sheet <ID>\"${NC}"
    echo -e "\nCheck logs: ${YELLOW}sudo journalctl -u nanoclaw -f${NC}"

else
    # =========================================================================
    # Mode: Show instructions for local OAuth flow
    # =========================================================================
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Google Sheets verwendet OAuth — der Token muss LOKAL       ║${NC}"
    echo -e "${CYAN}║  erstellt werden (Browser-Flow), dann auf die VM kopiert.   ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 1: Lokal auf deinem PC                             ║${NC}"
    echo -e "${CYAN}║  ─────────────────────────────────────                       ║${NC}"
    echo -e "${CYAN}║  mkdir ~/.gsheets-mcp                                        ║${NC}"
    echo -e "${CYAN}║  cp newsletter-agent/config/credentials.json \\               ║${NC}"
    echo -e "${CYAN}║     ~/.gsheets-mcp/gcp-oauth.keys.json                       ║${NC}"
    echo -e "${CYAN}║  cd nanoclaw-fork                                            ║${NC}"
    echo -e "${CYAN}║  python setup_gsheets_oauth.py                               ║${NC}"
    echo -e "${CYAN}║  (Browser öffnet sich → Google-Konto autorisieren)           ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 2: Dateien auf VM kopieren                          ║${NC}"
    echo -e "${CYAN}║  ──────────────────────────────────                          ║${NC}"
    echo -e "${CYAN}║  gcloud compute scp ~/.gsheets-mcp/credentials.json \\        ║${NC}"
    echo -e "${CYAN}║    nanoclaw-vm:/tmp/gsheets-credentials.json \\               ║${NC}"
    echo -e "${CYAN}║    --zone=us-central1-a --project=nanoclaw-tnoll             ║${NC}"
    echo -e "${CYAN}║  gcloud compute scp ~/.gsheets-mcp/gcp-oauth.keys.json \\    ║${NC}"
    echo -e "${CYAN}║    nanoclaw-vm:/tmp/gsheets-oauth-keys.json \\                ║${NC}"
    echo -e "${CYAN}║    --zone=us-central1-a --project=nanoclaw-tnoll             ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  Schritt 3: Auf der VM installieren                          ║${NC}"
    echo -e "${CYAN}║  ──────────────────────────────────                          ║${NC}"
    echo -e "${CYAN}║  sudo bash .../setup-gsheets.sh --install-from-tmp           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
fi
