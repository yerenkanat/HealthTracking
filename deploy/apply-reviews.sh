#!/usr/bin/env bash
#
# Put deploy/seed-reviews.json into shop_settings.reviews on the running server.
#
# The three testimonials it holds are ALREADY on the landing page — they are
# baked into the exported artifact. Applying this changes no pixel; it moves
# them into the setting so staff can edit them in the admin panel instead of
# needing a re-export. See seed-reviews.README.md.
#
# Run on the server (it talks to the backend over the loopback interface):
#   ./deploy/apply-reviews.sh
#
# Uses node rather than python for the JSON work: node is guaranteed present
# because it is what runs the backend.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED="$HERE/seed-reviews.json"
API="${API:-http://127.0.0.1:8080}"

[ -f "$SEED" ] || { echo "missing $SEED" >&2; exit 1; }

# The admin API is the only writer of shop_settings, so go through it rather
# than reaching into the database — it audits who changed what.
#
# Auth is the same development stub the admin panel uses: the backend trusts
# x-staff-id / x-staff-role outright. What actually keeps the public out is the
# basic_auth in front of /admin (deploy/admin-access.sh) — which is why this is
# a loopback-only script and why $API defaults to 127.0.0.1. Sending these
# headers from anywhere reachable would be handing over the back office.
STAFF_ID="${STAFF_ID:-seed-reviews}"

# Validate before touching anything: the landing silently ignores a value it
# cannot parse, so a bad save looks exactly like a successful one.
BODY="$(node -e '
const fs = require("fs");
const rs = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!Array.isArray(rs) || !rs.length) throw new Error("expected a non-empty array");
for (const r of rs) {
  for (const k of ["name", "text"]) if (!r[k]) throw new Error(`a review is missing ${k}`);
  const s = Number(r.stars ?? 5);
  if (!(s >= 1 && s <= 5)) throw new Error("stars must be 1..5");
}
const kz = rs.filter((r) => r.text_kz).length;
process.stderr.write(`  ${rs.length} reviews, ${kz} with Kazakh text\n`);
// The setting is a STRING holding JSON, not a JSON array — /shop/config hands
// it to the page verbatim for the page to parse.
process.stdout.write(JSON.stringify({ reviews: JSON.stringify(rs) }));
' "$SEED")"

curl -fsS -X PUT "$API/admin/settings" \
  -H 'content-type: application/json' \
  -H "x-staff-id: $STAFF_ID" \
  -H 'x-staff-role: admin' \
  -d "$BODY" > /dev/null

# Read it back through the PUBLIC route — that is the one the landing calls, and
# it exposes only the public keys. If reviews came back empty here the page
# would keep showing the baked-in copy, and the change would look applied.
curl -fsS "$API/shop/config" | node -e '
let raw = "";
process.stdin.on("data", (d) => (raw += d)).on("end", () => {
  const rs = JSON.parse(JSON.parse(raw).reviews || "[]");
  if (!rs.length) throw new Error("reviews did not survive the round trip");
  console.log("applied: " + rs.map((r) => r.name).join(", "));
});
'
