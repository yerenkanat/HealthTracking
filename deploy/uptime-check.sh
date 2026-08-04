#!/usr/bin/env bash
#
# Is the site actually up? Runs every few minutes from a systemd timer.
#
# Nothing was watching. The landing, the lead form and the back office all run
# on one box with one backend, and the first anyone would know of an outage is a
# customer not being called back — which looks identical to no customers.
#
# Alerts go through the same Telegram credentials the lead notifier uses, read
# from the database at check time, so configuring one configures both. With no
# token it still records state and exits non-zero, so `systemctl status
# umay-uptime` and the journal remain a usable record.
#
# It alerts on TRANSITIONS, not on every failing check: a five-minute outage
# should be one message and one recovery, not a message every two minutes until
# someone mutes the chat and stops reading it.
#
set -uo pipefail

STATE="${STATE:-/var/lib/umay/uptime.state}"
SITE="${SITE:-https://ana-bala.kz}"
TIMEOUT="${TIMEOUT:-10}"

mkdir -p "$(dirname "$STATE")"

fail=()

# The landing itself, as a visitor sees it — through the proxy and TLS, not
# against the container. A backend that answers while Caddy is broken is still
# an outage.
code="$(curl -s -o /dev/null -m "$TIMEOUT" -w '%{http_code}' "$SITE/" || echo 000)"
[ "$code" = "200" ] || fail+=("landing HTTP $code")

# The database behind it. /ready reports 503 with a per-dependency breakdown, so
# this catches a backend that is serving cached pages over a dead Postgres.
ready="$(curl -s -m "$TIMEOUT" "$SITE/ready" || echo '')"
case "$ready" in
  *'"ready":true'*) ;;
  *) fail+=("not ready: ${ready:-no response}") ;;
esac

# Certificate expiry. Caddy renews automatically, and automatic renewal failing
# quietly is exactly the kind of thing nobody notices until the browser warning.
if expiry="$(echo | openssl s_client -connect "${SITE#https://}:443" -servername "${SITE#https://}" 2>/dev/null \
             | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"; then
  if [ -n "$expiry" ]; then
    days=$(( ( $(date -d "$expiry" +%s) - $(date +%s) ) / 86400 ))
    [ "$days" -gt 10 ] || fail+=("TLS certificate expires in ${days}d")
  fi
fi

# Disk. The backups, the Postgres volume and the landing assets share it, and a
# full disk takes the database down in a way that looks like a code fault.
used="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
[ "${used:-0}" -lt 90 ] || fail+=("disk ${used}% full")

now="$(date -u +%FT%TZ)"
prev="$(cat "$STATE" 2>/dev/null || echo ok)"

if [ ${#fail[@]} -eq 0 ]; then
  status=ok
  message="Ana-Bala: восстановлено. Сайт снова отвечает. ($now)"
else
  status=down
  message="Ana-Bala: проблема на сайте ($now)"$'\n\n'"$(printf '• %s\n' "${fail[@]}")"
fi

notify() {
  # Same settings row the lead notifier reads, so one token covers both.
  local cfg
  cfg="$(docker exec umay-backend node -e '
    const { Pool } = require("pg");
    const pool = new Pool({ connectionString: process.env.DATABASE_URL });
    pool.query("SELECT key, value FROM shop_settings WHERE key IN ($1,$2)",
      ["telegramBotToken","telegramChatId"])
      .then(r => {
        const m = Object.fromEntries(r.rows.map(x => [x.key, x.value]));
        process.stdout.write((m.telegramBotToken||"") + "\n" + (m.telegramChatId||""));
        return pool.end();
      }).catch(() => { process.stdout.write("\n"); process.exit(0); });
  ' 2>/dev/null)" || return 0
  local token chat
  token="$(printf '%s' "$cfg" | sed -n 1p)"
  chat="$(printf '%s' "$cfg" | sed -n 2p)"
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  curl -s -m 10 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -H 'content-type: application/json' \
    --data-raw "$(printf '{"chat_id":"%s","text":%s}' "$chat" \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
           || printf '"%s"' "$(printf '%s' "$1" | tr '\n' ' ')")")" >/dev/null || true
}

if [ "$status" != "$prev" ]; then
  printf '%s' "$status" > "$STATE"
  notify "$message"
fi

if [ "$status" = down ]; then
  printf '%s\n' "$message" >&2
  exit 1
fi
echo "ok $now"
