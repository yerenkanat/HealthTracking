#!/usr/bin/env bash
# =============================================================================
# Nightly backup of the Umay database.
#
# Until this existed there was no backup of anything: one Docker volume, no
# dump, no snapshot. That is survivable while the only rows are shop_leads and
# stops being survivable the day real families are in there.
#
# What it does:
#   * pg_dump the whole database in the custom format (-Fc), which restores
#     selectively and compresses on its own;
#   * write it OUTSIDE the Docker volume, so losing the volume does not lose the
#     backups with it;
#   * verify the dump is readable before counting it as a success — a corrupt
#     file that nobody opens until a restore is worse than no file at all;
#   * keep DAILY_KEEP days, and one dump per month indefinitely.
#
#   bash deploy/backup.sh            # take one now
#   bash deploy/backup.sh --verify   # take one, then restore it to a scratch
#                                    # database and compare row counts
#
# Install the timer with deploy/backup-install.sh.
# =============================================================================
set -euo pipefail

CONTAINER="${CONTAINER:-umay-db}"
DB_USER="${DB_USER:-umay}"
DB_NAME="${DB_NAME:-umay}"
DEST="${DEST:-/var/backups/umay}"
DAILY_KEEP="${DAILY_KEEP:-14}"

stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
day="$(date -u +%d)"
mkdir -p "$DEST/daily" "$DEST/monthly"
out="$DEST/daily/umay-$stamp.dump"

docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "$CONTAINER is not running"; exit 1; }

echo "==> Dumping $DB_NAME"
# -Fc: custom format. Plain SQL would be simpler to read and far worse to
# restore — no selective restore, no parallelism, and it grows without bound.
docker exec "$CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$out"

# A dump that cannot be listed is not a backup. pg_restore --list parses the
# archive's table of contents, which is the cheapest proof the file is intact.
if ! docker exec -i "$CONTAINER" pg_restore --list < "$out" >/dev/null 2>&1; then
  echo "!! the dump is unreadable — removing it rather than keeping a corpse"
  rm -f "$out"
  exit 1
fi

size="$(du -h "$out" | cut -f1)"
echo "    $out  ($size)"

# One dump a month kept forever: daily rotation alone means a corruption nobody
# noticed for three weeks has already aged out of every copy.
if [ "$day" = "01" ]; then
  cp -a "$out" "$DEST/monthly/umay-$stamp.dump"
  echo "    kept as monthly"
fi

echo "==> Rotating (keeping $DAILY_KEEP daily)"
ls -1t "$DEST/daily"/umay-*.dump 2>/dev/null | tail -n +$((DAILY_KEEP + 1)) | while read -r old; do
  rm -f "$old"
  echo "    removed $(basename "$old")"
done

# ---- Optional: verify by actually restoring -------------------------------
if [ "${1:-}" = "--verify" ]; then
  echo "==> Restoring into a scratch database and comparing"
  scratch="umay_restore_check"
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $scratch;" >/dev/null
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $scratch;" >/dev/null
  docker exec -i "$CONTAINER" pg_restore -U "$DB_USER" -d "$scratch" --no-owner < "$out" >/dev/null 2>&1 || true

  fail=0
  for t in shop_leads shop_orders shop_products profiles children; do
    a="$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo skip)"
    [ "$a" = "skip" ] && continue
    b="$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$scratch" -tAc "SELECT count(*) FROM $t" 2>/dev/null || echo missing)"
    if [ "$a" = "$b" ]; then
      printf '    %-16s %s rows — match\n' "$t" "$a"
    else
      printf '    %-16s live=%s restored=%s — MISMATCH\n' "$t" "$a" "$b"
      fail=1
    fi
  done
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE $scratch;" >/dev/null
  [ "$fail" = 0 ] || { echo "!! the restore does not match the live database"; exit 1; }
  echo "    restore verified"
fi

echo
echo "Backups in $DEST — $(ls -1 "$DEST/daily" | wc -l) daily, $(ls -1 "$DEST/monthly" 2>/dev/null | wc -l) monthly."
echo
echo "STILL TO DO: these live on the same machine as the database. A host that"
echo "dies takes both. Copy $DEST somewhere else — object storage, another box,"
echo "anything not this disk — see deploy/backup-install.sh for where to hook it."
