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

# Pre-install MCP server packages globally to avoid npx download timeouts
# on resource-constrained instances (e2-micro). These are loaded via npx -y
# in index.ts but npx will use the global install instead of downloading.
RUN npm install -g \
    @gongrzhe/server-gmail-autoauth-mcp \
    roam-research-mcp \
    @hoffination/mcp-todoist \
    @modelcontextprotocol/server-gdrive \
    @cocal/google-calendar-mcp

WORKDIR /app
COPY agent-runner/package*.json ./
RUN npm install
COPY agent-runner/ ./
RUN npm run build

# Workspace directories
RUN mkdir -p /workspace/group /workspace/global /workspace/extra \
    /workspace/ipc/messages /workspace/ipc/tasks /workspace/ipc/input

# Create entrypoint script inline (same as upstream, no external file needed)
# Secrets are passed via stdin JSON — temp file is deleted immediately after Node reads it
RUN printf '#!/bin/bash\nset -e\ncd /app && npx tsc --outDir /tmp/dist 2>&1 >&2\nln -s /app/node_modules /tmp/dist/node_modules\nchmod -R a-w /tmp/dist\ncat > /tmp/input.json\nnode /tmp/dist/index.js < /tmp/input.json\n' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

# Set ownership to node user (non-root) for writable directories
RUN chown -R node:node /workspace && chmod 777 /home/node

USER node
WORKDIR /workspace/group
ENTRYPOINT ["/app/entrypoint.sh"]
