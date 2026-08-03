#!/usr/bin/env bash
# =============================================================================
# Point ana-bala.kz's root at the Ana-Bala landing page.
#
# This is the ONE step that edits something already serving traffic — the Aiti.kz
# CRM's Caddyfile — so it is deliberately small, idempotent, and backed up before
# it writes. Read deploy/landing-route.md for what changes hands and why.
#
# The landing takes exactly `/`, `/landing/*` and `/shop/*`. Every path the CRM
# actually uses (/api/v1, /api/wa, /rest, /auth/v1, /storage, /assets, and its
# SPA fallback) is left alone.
#
#   bash /opt/umay/deploy/landing-route-apply.sh          # apply
#   bash /opt/umay/deploy/landing-route-apply.sh --revert # undo (newest backup)
# =============================================================================
set -euo pipefail

CADDYFILE="${CADDYFILE:-/opt/aiti/app/docker/Caddyfile}"
CONTAINER="${CONTAINER:-aiti_caddy}"
MARKER='umay-backend:8080'

reload() {
  # `caddy reload` swaps config without dropping connections. If the new config
  # does not parse, Caddy keeps the old one and exits non-zero — so a bad edit
  # cannot take the CRM down.
  docker exec "$CONTAINER" caddy reload --config /etc/caddy/Caddyfile 2>&1 | tail -3
}

if [ "${1:-}" = "--revert" ]; then
  latest="$(ls -1t "$CADDYFILE".bak.before-umay-landing-* 2>/dev/null | head -1 || true)"
  [ -n "$latest" ] || { echo "no backup found"; exit 1; }
  echo "==> Restoring $latest"
  cp -a "$latest" "$CADDYFILE"
  reload
  echo "==> Reverted. The CRM owns / again."
  exit 0
fi

[ -f "$CADDYFILE" ] || { echo "$CADDYFILE not found"; exit 1; }

if grep -q "$MARKER" "$CADDYFILE"; then
  echo "==> Route already present — nothing to do."
  reload
  exit 0
fi

BACKUP="$CADDYFILE.bak.before-umay-landing-$(date +%F-%H%M%S)"
cp -a "$CADDYFILE" "$BACKUP"
echo "==> Backed up to $BACKUP"

# Insert immediately before the SPA catch-all. Caddy matches `handle` blocks in
# source order, so anything placed after the catch-all would never be reached.
# The catch-all is identified by its `root * /app/dist` line; the `handle {` that
# opens it is the line before.
awk '
  /root \* \/app\/dist/ && !done {
    # prev holds the "handle {" line that opens the catch-all.
    print "    # ---- Ana-Bala landing page (umay-backend) -------------------------"
    print "    # Added by deploy/landing-route-apply.sh. MUST stay above the SPA"
    print "    # catch-all below: Caddy takes the first matching handle."
    print "    handle / {"
    print "        reverse_proxy umay-backend:8080"
    print "    }"
    print "    handle /landing/* {"
    print "        reverse_proxy umay-backend:8080"
    print "    }"
    print "    handle /shop/* {"
    print "        reverse_proxy umay-backend:8080"
    print "    }"
    print ""
    done = 1
  }
  NR > 1 { print prev }
  { prev = $0 }
  END { print prev }
' "$CADDYFILE" > "$CADDYFILE.new"

grep -q "$MARKER" "$CADDYFILE.new" || { echo "insertion failed — leaving the original alone"; rm -f "$CADDYFILE.new"; exit 1; }
mv "$CADDYFILE.new" "$CADDYFILE"
echo "==> Wrote the new route"

# Validate BEFORE reloading, so a syntax error never reaches the running proxy.
if ! docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
  echo "!! Config does not validate — restoring the backup"
  cp -a "$BACKUP" "$CADDYFILE"
  docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || true
  exit 1
fi
echo "==> Config validates"
reload

echo
echo "==> Verify"
sleep 2
printf '    landing  : '; curl -sS https://ana-bala.kz/ | grep -o '<title>[^<]*</title>' | head -1
printf '    CRM login: HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/login
printf '    CRM api  : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/api/v1/health
echo
echo "Roll back with: bash /opt/umay/deploy/landing-route-apply.sh --revert"
