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
  # cat, not cp -a: rewriting the file keeps its inode, and the container's
  # bind mount follows the inode. Replacing it would detach the mount and the
  # revert would look applied while changing nothing — see the note further down.
  cat "$latest" > "$CADDYFILE"
  reload
  echo "==> Reverted."
  exit 0
fi

[ -f "$CADDYFILE" ] || { echo "$CADDYFILE not found"; exit 1; }
docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "$CONTAINER not running"; exit 1; }

BACKUP="$CADDYFILE.bak.before-umay-takeover-$(date +%F-%H%M%S)"
cp -a "$CADDYFILE" "$BACKUP"
echo "==> Backed up to $BACKUP"

# ---- The retired CRM's Supabase passthrough --------------------------------
#
# `:8081 → kong:8000`, left from the Aiti.kz test deployment this box used to
# host. Its production moved to aiti.kz long ago.
#
# It was preserved verbatim AND recreated when absent, so deleting it by hand
# came back on the next run of this script. Meanwhile `kong` is not among the
# running containers — so the block holds port 8081 open on 0.0.0.0 and answers
# every request to it with a proxy error, which is worse than not listening.
#
# Now emitted only when the container it points at actually EXISTS. That is the
# honest test: not a flag somebody has to remember, and not an assumption.
# KEEP_CRM_EDGE=1 forces it back for the case where kong is expected to return.
#
# The heading travels inside the variable so dropping the block leaves no
# orphaned comment describing a section that is not there.
KONG_BLOCK=""
if [ "${KEEP_CRM_EDGE:-0}" = "1" ] || docker ps --format '{{.Names}}' | grep -qx kong; then
  FOUND="$(awk '/^:8081 \{/,/^\}/' "$CADDYFILE")"
  [ -n "$FOUND" ] || FOUND=$':8081 {\n    encode zstd gzip\n    reverse_proxy kong:8000\n}'
  KONG_BLOCK="# Kept from the previous config: the test CRM's Supabase edge."$'\n'"$FOUND"
  echo "==> Keeping the :8081 CRM edge (kong is running, or KEEP_CRM_EDGE=1)"
else
  echo "==> Dropping the :8081 CRM edge — no kong container, so it proxied to nothing"
