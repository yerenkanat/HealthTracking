#!/usr/bin/env bash
# =============================================================================
# Install the nightly backup as a systemd timer.
#
# A timer rather than cron: it survives a reboot mid-window (Persistent=true
# runs a missed job on the next boot), the last run and its output are visible
# in `systemctl status`, and a failure is a unit in a failed state rather than
# a mail nobody reads.
#
#   bash /opt/umay/deploy/backup-install.sh
#   systemctl list-timers umay-backup    # when it next runs
#   journalctl -u umay-backup -n 40      # what the last run did
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/umay}"
DEST="${DEST:-/var/backups/umay}"

mkdir -p "$DEST"
chmod 700 "$DEST"   # dumps contain everything; do not leave them world-readable

cat > /etc/systemd/system/umay-backup.service <<EOF
[Unit]
Description=Umay database backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
# --verify restores each night's dump into a scratch database and compares row
# counts. It costs seconds at this size, and an unverified backup is a guess.
ExecStart=/usr/bin/env bash $APP_DIR/deploy/backup.sh --verify
EOF

cat > /etc/systemd/system/umay-backup.timer <<'EOF'
[Unit]
Description=Nightly Umay database backup

[Timer]
OnCalendar=*-*-* 03:20:00
# Runs on the next boot if the machine was off at 03:20.
Persistent=true
# Spread the load a little; nothing here is time-critical to the minute.
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now umay-backup.timer

echo "==> Installed"
systemctl list-timers umay-backup.timer --no-pager | head -3

cat <<'DONE'

==> Offsite is NOT set up, and this is the half that matters
    Everything above is on the same disk as the database, so one dead host
    loses both. Add ONE of these to umay-backup.service as a second ExecStart:

      # to another machine you control
      ExecStart=/usr/bin/rsync -az --delete /var/backups/umay/ user@host:/backups/umay/

      # to S3-compatible object storage (install rclone, configure a remote)
      ExecStart=/usr/bin/rclone sync /var/backups/umay remote:umay-backups

    Then `systemctl daemon-reload`. Whichever you pick, restore from it once
    before believing it.
DONE
