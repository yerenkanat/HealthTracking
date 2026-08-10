#!/usr/bin/env bash
# =============================================================================
# Ana-Bala — is the LIVE site actually working?
#
#   bash deploy/verify-live.sh                    # against https://ana-bala.kz
#   PUBLIC_URL=https://staging.example bash deploy/verify-live.sh
#
# Runs from ANYWHERE — a laptop, CI, the box — and talks only to the public
# name. That is the whole point, and it is the difference between this and the
# checks inside update.sh.
#
# WHY BOTH EXIST
#
# update.sh verifies from inside the server, mostly against 127.0.0.1. It
# therefore cannot see the one thing that has broken more releases here than
# anything else: Caddy serves an explicit allowlist and answers a plain 404 to
# any path missing from it. The Ма!Ма! course was unreachable in production for
# its entire life that way — the backend answered perfectly, and every check
# that asked the backend directly passed.
#
# So this asks the internet the same questions a phone and a browser ask.
#
# Exit code is the answer: 0 = everything checked is working.
# =============================================================================

set -uo pipefail   # NOT -e: a failing check must be reported, not abort the run

BASE="${PUBLIC_URL:-https://ana-bala.kz}"
FAILED=0
PASSED=0

pass() { PASSED=$((PASSED+1)); printf '  \033[32mOK\033[0m   %s\n' "$1"; }
fail() { FAILED=$((FAILED+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

# code <path> <label> <acceptable codes...>
code() {
  local path="$1" label="$2"; shift 2
  local got
  got="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$BASE$path" 2>/dev/null || echo 000)"
  for want in "$@"; do
    [ "$got" = "$want" ] && { pass "$label ($got)"; return 0; }
  done
  fail "$label — $BASE$path answered $got, expected one of: $*"
  # 404 from the edge is the signature failure here, so name the fix rather
  # than leaving somebody to rediscover it.
  [ "$got" = "404" ] && echo "         404 is usually Caddy: add the path to @public/@app in deploy/landing-takeover.sh"
  return 1
}

# Fetched once and cached, then searched in memory.
#
# NOT `curl … | grep -q`. That combination is silently wrong under
# `set -o pipefail`, which this script needs for everything else: grep -q exits
# the moment it matches and closes the pipe, curl dies of SIGPIPE (141), and
# pipefail reports the PIPELINE as failed — so a needle that IS present reads as
# absent. This script's first run claimed the fabricated testimonials were gone
# from the live site while they were plainly still on it. A verifier that fails
# in the reassuring direction is worse than none.
declare -A _BODY_CACHE
fetch() {
  local path="$1"
  if [ -z "${_BODY_CACHE[$path]+set}" ]; then
    _BODY_CACHE[$path]="$(curl -s --max-time 20 "$BASE$path" 2>/dev/null || true)"
  fi
  printf '%s' "${_BODY_CACHE[$path]}"
}

# body <path> <needle> <label>
body() {
  local path="$1" needle="$2" label="$3"
  case "$(fetch "$path")" in
    *"$needle"*) pass "$label" ;;
    *)           fail "$label — «$needle» not found at $BASE$path" ;;
  esac
}

# absent <path> <needle> <label>  — the inverse, for things that must NOT ship
absent() {
  local path="$1" needle="$2" label="$3"
  case "$(fetch "$path")" in
    *"$needle"*) fail "$label" ;;
    *)           pass "$label" ;;
  esac
}

echo "==> Verifying $BASE"
echo
echo "-- Reachable at all"
code /                      "the landing loads"                 200
code /health                "the backend is alive"              200
code /ready                 "dependencies are up"               200 503

echo
echo "-- What a customer touches"
code /shop/products         "the storefront lists products"     200
body /shop/products '"kind":"bundle"' "the комплект is orderable"
code /course                "the Ма!Ма! course is reachable"    200 401 403
code /api-docs              "the API docs load"                 200

echo
echo "-- What the app calls"
# 401 is a PASS: it means the route exists and is guarded. 404 means Caddy
# never let it through, which is the failure this script exists to catch.
code /api/v1/pregnancy/weeks "the pregnancy calendar"           200 401
code /children               "the children endpoint is guarded"  401 403
code /alerts                 "the alerts endpoint is guarded"    401 403

echo
echo "-- The back office"
code /admin                 "the panel loads"                   200
# One marker per feature. The backend reads the panel ONCE at startup, so a
# stale container serves an old build of every tab at once — and renders
# perfectly while doing it. Absence here means the deploy did not take.
body /admin 'data-view="catalog"'      "Каталог shipped"
body /admin 'data-view="finance"'      "Финансы shipped"
body /admin 'data-view="integrations"' "Интеграции shipped"
body /admin 'catStages'                "the catalogue can set a stage"
body /admin 'finCaveats'               "Финансы prints what it cannot know"

echo
echo "-- Nothing untrue on the public pages"
# These were live: three invented testimonials and a customer count no query
# produces. Checked against the SERVED page, not the repository, because the
# repository being clean says nothing about what the container is serving.
for ghost in 'Айгерим' 'Мадина' 'Динара' '12 400' '★★★★★'; do
  absent / "$ghost" "«$ghost» is gone"
done

echo
echo "-- TLS"
if curl -s -o /dev/null --max-time 20 "$BASE/" 2>/dev/null; then
  pass "certificate accepted without --insecure"
else
  fail "TLS handshake or DNS failed for $BASE"
fi

echo
echo "======================================================================"
if [ "$FAILED" -eq 0 ]; then
  echo "  $PASSED checks passed. The site is working."
  exit 0
fi
echo "  $PASSED passed, $FAILED FAILED. The deploy is not good."
echo "  A stale panel marker means the container did not restart with the new"
echo "  file; a 404 means Caddy is not routing the path. They are different"
echo "  problems and the lines above say which."
exit 1
