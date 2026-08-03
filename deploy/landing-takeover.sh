#!/usr/bin/env bash
# =============================================================================
# Give ana-bala.kz to the Ana-Bala landing page, in full.
#
# Context (verified 2026-08-03, not assumed):
#   - This box (188.137.231.252) ran a TEST deployment of the Aiti.kz CRM, which
#     owned ana-bala.kz in its Caddyfile.
#   - The CRM's real production lives on a DIFFERENT server: aiti.kz resolves to
#     188.137.253.215. Nothing here affects it.
#   - The owner confirmed the instance on this box is disposable.
#
# So the whole hostname moves to umay-backend. This rewrites only the site block
# for ana-bala.kz; the `:8081` passthrough to the CRM's Supabase Kong is kept
# byte-for-byte, and no container, volume or database is touched. The CRM's
# containers keep running — stopping them is a separate, deliberate act.
#
#   bash /opt/umay/deploy/landing-takeover.sh            # apply
#   bash /opt/umay/deploy/landing-takeover.sh --revert   # newest backup back
# =============================================================================
set -euo pipefail

CADDYFILE="${CADDYFILE:-/opt/aiti/app/docker/Caddyfile}"
CONTAINER="${CONTAINER:-aiti_caddy}"
BACKEND="${BACKEND:-umay-backend:8080}"
MARKER='# ana-bala: landing'

reload() {
  # Swaps config without dropping connections; on a parse error Caddy keeps the
  # old config and exits non-zero, so a bad edit cannot take the site down.
  docker exec "$CONTAINER" caddy reload --config /etc/caddy/Caddyfile 2>&1 | tail -3
}

if [ "${1:-}" = "--revert" ]; then
  latest="$(ls -1t "$CADDYFILE".bak.before-umay-* 2>/dev/null | head -1 || true)"
  [ -n "$latest" ] || { echo "no backup found"; exit 1; }
  echo "==> Restoring $latest"
  cp -a "$latest" "$CADDYFILE"
  reload
  echo "==> Reverted."
  exit 0
fi

[ -f "$CADDYFILE" ] || { echo "$CADDYFILE not found"; exit 1; }
docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "$CONTAINER not running"; exit 1; }

BACKUP="$CADDYFILE.bak.before-umay-takeover-$(date +%F-%H%M%S)"
cp -a "$CADDYFILE" "$BACKUP"
echo "==> Backed up to $BACKUP"

# Preserve the CRM's Supabase passthrough exactly as found. It is published on
# 0.0.0.0:8081 and its data plane is unrelated to the landing.
KONG_BLOCK="$(awk '/^:8081 \{/,/^\}/' "$CADDYFILE")"
[ -n "$KONG_BLOCK" ] || KONG_BLOCK=$':8081 {\n    encode zstd gzip\n    reverse_proxy kong:8000\n}'

cat > "$CADDYFILE" <<EOF
$MARKER — written by deploy/landing-takeover.sh
#
# ana-bala.kz serves the Ana-Bala product: the landing page at /, the storefront
# under /shop, and the app API. The Aiti.kz CRM that used to answer here was a
# test deployment; its production is on another server (aiti.kz).
#
# The rate_limit directive comes from the custom Caddy image and must be ordered
# explicitly. Kept so the block below can use it.
{
    order rate_limit before reverse_proxy
}

ana-bala.kz, www.ana-bala.kz {
    encode zstd gzip

    # www → apex, so the landing has one canonical URL.
    @www host www.ana-bala.kz
    redir @www https://ana-bala.kz{uri} permanent

    # The staff back-office is NOT exposed. Its auth is still the x-staff-id /
    # x-staff-role header stub, so anyone who could reach /admin/ui would have
    # full admin over every family's data. This 404 is what makes running the
    # backend without NODE_ENV=production defensible. Remove it only once real
    # staff auth exists — see docs/DEPLOY.md §5 — and put it behind
    # admin.ana-bala.kz with basic_auth, as deploy/Caddyfile does.
    handle /admin* {
        respond "Not found" 404
    }

    # Everything else: the landing page, its assets, the storefront and the
    # JSON API the Flutter app talks to.
    reverse_proxy $BACKEND

    header {
        # Start HSTS at 0 and raise it only after HTTPS has been stable for a
        # week. A bad cert with a live max-age traps every visitor on a broken
        # site for the cached duration.
        Strict-Transport-Security "max-age=0"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}

# Kept verbatim from the previous config — the test CRM's Supabase edge.
$KONG_BLOCK
EOF

echo "==> Wrote the new config"
if ! docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
  echo "!! Does not validate — restoring the backup"
  docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile 2>&1 | tail -5
  cp -a "$BACKUP" "$CADDYFILE"
  exit 1
fi
echo "==> Config validates"
reload

echo
echo "==> Verify"
sleep 3
printf '    landing  : '; curl -sS https://ana-bala.kz/ | grep -o '<title>[^<]*</title>' | head -1
printf '    assets   : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' "https://ana-bala.kz/landing/wire.js"
printf '    lead API : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' -X POST https://ana-bala.kz/shop/leads \
  -H 'content-type: application/json' -d '{"customerName":"","phone":""}'   # expect 400 = reached the app
printf '    admin    : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/ui   # expect 404
echo
echo "Roll back with: bash /opt/umay/deploy/landing-takeover.sh --revert"
