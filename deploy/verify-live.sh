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
echo "-- The panel can actually be signed into"
#
# A panel that returns 200 and paints NOTHING is the failure this section
# exists for, and it has happened: every check above passed while the browser
# showed a blank page. 200 says the file arrived, not that anything is on it.
#
# Signed out, /admin must offer the sign-in gate. These are the elements that
# gate is made of — if the served build has lost any of them, showLogin() puts
# the operator in front of a white screen with no way in.
for el in loginGate appShell loginForm loginPhone loginErr; do
  body /admin "id=\"$el\"" "the sign-in gate has $el"
done
# The rule that makes `hidden` mean hidden. Without it any author `display`
# rule outranks the attribute, and the gate and the shell can BOTH end up
# painted or both invisible — the second of which is a blank page.
body /admin 'hidden]{display:none!important' "hidden actually hides"
# start() is what asks who you are. Defined and never called is this repo's
# signature defect, and here it would mean nothing ever unhides.
body /admin 'start();' "the panel boots itself"

echo
echo "-- The build being served is the one in this checkout"
# A marker present locally and absent live means the container did not restart
# with the new file — a deploy that reported success and changed nothing.
LOCAL_PANEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/admin/index.html"
if [ -f "$LOCAL_PANEL" ]; then
  MISSING=0
  for marker in 'data-view="catalog"' 'data-view="support"' 'data-view="finance"' 'supRule'; do
    if grep -q -- "$marker" "$LOCAL_PANEL"; then
      case "$(fetch /admin)" in
        *"$marker"*) : ;;
        *) MISSING=$((MISSING+1)) ;;
      esac
    fi
  done
  if [ "$MISSING" -eq 0 ]; then
    pass "the served panel matches this checkout"
  else
    fail "$MISSING feature(s) are in this checkout and NOT on the site — the box did not pull, or the container did not restart"
  fi
fi

echo
echo "-- Does a REAL browser paint anything?"
#
# The check that would have saved two sessions. Every other test in this file
# reads bytes: it can tell you the file arrived, the markers are in it and the
# endpoints answer — and every one of them passed while the operator looked at
# a white screen. "200 OK" is not "somebody can use it".
#
# So: run headless Chrome, let the page boot, and assert the DOM it ends up
# with actually contains the sign-in form. Chrome does CSS layout and jsdom
# does not, which is the exact gap this project has been bitten through twice —
# a `display` rule outranking the `hidden` attribute is invisible to every
# byte-level check ever written.
CHROME=""
for c in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
  "$(command -v google-chrome 2>/dev/null)" \
  "$(command -v chromium 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { CHROME="$c"; break; }
done

if [ -z "$CHROME" ]; then
  # Not a failure: CI may have no browser. But say so, because a silent skip
  # is how this check quietly stops running.
  echo "  SKIP no Chrome found — the paint check did not run"
else
  DOM="$(mktemp)"
  "$CHROME" --headless=new --disable-gpu --no-sandbox \
    --virtual-time-budget=10000 --dump-dom "$BASE/admin" > "$DOM" 2>/dev/null || true

  if [ ! -s "$DOM" ]; then
    fail "Chrome rendered nothing at all — the page did not boot"
  else
    # Signed out, the panel must end up showing the sign-in form. The check is
    # on the POST-BOOT dom: `hidden` removed from the gate is the proof that
    # start() ran, got its answer, and revealed something.
    case "$(cat "$DOM")" in
      *'id="loginGate"'*) : ;;
      *) fail "the rendered page has no sign-in gate" ;;
    esac
    # `<div ... id="loginGate">` with NO hidden attribute. If it still carries
    # hidden after boot, the operator is looking at a white page.
    if grep -qE '<div[^>]*id="loginGate"[^>]*hidden' "$DOM"; then
      fail "the sign-in gate is still hidden after boot — THIS IS A BLANK PAGE"
      echo "         start() never revealed it: check /admin/me and the boot handler"
    else
      pass "the sign-in form is on screen after boot"
    fi
    # And the words a human would actually read, so an empty-but-present form
    # cannot pass either.
    case "$(cat "$DOM")" in
      *'Вход для персонала'*) pass "the form has its heading" ;;
      *) fail "the sign-in form rendered without its heading" ;;
    esac
  fi
  rm -f "$DOM"
fi

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
