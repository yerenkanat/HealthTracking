#!/usr/bin/env bash
# =============================================================================
# Open the back-office at https://ana-bala.kz/admin behind an edge password.
#
# WHY THIS IS THE WHOLE BOUNDARY
#
# The admin page carries the staff header stub in its own source: `x-staff-id`
# and `x-staff-role` are trusted outright, and authPosture() hardcodes
# adminStub = true because no verifier exists. So whoever gets past this
# password has full read/write over every family's data. It is not defence in
# depth; it is the only door.
#
# That is still strictly better than the alternative, which was /admin being
# 404 and the leads the landing collects being unreadable by anybody.
#
# Replace it with a real staff verifier when there is one (docs/DEPLOY.md §5,
# docs/SECURITY_FOLLOWUP.md §2), and move it to admin.ana-bala.kz once that DNS
# record exists — the path form is here because the record does not.
#
#   bash /opt/umay/deploy/admin-access.sh            # create/rotate the password
#   bash /opt/umay/deploy/admin-access.sh --close    # take it away again
# =============================================================================
set -euo pipefail

CONTAINER="${CONTAINER:-aiti_caddy}"
HASH_FILE="${HASH_FILE:-/etc/umay/admin-basicauth}"
CRED_FILE="${CRED_FILE:-/etc/umay/admin-credentials}"
APP_DIR="${APP_DIR:-/opt/umay}"

if [ "${1:-}" = "--close" ]; then
  rm -f "$HASH_FILE" "$CRED_FILE"
  echo "==> Credential removed; re-applying the config"
  bash "$APP_DIR/deploy/landing-takeover.sh"
  exit 0
fi

mkdir -p "$(dirname "$HASH_FILE")"

# Generated HERE, on the box. The root password for this machine has been pasted
# into a chat twice; this one is written to a 0600 file and printed nowhere, so
# there is no transcript of it anywhere to leak.
PASSWORD="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 22)"
HASH="$(docker exec "$CONTAINER" caddy hash-password --plaintext "$PASSWORD")"

printf '%s' "$HASH" > "$HASH_FILE"
chmod 600 "$HASH_FILE"

cat > "$CRED_FILE" <<EOF
# Ana-Bala back-office — https://ana-bala.kz/admin/ui
# Created $(date -u +%Y-%m-%dT%H:%M:%SZ) by deploy/admin-access.sh
#
# This password is the ONLY thing between the internet and every family's data,
# because the app behind it still trusts the x-staff-role header. Treat it as
# you would the root password: share it over something that is not a chat log,
# and rotate it by re-running admin-access.sh.
username: admin
password: $PASSWORD
EOF
chmod 600 "$CRED_FILE"

echo "==> Credential written to $CRED_FILE (0600)"
echo "==> Applying the Caddy config"
bash "$APP_DIR/deploy/landing-takeover.sh" >/dev/null

echo
echo "==> Verify"
sleep 2
printf '    without a password : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/ui
printf '    with it            : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' -u "admin:$PASSWORD" https://ana-bala.kz/admin/ui
printf '    leads endpoint     : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' -u "admin:$PASSWORD" \
  -H 'x-staff-id: s1' -H 'x-staff-role: admin' https://ana-bala.kz/admin/shop/leads
printf '    landing unaffected : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/

cat <<DONE

==> Read the password with:
      ssh root@<host> 'cat $CRED_FILE'

    It is deliberately not printed here, so it does not end up in a terminal
    scrollback or a chat transcript.
DONE
