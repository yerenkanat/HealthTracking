#!/usr/bin/env bash
# =============================================================================
# Ana-Bala — ship what is on the branch to the running box.
#
#   ssh root@188.137.231.252 'bash /opt/umay/deploy/update.sh'
#
# or, if the checkout is stale, from the box:
#
#   cd /opt/umay && git pull && bash deploy/update.sh
#
# What it does: pulls, applies any new migrations, replaces the backend
# container so new code and the static admin/landing HTML are re-read, then
# CHECKS the things this release actually changed rather than assuming a
# successful restart means a successful deploy.
#
# That last part is the point. `docker restart` exits 0 whether or not the
# thing inside came up correctly, and the backend reads admin/index.html and
# shop/*.html ONCE at startup — so a deploy that "worked" has, more than once,
# meant a container running old markup while every command reported success.
#
# Idempotent and safe to re-run. Applying migrations twice is a no-op
# (schema_migrations records what has run).
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/umay}"
NETWORK="${NETWORK:-supabase_default}"
ENV_FILE="${ENV_FILE:-/etc/umay/backend.env}"
NODE_IMAGE="${NODE_IMAGE:-node:24-alpine}"
BACKEND=umay-backend

cd "$APP_DIR"

echo "==> Preconditions"
[ -f "$ENV_FILE" ] || { echo "no $ENV_FILE — run deploy/landing-stack.sh first"; exit 1; }
docker ps --format '{{.Names}}' | grep -qx "$BACKEND" || echo "    ($BACKEND is not running; it will be created)"
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

echo "==> Pulling"
BEFORE="$(git rev-parse --short HEAD)"
git pull --ff-only
AFTER="$(git rev-parse --short HEAD)"
echo "    $BEFORE -> $AFTER"
[ "$BEFORE" = "$AFTER" ] && echo "    (nothing new; continuing anyway so a half-finished deploy completes)"

echo "==> Dependencies"
docker run --rm -v "$APP_DIR:/app" -w /app "$NODE_IMAGE" \
  npm ci --omit=dev --ignore-scripts 2>&1 | tail -3

echo "==> Migrations"
docker run --rm --network "$NETWORK" -v "$APP_DIR:/app" -w /app/packages/backend \
  -e DATABASE_URL="$DATABASE_URL" "$NODE_IMAGE" node db/apply.mjs 2>&1 | tail -15

# ---- Restart -----------------------------------------------------------------
# Removed and recreated, not restarted: the container has the repo bind-mounted,
# and this is also what picks up a changed env file.
echo "==> Replacing $BACKEND"
docker rm -f "$BACKEND" >/dev/null 2>&1 || true
docker run -d --name "$BACKEND" --restart unless-stopped --network "$NETWORK" \
  --env-file "$ENV_FILE" -v "$APP_DIR:/app" -w /app/packages/backend \
  "$NODE_IMAGE" npx tsx src/index.ts >/dev/null

echo "==> Waiting for /health"
for i in $(seq 1 45); do
  if docker run --rm --network "$NETWORK" "$NODE_IMAGE" \
       wget -qO- "http://$BACKEND:8080/health" >/dev/null 2>&1; then
    echo "    OK"; break
  fi
  [ "$i" = 45 ] && { echo "    never answered:"; docker logs --tail 40 "$BACKEND"; exit 1; }
  sleep 2
done

