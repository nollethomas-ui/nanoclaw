# NanoClaw Agent Container — Lightweight (no Chromium)
# Saves ~400-500MB RAM — critical for e2-micro (1GB)

FROM node:22-slim

# System dependencies WITHOUT Chromium
RUN apt-get update && apt-get install -y \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install claude-code globally (skip agent-browser)
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app
COPY agent-runner/package*.json ./
RUN npm install
COPY agent-runner/ ./
RUN npm run build

# Workspace directories
RUN mkdir -p /workspace/group /workspace/global /workspace/extra \
    /workspace/ipc/messages /workspace/ipc/tasks /workspace/ipc/input

# Copy entrypoint
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

USER node
WORKDIR /workspace/group
ENTRYPOINT ["/app/entrypoint.sh"]
