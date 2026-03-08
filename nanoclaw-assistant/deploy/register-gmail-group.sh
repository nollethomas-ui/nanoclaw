#!/bin/bash
# Register the Gmail Agent WhatsApp group in NanoClaw's SQLite database.
#
# Usage:
#   sudo bash register-gmail-group.sh <GROUP_JID>
#
# How to get the GROUP_JID:
#   1. Create a WhatsApp group "Gmail Agent" on your phone (just you + Nano)
#   2. Send any message in the group
#   3. Check logs: sudo journalctl -u nanoclaw -f | grep "gmail"
#   4. The JID looks like: 120363336345536173@g.us
#
# This script must be run on the NanoClaw VM as root.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <GROUP_JID>"
  echo ""
  echo "Example: $0 120363336345536173@g.us"
  echo ""
  echo "Get the JID by sending a message in the Gmail Agent WhatsApp group"
  echo "and checking: sudo journalctl -u nanoclaw --since '5 min ago' | grep -i gmail"
  exit 1
fi

GROUP_JID="$1"
NANOCLAW_DIR="/opt/nanoclaw/nanoclaw"
DB_PATH="$NANOCLAW_DIR/store/messages.db"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: Database not found at $DB_PATH"
  exit 1
fi

echo "Registering Gmail Agent group..."
echo "  JID: $GROUP_JID"
echo "  Folder: gmail-agent"
echo "  Trigger: @Gmail"

# Use Node.js with better-sqlite3 (sqlite3 CLI not installed on VM)
cd "$NANOCLAW_DIR"
sudo -u nanoclaw node -e "
  const Database = require('better-sqlite3');
  const db = new Database('$DB_PATH');

  db.prepare(\`
    INSERT OR REPLACE INTO registered_groups
    (jid, name, folder, trigger_pattern, added_at, container_config, requires_trigger)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  \`).run(
    '$GROUP_JID',
    'Gmail Agent',
    'gmail-agent',
    '@Gmail',
    new Date().toISOString(),
    null,
    0
  );

  // Verify
  const row = db.prepare('SELECT * FROM registered_groups WHERE folder = ?').get('gmail-agent');
  console.log('Registered:', JSON.stringify(row, null, 2));

  db.close();
"

# Ensure group directory exists with correct permissions
GROUP_DIR="$NANOCLAW_DIR/groups/gmail-agent"
if [ ! -d "$GROUP_DIR" ]; then
  mkdir -p "$GROUP_DIR"
  chown -R nanoclaw:nanoclaw "$GROUP_DIR"
fi

# Copy .env and CLAUDE.md if they exist in the git repo but not in the runtime groups dir
REPO_GROUP_DIR="$NANOCLAW_DIR/groups/gmail-agent"
if [ -f "$REPO_GROUP_DIR/.env" ] && [ -f "$REPO_GROUP_DIR/CLAUDE.md" ]; then
  echo "Group config files already in place."
else
  echo "WARNING: groups/gmail-agent/.env and CLAUDE.md should exist after git pull."
  echo "If missing, create them manually:"
  echo "  echo 'AGENT_ROLE=gmail' > $GROUP_DIR/.env"
fi

echo ""
echo "Done! Now restart the service:"
echo "  sudo systemctl restart nanoclaw"
echo ""
echo "Then test by sending a message in the Gmail Agent WhatsApp group."