# ---- Verify what this release changed ----------------------------------------
#
# Every check below reads the RUNNING service, not the repo. A file on disk
# proves nothing about the process serving requests.
echo
echo "==> Schema"
# --input-type=module: `node -e` is CommonJS by default, where a top-level
# await is a syntax error — so this printed nothing and every check below it
# "passed" by finding nothing to disagree with.
q() { docker run --rm --network "$NETWORK" -e DATABASE_URL="$DATABASE_URL" \
        -v "$APP_DIR:/app" -w /app/packages/backend "$NODE_IMAGE" \
        node --input-type=module -e "
import pg from 'pg';
const c = new pg.Client(process.env.DATABASE_URL);
await c.connect();
const r = await c.query(process.argv[1]);
console.log(r.rows.length ? 'FOUND' : 'ABSENT');
await c.end();
" "$1"; }

for col in "shop_orders bundle_id" "shop_orders phone_normalized" "shop_products grants_feature" \
           "course_progress phone" "course_progress completed" \
           "device_registry serial" "device_registry status" \
           "audit_log reason"; do
  table="${col%% *}"; column="${col##* }"
  if q "SELECT 1 FROM information_schema.columns WHERE table_name='$table' AND column_name='$column'" | grep -qx FOUND; then
    echo "    $table.$column OK"
  else
    # Named individually rather than blamed on one migration: this list spans
    # 025 through 029, and "migration 025 did not apply" sent somebody to the
    # wrong file the last time a later one was the problem.
    echo "!!  $table.$column MISSING — a migration did not apply"; exit 1
  fi
done

# The combo has to carry the entitlement, or a sale grants nothing.
if q "SELECT 1 FROM shop_products WHERE id='combo' AND grants_feature='mama_course'" | grep -qx FOUND; then
  echo "    combo grants mama_course OK"
else
  echo "!!  the комплект grants nothing — migration 025's UPDATE did not run"; exit 1
fi

echo
echo "==> Endpoints (as the proxy sees them)"
check() { # path, grep-pattern, label
  local body
  body="$(docker run --rm --network "$NETWORK" "$NODE_IMAGE" wget -qO- "http://$BACKEND:8080$1" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q "$2"; then
    echo "    $3 OK"
  else
    echo "!!  $3 FAILED — $1 did not contain $2"; exit 1
  fi
}
# The комплект has to be in the public catalogue, or nobody can order it.
check "/shop/products" '"kind":"bundle"' "the комплект is sellable"
check "/shop/products" '"parts"'         "its parts are listed"
# The panel is one file read at startup; this is what proves the new build is
# the one being served.
check "/admin" 'dashKpis'                "the panel serves the new Dashboard"
check "/admin" 'newOrderBox'             "the panel can take an order"
check "/admin" 'dashCourse'              "the Dashboard shows the course"
check "/admin" 'courseProgressCell'      "the access list shows who is watching"
check "/admin" 'stageGapRows'            "Аналитика shows where the users are"
check "/admin" 'prodSku'                 "the warehouse can record an article code"
check "/admin" 'serialForm'              "the warehouse can record device serials"
check "/admin" 'oserial'                 "an order can record what shipped in it"

echo
echo "==> Routes the PROXY must pass through"
#
# Every check above talks to the backend directly, so it cannot see the one
# thing that actually breaks a release here: Caddy serves an explicit allowlist
# and answers a plain-text 404 to anything missing from it. /api/v1 was absent
# for its whole life — the docs page loaded and every endpoint on it 404ed —
# and `handle /auth/phone` matched one exact path, so the two-step sign-in
# would have died the moment it shipped, with the backend answering perfectly.
#
# Checked against the PUBLIC name, which is the only place the difference shows.
PUBLIC="${PUBLIC_URL:-https://ana-bala.kz}"
proxy() { # path, label, expected-codes...
  local path="$1" label="$2"; shift 2
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$PUBLIC$path" || echo 000)"
  for want in "$@"; do
    if [ "$code" = "$want" ]; then echo "    $label OK ($code)"; return 0; fi
  done
  echo "!!  $label FAILED — $PUBLIC$path answered $code, expected one of: $*"
  echo "    If this is 404 from Caddy, the path is missing from @public/@app in"
  echo "    deploy/landing-takeover.sh — re-run that script."
  return 1
}
FAILED=0
proxy /api/v1                 "the content API is reachable"   200 401 || FAILED=1
proxy /api/v1/pregnancy/weeks "the pregnancy calendar"         200 401 || FAILED=1
proxy /api-docs               "the API docs"                   200     || FAILED=1
# 400/503 both mean it REACHED the handler; 404 means Caddy swallowed it.
proxy /auth/phone/start       "sign-in step one is routed"     400 429 503 || FAILED=1
proxy /shop/products          "the storefront"                 200     || FAILED=1
[ "$FAILED" = 0 ] || { echo "!!  the proxy is not passing everything through"; exit 1; }

echo
echo "==> A malformed id must be refused, not 500"
# Any string in a path used to raise 22P02 out of the ownership check. 401 is
# the right answer here (no credentials); the failure being guarded against is
# a 500.
code="$(docker run --rm --network "$NETWORK" "$NODE_IMAGE" \
  wget -qS -O /dev/null "http://$BACKEND:8080/children/not-a-uuid/location" 2>&1 \
  | awk '/HTTP\//{c=$2} END{print c}')"
case "$code" in
  401|403|404) echo "    $code OK" ;;
  500)         echo "!!  500 — the UUID guard is not in this build"; exit 1 ;;
  *)           echo "    $code (unexpected but not a 500)" ;;
esac

echo
docker ps --filter name=umay --format "    {{.Names}}  {{.Status}}"
echo
echo "Shipped $AFTER."
