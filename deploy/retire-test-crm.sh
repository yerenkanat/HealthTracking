#!/usr/bin/env bash
#
# Retire the test CRM that shared this box with the Ana-Bala landing.
#
# What it was: an Aiti.kz Supabase CRM, reachable at :8081 and answering 401.
# The owner confirmed it is a test deployment and can go. The real aiti.kz runs
# on a different server (188.137.253.215) and is untouched by any of this.
#
# What this does, in order, verifying the landing after each step:
#   1. Removes the `:8081 { reverse_proxy kong:8000 }` block from the Caddyfile
#      and reloads Caddy in place.
#   2. Stops the CRM's containers.
#
# What it deliberately does NOT do:
#   - Touch aiti_caddy. That container IS the reverse proxy serving ana-bala.kz;
#     stopping it takes the site down. It stays running and is only reloaded.
#   - Run `docker compose down`. aiti_caddy belongs to the same compose project
#     as the CRM, so a project-wide down would take our proxy with it. Explicit
#     per-container stops only.
#   - Delete any volume. Stopping is reversible in one command; deleting the
#     database is not, and nothing here needs the disk back.
#
# Undo:  bash deploy/retire-test-crm.sh --restore
#
set -euo pipefail

CADDYFILE="${CADDYFILE:-/opt/aiti/app/docker/Caddyfile}"
PROXY="${PROXY:-aiti_caddy}"
BACKUP="$CADDYFILE.bak.before-crm-retire"

# Everything except the proxy. whatsapp_ai_bot is already exited.
CRM_CONTAINERS=(
  crm_api
  supabase-studio supabase-kong supabase-auth supabase-rest supabase-storage
  supabase-realtime supabase-meta supabase-pooler supabase-imgproxy
  supabase-edge-functions supabase-redis supabase-db
  wa-session-db whatsapp_ai_bot
)

say() { printf '==> %s\n' "$*"; }

check_landing() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' https://ana-bala.kz/ || true)"
  [ "$code" = "200" ] || { echo "!!  ana-bala.kz returned $code — stopping here"; exit 1; }
  say "ana-bala.kz still 200"
}

reload_caddy() {
  docker exec "$PROXY" caddy reload --config /etc/caddy/Caddyfile 2>&1 | tail -2
}

if [ "${1:-}" = "--restore" ]; then
  [ -f "$BACKUP" ] || { echo "no backup at $BACKUP"; exit 1; }
  say "Restoring the Caddyfile and starting the CRM back up"
  cp -a "$BACKUP" "$CADDYFILE"
  reload_caddy
  # Reverse order: the database and its dependencies first.
  for c in $(printf '%s\n' "${CRM_CONTAINERS[@]}" | tac); do
    docker start "$c" >/dev/null 2>&1 || true
  done
  check_landing
  say "Restored."
  exit 0
fi

command -v docker >/dev/null || { echo "docker not found"; exit 1; }
[ -f "$CADDYFILE" ] || { echo "$CADDYFILE not found"; exit 1; }

check_landing

# ---- 1. The public edge ------------------------------------------------------
if grep -q '^:8081 {' "$CADDYFILE"; then
  say "Backing up the Caddyfile to $BACKUP"
  cp -a "$CADDYFILE" "$BACKUP"

  say "Removing the :8081 block"
  # Delete from the ':8081 {' line to its closing brace at column 0. The
  # ana-bala.kz block above it is untouched.
  awk '
    /^:8081 \{/ { skip = 1 }
    skip && /^\}/  { skip = 0; next }
    !skip
  ' "$BACKUP" > "$CADDYFILE.candidate"

  # Validate BEFORE reloading: a bad Caddyfile that reaches reload takes the
  # landing down with it.
  docker cp "$CADDYFILE.candidate" "$PROXY:/etc/caddy/Caddyfile.candidate"
  if ! docker exec "$PROXY" caddy validate --adapter caddyfile \
        --config /etc/caddy/Caddyfile.candidate >/dev/null 2>&1; then
    echo "!!  the edited Caddyfile does not validate — nothing changed"
    rm -f "$CADDYFILE.candidate"
    exit 1
  fi
  mv "$CADDYFILE.candidate" "$CADDYFILE"
  reload_caddy
  check_landing
else
  say ":8081 block already gone"
fi

# ---- 2. The containers -------------------------------------------------------
say "Stopping the CRM containers (volumes kept)"
for c in "${CRM_CONTAINERS[@]}"; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    docker stop "$c" >/dev/null && printf '    stopped %s\n' "$c"
  fi
done

check_landing

echo
say "Done. Still running:"
docker ps --format '    {{.Names}}\t{{.Status}}'
echo
say "Undo with: bash deploy/retire-test-crm.sh --restore"
