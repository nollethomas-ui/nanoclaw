#!/bin/bash
# =============================================================================
# Fetch secrets from GCP Secret Manager at service start
# Called by systemd ExecStartPre with + prefix (runs as root)
# Writes /run/nanoclaw/secrets.env for the nanoclaw service
# =============================================================================
set -e

PROJECT="nanoclaw-tnoll"
ENV_FILE="/run/nanoclaw/secrets.env"

# Find gcloud binary (snap or standard install)
if [ -x /snap/bin/gcloud ]; then
    GCLOUD=/snap/bin/gcloud
elif [ -x /usr/bin/gcloud ]; then
    GCLOUD=/usr/bin/gcloud
elif [ -x /usr/local/bin/gcloud ]; then
    GCLOUD=/usr/local/bin/gcloud
else
    echo "ERROR: gcloud not found" >&2
    exit 1
fi

mkdir -p /run/nanoclaw

# Helper: fetch secret, return empty string on failure
fetch_secret() {
    local name="$1"
    $GCLOUD secrets versions access latest --secret="$name" --project="$PROJECT" 2>/dev/null | tr -d '\r\n' || echo ""
}

# Required secrets (fail if missing)
ANTHROPIC_KEY=$(fetch_secret "ANTHROPIC_API_KEY")
GROQ_KEY=$(fetch_secret "GROQ_API_KEY")

if [ -z "$ANTHROPIC_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY not found in Secret Manager" >&2
    exit 1
fi
if [ -z "$GROQ_KEY" ]; then
    echo "ERROR: GROQ_API_KEY not found in Secret Manager" >&2
    exit 1
fi

# Optional secrets (empty string if missing)
TODOIST_KEY=$(fetch_secret "TODOIST_API_TOKEN")
ELEVENLABS_KEY=$(fetch_secret "ELEVENLABS_API_KEY")
ROAM_TOKEN=$(fetch_secret "ROAM_API_TOKEN")
ROAM_GRAPH=$(fetch_secret "ROAM_GRAPH_NAME")
TELEGRAM_TOKEN=$(fetch_secret "TELEGRAM_BOT_TOKEN")

# Write secrets.env
cat > "$ENV_FILE" <<EOF
ANTHROPIC_API_KEY=${ANTHROPIC_KEY}
GROQ_API_KEY=${GROQ_KEY}
TODOIST_API_TOKEN=${TODOIST_KEY}
ELEVENLABS_API_KEY=${ELEVENLABS_KEY}
ROAM_API_TOKEN=${ROAM_TOKEN}
ROAM_GRAPH_NAME=${ROAM_GRAPH}
TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}
EOF

chmod 600 "$ENV_FILE"
chown nanoclaw:nanoclaw "$ENV_FILE"
