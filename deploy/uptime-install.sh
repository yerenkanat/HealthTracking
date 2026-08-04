#!/usr/bin/env bash
#
# Install the uptime check as a systemd timer (every 5 minutes).
#
# A timer rather than cron for the same reasons as the backup: the run is in the
# journal with its exit status, `systemctl status umay-uptime` answers "when did
# this last work", and a missed run while the box was off is not silently
# skipped forever.
#
set -euo pipefail

REPO="${REPO:-/opt/umay}"
INTERVAL="${INTERVAL:-5min}"

[ -f "$REPO/deploy/uptime-check.sh" ] || { echo "run this from the deployed repo"; exit 1; }
chmod +x "$REPO/deploy/uptime-check.sh"

cat > /etc/systemd/system/umay-uptime.service <<EOF
[Unit]
Description=Ana-Bala uptime check
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/env bash $REPO/deploy/uptime-check.sh
# The check alerting is not a reason to mark the unit failed forever; the timer
# will run it again. The non-zero exit is what makes the journal readable.
SuccessExitStatus=0 1
EOF

cat > /etc/systemd/system/umay-uptime.timer <<EOF
[Unit]
Description=Run the Ana-Bala uptime check every $INTERVAL

[Timer]
OnBootSec=2min
OnUnitActiveSec=$INTERVAL
# Spread across the minute so the check does not land on the same instant as
# every other timer on the box.
RandomizedDelaySec=20
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now umay-uptime.timer

echo "==> Installed. First run:"
systemctl start umay-uptime.service || true
journalctl -u umay-uptime.service -n 12 --no-pager
echo
systemctl list-timers umay-uptime.timer --no-pager | head -3
echo
echo "Alerts go to the Telegram chat configured in the admin panel."
echo "Until a bot token is set there, failures are recorded in the journal only."
