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
  # Pushed in rather than trusted to the mount — see the note further down.
  docker cp "$CADDYFILE" "$CONTAINER:/etc/caddy/Caddyfile" >/dev/null
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

# ---- /admin: the app authenticates it -------------------------------------
#
# The back office asks for a phone number and a password (migration 019,
# src/routes/staffLogin.ts) and hands out a session cookie. That is the
# boundary now, so the edge password this block used to carry has been
# removed: it was there only because the app trusted an x-staff-role header
# anyone could send, and it no longer does.
#
# What stays at the edge is a per-IP limit on the login itself. The app counts
# failures per phone number; this counts them per source, so one host cannot
# walk the eleven-digit phone space by trying each number once.
#
# Set ADMIN_CLOSED=1 to 404 the whole thing instead — the fast way to shut the
# back office if a session ever has to be assumed stolen.
if [ "${ADMIN_CLOSED:-0}" = "1" ]; then
  ADMIN_BLOCK="    # Closed by hand: ADMIN_CLOSED=1 when this was written.
    handle /admin* {
        respond \"Not found\" 404
    }"
  echo "==> /admin stays closed (ADMIN_CLOSED=1)"
else
  ADMIN_BLOCK="    handle /admin/login {
        rate_limit {
            zone admin_login {
                key    {remote_host}
                events 12
                window 5m
            }
        }
        reverse_proxy ${BACKEND}
    }

    handle /admin* {
        reverse_proxy ${BACKEND}
    }"
  echo "==> /admin is served by the app's own sign-in (phone + password)"
fi

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

    # ---- Fail closed --------------------------------------------------------
    #
    # Only the public surface is proxied; everything else 404s. This is an
    # allow-list on purpose, because the deny-list version was wrong: it closed
    # /admin* and left the whole app API open, and
    #
    #     curl -H 'x-user-id: <any id>' https://ana-bala.kz/children
    #
    # answered 200 with that family's children. Both authUser and authAdmin are
    # header stubs until REAL_AUTH=1 and a Firebase service account are wired
    # (docs/DEPLOY.md §5), so every user-data route is forgeable by anyone who
    # can reach it. Nothing leaked — the database has no families in it yet —
    # but the door was open on the public internet.
    #
    # An allow-list also cannot rot the same way: a new route is closed by
    # default rather than exposed by default.
    #
    # To open the app API, set REAL_AUTH=1 with a service account, confirm the
    # boot guard is satisfied, and add the paths here — not before.

    # The back-office. Must come BEFORE the allow-list: Caddy takes the first
    # matching handle, and /admin is deliberately not in @public.
$ADMIN_BLOCK

    # /robots.txt and /sitemap.xml are served by the backend per request, so
    # they have to be listed here too — the allow-list 404s anything it does
    # not name, which is how they came to be missing on a site whose whole job
    # is to be found.
    # /api-docs is a static documentation page — no data, no database, and the
    # "try it" console only sends a key the reader supplies themselves. It was
    # 404ing because it is not under any of the prefixes above, which made the
    # product look broken to anyone who followed the link. Documentation for an
    # API nobody can open yet is still documentation.
    @public path / /robots.txt /sitemap.xml /landing/* /shop /shop/* /health /ready /api-docs
    handle @public {
        reverse_proxy $BACKEND
    }

    handle {
        respond "Not found" 404
    }

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

# The container is supposed to see this file through a bind mount, and for a
# while it did. Then a script replaced the file with mv, which makes a NEW
# inode — and a bind-mounted *file* follows the inode, not the path. From then
# on the container kept serving the old contents while every edit landed on a
# file nothing was reading, and `caddy reload` cheerfully re-loaded the stale
# config and reported success. Two deploys were verified against a config that
# was never applied.
#
# So the file is pushed in explicitly and the push is checked. This is correct
# whether the mount is intact or not.
HOST_SUM="$(sha256sum "$CADDYFILE" | cut -d' ' -f1)"

docker cp "$CADDYFILE" "$CONTAINER:/etc/caddy/Caddyfile.candidate" >/dev/null
if ! docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile.candidate >/dev/null 2>&1; then
  echo "!! Does not validate — restoring the backup, nothing was applied"
  docker exec "$CONTAINER" caddy validate --config /etc/caddy/Caddyfile.candidate 2>&1 | tail -5
  cp -a "$BACKUP" "$CADDYFILE"
  exit 1
fi
echo "==> Config validates"

docker cp "$CADDYFILE" "$CONTAINER:/etc/caddy/Caddyfile" >/dev/null
IN_SUM="$(docker exec "$CONTAINER" sha256sum /etc/caddy/Caddyfile | cut -d' ' -f1)"
if [ "$HOST_SUM" != "$IN_SUM" ]; then
  echo "!! The container is not reading the file we wrote — refusing to claim a deploy"
  echo "   host:      $HOST_SUM"
  echo "   container: $IN_SUM"
  cp -a "$BACKUP" "$CADDYFILE"
  exit 1
fi
echo "==> The container has exactly this file"
reload

echo
echo "==> Verify"
sleep 3
printf '    landing  : '; curl -sS https://ana-bala.kz/ | grep -o '<title>[^<]*</title>' | head -1
printf '    assets   : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' "https://ana-bala.kz/landing/wire.js"
printf '    lead API : HTTP '; curl -s -o /dev/null -w '%{http_code}\n' -X POST https://ana-bala.kz/shop/leads \
  -H 'content-type: application/json' -d '{"customerName":"","phone":""}'   # expect 400 = reached the app
# The back office: the page is public, its data is not, and the browser
# password dialog must be gone — a WWW-Authenticate here means the edge is
# still asking for a password the app now asks for itself.
# The panel IS /admin. Both forms serve it; the old /admin/ui redirects there.
printf '    /admin   : HTTP '; curl -s -o /dev/null -w '%{http_code}' https://ana-bala.kz/admin
printf ' , /admin/ HTTP '; curl -s -o /dev/null -w '%{http_code}' https://ana-bala.kz/admin/
printf ' , /admin/ui HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/ui  # 200,200,302
printf '    admin API: HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/stats   # expect 401
printf '    basic srv: '; curl -sI https://ana-bala.kz/admin/ui | grep -qi '^www-authenticate' \
  && echo 'STILL PROMPTING — the edge password did not go away' || echo 'gone (the app signs staff in)'
# Both forms of the retired storefront URL land on the landing. The one with
# the trailing slash is what a browser leaves on a bookmark, and it 404'd.
printf '    /shop    : HTTP '; curl -s -o /dev/null -w '%{http_code}' https://ana-bala.kz/shop
printf ' , /shop/ HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/shop/   # both 302
# The one that regressed once: a forged user header must NOT reach the backend.
printf '    forged id: HTTP '; curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'x-user-id: 11111111-1111-1111-1111-111111111111' https://ana-bala.kz/children   # expect 404, never 200
echo
echo "Roll back with: bash /opt/umay/deploy/landing-takeover.sh --revert"
