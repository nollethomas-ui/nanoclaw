#!/bin/bash
# =============================================================================
# NanoClaw VM Setup Script
# Target: GCP e2-micro (us-central1, Free Tier), Ubuntu 24.04 LTS
# Usage: Run as root on a fresh VM
# =============================================================================

set -euo pipefail

echo "=== NanoClaw VM Setup ==="

# --- System updates ---
echo "[1/9] Updating system packages..."
apt-get update && apt-get upgrade -y

# --- Install Docker ---
echo "[2/9] Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$SUDO_USER" || true
  systemctl enable docker
  systemctl start docker
  echo "Docker installed. User added to docker group."
else
  echo "Docker already installed."
fi

# --- Install Node.js 22 ---
echo "[3/9] Installing Node.js 22..."
if ! command -v node &> /dev/null || [[ $(node -v | cut -d. -f1 | tr -d v) -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
  echo "Node.js $(node -v) installed."
else
  echo "Node.js $(node -v) already installed."
fi

# --- Install ffmpeg ---
echo "[4/9] Installing ffmpeg..."
apt-get install -y ffmpeg
echo "ffmpeg $(ffmpeg -version 2>&1 | head -1) installed."

# --- Install git ---
echo "[5/9] Installing git..."
apt-get install -y git

# --- Configure swap (2GB) ---
echo "[6/9] Configuring 2GB swap..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  # Optimize swap for low-RAM system
  sysctl vm.swappiness=10
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  echo "2GB swap configured."
else
  echo "Swap already configured."
fi

# --- Create nanoclaw user & directory ---
echo "[7/9] Creating nanoclaw user and directories..."
if ! id nanoclaw &> /dev/null; then
  useradd -m -s /bin/bash nanoclaw
  usermod -aG docker nanoclaw
fi

NANOCLAW_DIR="/opt/nanoclaw"
mkdir -p "$NANOCLAW_DIR"
chown nanoclaw:nanoclaw "$NANOCLAW_DIR"

# --- Clone & setup NanoClaw ---
echo "[8/9] Cloning NanoClaw fork..."
if [ ! -d "$NANOCLAW_DIR/nanoclaw" ]; then
  sudo -u nanoclaw git clone https://github.com/nollethomas-ui/nanoclaw.git "$NANOCLAW_DIR/nanoclaw"
  cd "$NANOCLAW_DIR/nanoclaw"
  sudo -u nanoclaw git checkout voice-support || sudo -u nanoclaw git checkout -b voice-support
  sudo -u nanoclaw npm install
  sudo -u nanoclaw npm run build
  echo "NanoClaw cloned and built."
else
  echo "NanoClaw already cloned."
fi

# --- Setup voice-middleware ---
VOICE_DIR="$NANOCLAW_DIR/voice-middleware"
if [ ! -d "$VOICE_DIR" ]; then
  mkdir -p "$VOICE_DIR"
  # voice-middleware will be copied from the local project
  echo "Created voice-middleware directory at $VOICE_DIR"
  echo "Copy voice-middleware files and run: cd $VOICE_DIR && npm install && npm run build"
fi

# --- Secure file permissions ---
echo "[9/9] Setting secure permissions..."

# Session/auth directory: only nanoclaw user can access (K4: WhatsApp session keys are replay-able)
AUTH_DIR="$NANOCLAW_DIR/nanoclaw/store/auth"
mkdir -p "$AUTH_DIR"
chown -R nanoclaw:nanoclaw "$AUTH_DIR"
chmod 700 "$AUTH_DIR"

# .env file: only nanoclaw user can read
if [ -f "$NANOCLAW_DIR/nanoclaw/.env" ]; then
  chmod 600 "$NANOCLAW_DIR/nanoclaw/.env"
  chown nanoclaw:nanoclaw "$NANOCLAW_DIR/nanoclaw/.env"
fi

echo "Session and secret files secured."
echo ""
echo "SECURITY NOTE: WhatsApp session keys in store/auth/ are replay-able."
echo "Consider enabling disk encryption: https://cloud.google.com/compute/docs/disks/customer-supplied-encryption"

# --- Install systemd service ---
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Copy .env to $NANOCLAW_DIR/nanoclaw/.env"
echo "  2. Copy voice-middleware to $VOICE_DIR/"
echo "  3. Install systemd service: cp nanoclaw.service /etc/systemd/system/"
echo "  4. Enable service: systemctl daemon-reload && systemctl enable nanoclaw"
echo "  5. Start: systemctl start nanoclaw"
echo "  6. Connect WhatsApp: journalctl -u nanoclaw -f (scan QR code)"
echo ""
echo "Memory status:"
free -h
echo ""
echo "Disk status:"
df -h /
