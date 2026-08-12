#!/usr/bin/env bash
# =============================================================================
# Ana-Bala — run this ONCE, and deploying stops needing a human.
#
# Why it exists: the assistant's shell has stdin on the null device, so it can
# never answer an SSH password prompt. Password auth works fine for a person and
# is a dead end for automation. Every deploy therefore needed the owner to open
# a terminal and type — which on 2026-08-12 cost two hours and had, by then,
# blocked their work for the better part of a week.
#
# One authenticated login is unavoidable: nothing can install a key on a box it
# cannot log into. This script makes that one login permanent.
#
# From the owner's machine, one line, one password prompt:
#
#   ssh root@188.137.231.252 "cd /opt/umay && git pull && bash deploy/enable-hands-free.sh \
#     'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICStpTnC2QlFg+nM86NXQda+2CqGbHHeKQqaMEwYoFf8 anabala-deploy'"
#
# Add --with-timer to ALSO deploy automatically whenever main moves. Off by
# default on purpose: work is pushed to main many times a day, and not every
# push is meant to reach customers. Without it, deploys stay a decision someone
# makes and the assistant carries out.
#
# Safe to re-run. It adds nothing twice.
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/umay}"
PUBKEY="${1:-}"
WITH_TIMER=0
for a in "$@"; do [ "$a" = "--with-timer" ] && WITH_TIMER=1; done
[ "$PUBKEY" = "--with-timer" ] && PUBKEY=""

if [ -z "$PUBKEY" ]; then
  echo "usage: bash deploy/enable-hands-free.sh 'ssh-ed25519 AAAA... comment' [--with-timer]"
  echo
  echo "The public key is the CONTENTS of ~/.ssh/anabala_deploy.pub on the machine"
  echo "that will deploy. Never pass the private half, and never a password."
  exit 2
fi

case "$PUBKEY" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *) ;;
  *) echo "!! that does not look like a public key: ${PUBKEY:0:40}..."; exit 2 ;;
esac
# A private key starts with this. Passing one here would be a serious mistake
# and is worth catching loudly rather than writing it into authorized_keys.
case "$PUBKEY" in *PRIVATE\ KEY*) echo "!! that is a PRIVATE key. Stop."; exit 2 ;; esac

echo "==> Installing the deploy key"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Matched on the key body only — the trailing comment differs between machines,
# so comparing whole lines would append a duplicate on every re-run.
BODY="$(printf '%s' "$PUBKEY" | awk '{print $2}')"
if grep -q -- "$BODY" /root/.ssh/authorized_keys; then
  echo "    already present — nothing to add"
else
  printf '%s\n' "$PUBKEY" >> /root/.ssh/authorized_keys
  echo "    added"
fi

# sshd silently ignores authorized_keys if anything in the path is group- or
# world-writable, which looks exactly like a rejected key and has cost people
# entire afternoons.
chown -R root:root /root/.ssh
echo "    permissions: $(stat -c '%a %U' /root/.ssh) /root/.ssh, $(stat -c '%a' /root/.ssh/authorized_keys) authorized_keys"

if ! grep -Eq '^\s*PubkeyAuthentication\s+no' /etc/ssh/sshd_config 2>/dev/null; then
  echo "    PubkeyAuthentication is not disabled — good"
else
  echo "!!  sshd_config has 'PubkeyAuthentication no'. The key will be ignored."
  echo "    Set it to yes and run: systemctl reload ssh"
fi

# ---- Optional: deploy on every push ------------------------------------------
if [ "$WITH_TIMER" = 1 ]; then
  echo
  echo "==> Installing the auto-deploy watcher"
  # Detects its scheduler rather than assuming one. This box was described in
  # notes as "Docker, not systemd" — true of the BACKEND, which is a container,
  # and no evidence either way about the host. Guessing is how the last set of
  # wrong instructions got written.
  cat > /usr/local/bin/umay-autodeploy <<'WATCHER'
#!/usr/bin/env bash
# Deploys when main moves. Does nothing at all when it has not.
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/umay}"
LOG=/var/log/umay-autodeploy.log
cd "$APP_DIR"
[ -f "$APP_DIR/.autodeploy-disabled" ] && exit 0
git fetch --quiet origin main
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse origin/main)"
[ "$LOCAL" = "$REMOTE" ] && exit 0
{
  echo "=== $(date -Is)  ${LOCAL:0:7} -> ${REMOTE:0:7}"
  bash "$APP_DIR/deploy/update.sh" 2>&1 || echo "!! update.sh exited $?"
} >> "$LOG" 2>&1
WATCHER
  chmod +x /usr/local/bin/umay-autodeploy

  if command -v systemctl >/dev/null 2>&1; then
    cat > /etc/systemd/system/umay-autodeploy.service <<'UNIT'
[Unit]
Description=Ana-Bala: deploy when main moves
After=docker.service
UNIT
    printf 'ExecStart=/usr/local/bin/umay-autodeploy\nType=oneshot\n' >> /etc/systemd/system/umay-autodeploy.service
    cat > /etc/systemd/system/umay-autodeploy.timer <<'UNIT'
[Unit]
Description=Ana-Bala: check for new commits every 2 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload
    systemctl enable --now umay-autodeploy.timer
    echo "    systemd timer installed: $(systemctl is-active umay-autodeploy.timer)"
  elif command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v umay-autodeploy; echo '*/2 * * * * /usr/local/bin/umay-autodeploy' ) | crontab -
    echo "    cron entry installed (every 2 minutes)"
  else
    echo "!!  neither systemctl nor crontab found — the watcher is installed at"
    echo "    /usr/local/bin/umay-autodeploy but nothing is calling it."
  fi
  echo "    log: /var/log/umay-autodeploy.log"
  echo "    to stop: touch $APP_DIR/.autodeploy-disabled"
fi

echo
echo "==> Done."
echo "    From now on, deploying is this, with no password and no prompt:"
echo
echo "      ssh root@188.137.231.252 'cd $APP_DIR && git pull && bash deploy/update.sh'"
echo
echo "    Verify it from the deploying machine with:  ssh -o BatchMode=yes root@188.137.231.252 true"
