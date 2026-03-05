#!/bin/bash
# =============================================================================
# Apply all NanoClaw patches to the fork
# Usage: ./apply-patches.sh /path/to/nanoclaw-fork
# =============================================================================

set -euo pipefail

NANOCLAW_DIR="${1:?Usage: ./apply-patches.sh /path/to/nanoclaw-fork}"
PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$NANOCLAW_DIR/package.json" ]; then
  echo "ERROR: $NANOCLAW_DIR does not look like a NanoClaw directory"
  exit 1
fi

echo "=== Applying NanoClaw Voice Patches ==="
echo "Target: $NANOCLAW_DIR"
echo ""

# Patch 1: Replace transcription.ts with Groq version
echo "[1/6] Replacing src/transcription.ts (Groq Whisper)..."
cp "$PATCHES_DIR/01-transcription-groq.ts" "$NANOCLAW_DIR/src/transcription.ts"
echo "  ✓ src/transcription.ts replaced"

# Patch 3: Add voice-response.ts (TTS)
echo "[2/6] Adding src/voice-response.ts (Google TTS)..."
cp "$PATCHES_DIR/03-voice-response.ts" "$NANOCLAW_DIR/src/voice-response.ts"
echo "  ✓ src/voice-response.ts added"

# Patch 6: Add dependencies
echo "[3/6] Installing additional dependencies..."
cd "$NANOCLAW_DIR"
npm install groq-sdk @google-cloud/text-to-speech
echo "  ✓ groq-sdk + @google-cloud/text-to-speech installed"

# Patches 2 + 5: Manual patches (WhatsApp handler + Router)
echo ""
echo "[4/6] MANUAL: Apply whatsapp voice handler changes"
echo "  See: $PATCHES_DIR/02-whatsapp-voice-handler.patch"
echo "  Edit: $NANOCLAW_DIR/src/channels/whatsapp.ts"
echo ""
echo "[5/6] MANUAL: Apply router voice routing changes"
echo "  See: $PATCHES_DIR/05-router-voice-routing.patch"
echo "  Edit: $NANOCLAW_DIR/src/index.ts"
echo ""

# Patch 4: Dockerfile (replace)
echo "[6/6] Updating container/Dockerfile (no Chromium)..."
cat > "$NANOCLAW_DIR/container/Dockerfile" << 'DOCKERFILE'
FROM node:22-slim

RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app
COPY agent-runner/package*.json ./
RUN npm install
COPY agent-runner/ ./
RUN npm run build

RUN mkdir -p /workspace/group /workspace/global /workspace/extra \
    /workspace/ipc/messages /workspace/ipc/tasks /workspace/ipc/input

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

USER node
WORKDIR /workspace/group
ENTRYPOINT ["/app/entrypoint.sh"]
DOCKERFILE
echo "  ✓ Dockerfile replaced (no Chromium, ~400MB smaller)"

echo ""
echo "=== Auto-patches applied ==="
echo ""
echo "Remaining manual steps:"
echo "  1. Edit src/channels/whatsapp.ts (see patch 02)"
echo "  2. Edit src/index.ts (see patch 05)"
echo "  3. Add sendAudio to Channel interface in src/types.ts (see patch 02)"
echo "  4. Run: npm run build"
echo "  5. Rebuild Docker image: cd container && ./build.sh"
