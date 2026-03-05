#!/bin/bash
# Install health-check cron for NanoClaw
set -euo pipefail

echo "=== Installing NanoClaw Health-Check Cron ==="

# Create log file with correct permissions
sudo touch /var/log/nanoclaw-health.log
sudo chown nanoclaw:nanoclaw /var/log/nanoclaw-health.log
echo "Log file created."

# Install cron job (root crontab — health-check needs sudo for systemctl restart)
CRON_LINE='*/5 * * * * /opt/nanoclaw/health-check.sh >> /var/log/nanoclaw-health.log 2>&1'
echo "$CRON_LINE" | sudo crontab -
echo "Cron installed."

# Add logrotate config to prevent log bloat
sudo tee /etc/logrotate.d/nanoclaw-health > /dev/null << 'LOGROTATE'
/var/log/nanoclaw-health.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 644 nanoclaw nanoclaw
}
LOGROTATE
echo "Logrotate configured."

# Verify
echo ""
echo "=== Verification ==="
echo "Crontab:"
sudo crontab -l
echo ""
echo "Log file:"
ls -la /var/log/nanoclaw-health.log
echo ""
echo "Logrotate:"
cat /etc/logrotate.d/nanoclaw-health
echo ""

# Run health-check once to test
echo "=== Test Run ==="
sudo bash /opt/nanoclaw/health-check.sh && echo "Health check: OK" || echo "Health check: ISSUE"

echo ""
echo "=== Done ==="