fi

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
    # answered 200 with that family's children, because the dev shortcuts were
    # live. They are off now — gated on the presence of a database rather than
    # on Firebase, which this deployment does not use — so the same request
    # returns 401 and the app API below is open, defended by the app itself.
    #
    # An allow-list still cannot rot the same way: a new route is closed by
    # default rather than exposed by default. Anything not named here 404s.

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
    # /api/v1* is the public CONTENT api — pregnancy and child calendars,
    # protocols, the vaccination schedule, shop products. Read-only, key-gated
    # when CONTENT_API_KEY is set, and the thing /api-docs documents.
    #
    # It was missing from this list, so every endpoint on that page answered a
    # Caddy 404 while the docs beside them loaded fine: the API looked empty
    # and broken to anyone who followed the link. It carries no user data —
    # everything user-scoped is in @app behind a session.
    # /join/* is where a family invitation link lands (screen 40). Public by
    # necessity: the relative tapping it has no session yet, and the page only
    # shows the code and says what to do with it — it accepts nothing.
    # Published reference data — the MOH antenatal protocol, the vaccination
    # calendar, the pregnancy and child-development weeks, the daily audio.
    # Constants compiled into the server: they name nobody, never vary by
    # caller, and are the same rows /api/v1 already serves publicly.
    # /emergency-help is screen 37's scenarios (frame 16b). PUBLIC rather than
    # in @app on purpose: it is the screen somebody opens because a child
    # cannot breathe, and a woman whose session expired must not meet a 401 —
    # or, worse, Caddy's 404, which the app reads as the server being down.
    # It carries no user data; the address and the doctor's number on that
    # screen come from /profile, which stays session-scoped.
    @public path / /robots.txt /sitemap.xml /landing/* /shop /shop/* /health /ready \
                 /api-docs /api/v1 /api/v1/* /join/* \
                 /antenatal/* /pregnancy/* /child/development* /vaccination/* /audio/* \
                 /emergency-help /privacy /terms

    # ---- The app ------------------------------------------------------------
    #
    # Opened 2026-08-05, and only because the thing that made it unsafe is
    # fixed. Until today \`curl -H 'x-user-id: <any uuid>' /children\` answered
    # 200: the dev shortcuts were gated on REAL_AUTH, which is about Firebase,
    # and this deployment has no Firebase — so they were never off. They are now
    # gated on the presence of a database, and the same request returns 401.
    #
    # /auth/phone* is how a session is obtained, so it cannot require one. It is
    # rate-limited per number in the handler and per source below.
    #
    # The GLOB matters. Sign-in became two steps — /auth/phone/start sends a
    # code, /auth/phone/verify redeems it — and \`handle /auth/phone\` matches
    # that one exact path and nothing beneath it. Left as it was, both new
    # endpoints would have fallen through to the catch-all 404 and nobody could
    # have signed in at all, while every test on the box passed.
    #
    # If this ever needs closing in a hurry, delete this block and re-run the
    # script; the app degrades to its local store rather than breaking.
    handle /auth/phone* {
        rate_limit {
            zone app_signin {
                key    {remote_host}
                events 30
                window 10m
            }
        }
        reverse_proxy ${BACKEND}
    }

    # Every session-scoped route the app calls. This list is written by hand
    # and the routes are not, so it drifts silently — a path absent here gets
    # Caddy's catch-all 404 and the app reads that as the server being down.
    # src/__tests__/edgeAllowlist.test.ts compares the two sides and fails when
    # they part company; it was written after this drift was found, and it
    # found more.
    #
    #   /course*  — the Ма!Ма! course. The app calls /course/lessons on the
    #               profile tab and /course/progress on every lesson, and
    #               NEITHER has ever been allowed through: the thing the
    #               комплект charges 9 200 ₸ extra for could not load in
    #               production while working perfectly on the box.
    #   /family*  — screen 40, added with family access.
    #   /metrics* — the vitals history query. Registered since long before this
    #               file; no app caller today, allowed so the next one works.
    #   /support* — screen 43, the app end of the operator's desk. Left out, the
    #               push telling her «Поддержка ответила» would open a screen
    #               that says the conversation did not load.
    #   /announcements* — frame 06, the app end of the marketing tab. Left out,
    #               the back office publishes a рассылка, counts it as
    #               delivered, and no phone ever finds out.
    @app path /account* /ai/* /alerts* /announcements* /app/* /appointments* \
              /auth/logout /calibration/* /children* /content* \
              /contraction-sessions* /course* /cry/* /cycle* /devices* /doses* \
              /family* /geofences* /growth* /ingest/* /kick-sessions* \
              /medications* /metrics* /newborn-events* /profile* /sleep* \
              /support* /vaccines* /vitals* /weight*
    handle @app {
        reverse_proxy ${BACKEND}
    }
    handle @public {
        reverse_proxy $BACKEND
    }

    handle {
        respond "Not found" 404
    }

    header {
        # HSTS, raised in stages. The risk is asymmetric: a bad certificate with
        # a long max-age traps every visitor who has ever loaded the site on a
        # broken page for the whole cached duration, and there is nothing the
        # server can do about it — the browser stops asking.
        #
        #   0        first days, while the cert and the redirect settle
        #   86400    now (2026-08-05): two days stable, auto-renewal working,
        #            and uptime-check.sh watches expiry with 10 days' warning.
        #            A mistake self-heals within a day.
        #   31536000 after about a week at 86400 with nothing going wrong.
        #
        # Do not add \`preload\` at any point without meaning it: that one is a
        # hardcoded browser list and getting off it takes months.
        Strict-Transport-Security "max-age=86400"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}

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
  cat "$BACKUP" > "$CADDYFILE"   # rewrite, not replace: keeps the inode the mount follows
  exit 1
fi
echo "==> Config validates"

# Getting the file INTO the container.
#
# Not `docker cp` onto /etc/caddy/Caddyfile: that path is a bind-mount point,
# and Docker refuses with "device or resource busy". (An earlier version of this
# script did exactly that and died here every run, after reporting that the
# config validated — so it looked like a deploy right up to the point it wasn't.)
#
# The mount is the delivery mechanism. It works, as long as it still points at
# the inode we just wrote: a bind-mounted FILE follows the inode, not the path,
# and anything that replaces the file rather than rewriting it detaches the
# container silently. So: compare, and if they differ, restart to re-resolve the
# mount and compare again. A restart costs about two seconds of 502s.
container_sum() { docker exec "$CONTAINER" sha256sum /etc/caddy/Caddyfile | cut -d' ' -f1; }

if [ "$HOST_SUM" != "$(container_sum)" ]; then
  echo "==> The container is reading a stale inode — restarting to re-resolve the mount"
  docker restart "$CONTAINER" >/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 2
    curl -sf -o /dev/null "https://ana-bala.kz/health" && break
  done
fi

IN_SUM="$(container_sum)"
if [ "$HOST_SUM" != "$IN_SUM" ]; then
  echo "!! The container is still not reading the file we wrote — refusing to claim a deploy"
  echo "   host:      $HOST_SUM"
  echo "   container: $IN_SUM"
  cat "$BACKUP" > "$CADDYFILE"   # rewrite, not replace: keeps the inode the mount follows
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
# Captured then matched in the shell, never piped into `grep -q`: that shape is
# inverted by SIGPIPE under pipefail and has twice made a check report the
# opposite of the truth. See packages/backend/src/__tests__/deployScripts.test.ts.
printf '    basic srv: '
HDRS="$(curl -sI --max-time 15 https://ana-bala.kz/admin/ui || true)"
case "$(printf '%s' "$HDRS" | tr 'A-Z' 'a-z')" in
  *www-authenticate*) echo 'STILL PROMPTING — the edge password did not go away' ;;
  *)                  echo 'gone (the app signs staff in)' ;;
esac
# Both forms of the retired storefront URL land on the landing. The one with
# the trailing slash is what a browser leaves on a bookmark, and it 404'd.
printf '    /shop    : HTTP '; curl -s -o /dev/null -w '%{http_code}' https://ana-bala.kz/shop
printf ' , /shop/ HTTP '; curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/shop/   # both 302
# The one that regressed once: a forged user header must NOT reach the backend.
# Sign-in, reported as routed / not routed rather than as a status code.
#
# This probed `POST /auth/phone`, which stopped existing when sign-in became two
# steps, so it printed a truthful 404 that read as "sign-in is broken" on a
# server where sign-in worked perfectly. A check whose healthy output looks like
# a failure gets ignored, which is worse than not having the check.
#
# A status code cannot answer the question anyway: Caddy 404s an unlisted path
# and Fastify 404s a GET to a POST-only route, and those are the same number.
# Who answered is the thing that matters — Caddy's body is plain text, ours is
# JSON. Same test as `reaches` in update.sh.
#
# GET on purpose. A POST to /auth/phone/start signs that number in and leaves a
# real account behind; a deploy check must not write to production.
printf '    app signin: '
SIGNIN="$(curl -s --max-time 15 https://ana-bala.kz/auth/phone/start || true)"
case "$SIGNIN" in
  *'{'*) echo 'routed to the backend' ;;
  *)     echo "NOT ROUTED — Caddy answered. Sign-in is dead: $(printf '%s' "$SIGNIN" | head -c 60)" ;;
esac
printf ' , app data unauth: HTTP '; curl -s -o /dev/null -w '%{http_code}
' https://ana-bala.kz/children   # 401
printf '    forged id: HTTP '; curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'x-user-id: 11111111-1111-1111-1111-111111111111' https://ana-bala.kz/children   # expect 404, never 200
echo
echo "Roll back with: bash /opt/umay/deploy/landing-takeover.sh --revert"
