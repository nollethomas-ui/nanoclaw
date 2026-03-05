#!/bin/bash
# =============================================================================
# NanoClaw Health Check (run via cron every 5 minutes)
# Checks: process alive, memory usage, Docker healthy
# Restarts NanoClaw if unhealthy
#
# Install: sudo crontab -e
#   */5 * * * * /opt/nanoclaw/health-check.sh >> /var/log/nanoclaw-health.log 2>&1
# =============================================================================

set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
MAX_MEMORY_PCT=90

# Check if NanoClaw service is running
if ! systemctl is-active --quiet nanoclaw; then
  echo "[$TIMESTAMP] ALERT: NanoClaw not running. Restarting..."
  systemctl restart nanoclaw
  exit 1
fi

# Check memory usage
MEMORY_PCT=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
if [ "$MEMORY_PCT" -gt "$MAX_MEMORY_PCT" ]; then
  echo "[$TIMESTAMP] WARN: Memory at ${MEMORY_PCT}%. Restarting NanoClaw..."
  # Kill stale Docker containers first
  docker container prune -f 2>/dev/null || true
  systemctl restart nanoclaw
  exit 1
fi

# Check Docker daemon
if ! docker info &>/dev/null; then
  echo "[$TIMESTAMP] ALERT: Docker daemon not responding. Restarting Docker..."
  systemctl restart docker
  sleep 5
  systemctl restart nanoclaw
  exit 1
fi

# All healthy (silent in normal operation)
