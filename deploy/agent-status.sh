#!/usr/bin/env bash
# =============================================================================
# Are the agents actually working right now?
#
#   bash deploy/agent-status.sh
#
# Answers it from evidence rather than from anybody's word for it. Run it
# whenever you want to know, including while nothing appears to be happening.
# =============================================================================

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> Are files being written right now?"
DIRTY="$(git status --porcelain | wc -l | tr -d ' ')"
if [ "$DIRTY" -gt 0 ]; then
  echo "  YES — $DIRTY file(s) mid-change. An agent is writing."
  git status --porcelain | head -12 | sed 's/^/     /'
  [ "$DIRTY" -gt 12 ] && echo "     … and $((DIRTY-12)) more"
else
  echo "  No uncommitted changes. Either between units of work, or idle."
fi

echo
echo "==> What has landed, and when"
# Relative timestamps: "14 minutes ago" answers the real question, which is
# whether anything has happened recently, not what the commit hashes are.
git log -8 --pretty=format:'  %h  %<(16)%cr  %s' | cut -c1-110
echo

echo
echo "==> Work in the last hour"
RECENT="$(git log --since='1 hour ago' --oneline | wc -l | tr -d ' ')"
echo "  $RECENT commit(s)"
if [ "$RECENT" -eq 0 ] && [ "$DIRTY" -eq 0 ]; then
  echo "  Nothing committed and nothing in progress — the agents are NOT working."
  echo "  Start them with: /workflows, or ask Claude to relaunch until-done.js"
fi

echo
echo "==> Is main ahead of what is deployed?"
git fetch --quiet origin main 2>/dev/null || true
AHEAD="$(git rev-list --count origin/main..HEAD 2>/dev/null || echo '?')"
BEHIND="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
echo "  local ahead of origin: $AHEAD    behind: $BEHIND"
[ "$AHEAD" != "0" ] && [ "$AHEAD" != "?" ] && \
  echo "  $AHEAD commit(s) not pushed — the server pulls from GitHub, so these are NOT live."

echo
echo "==> Is the live site running this code?"
echo "  (full check: bash deploy/verify-live.sh)"
for marker in 'data-view="catalog"' 'data-view="finance"' 'data-view="integrations"'; do
  BODY="$(curl -s --max-time 15 https://ana-bala.kz/admin 2>/dev/null || true)"
  case "$BODY" in
    *"$marker"*) echo "  live: $marker" ;;
    *)           echo "  STALE: $marker is in the repo but not on the site" ;;
  esac
done

echo
echo "----------------------------------------------------------------------"
echo "  Live progress of a running workflow:  /workflows"
echo "  Full post-deploy check:               bash deploy/verify-live.sh"
