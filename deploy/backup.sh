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
#
# This block used to compare a hardcoded list of five tables, and it was very
# nearly a no-op:
#
#   * `profiles` does not exist — the table is `users` — and a missing table was
#     silently skipped, so the list quietly shrank to four without a word;
#   * three of the four held zero rows, and "0 rows — match" is two empty tables
#     agreeing with each other. A restore that produced nothing but a schema
#     would have matched on all three;
#   * staff_accounts, the table that now decides who can open the back office,
#     was not among them;
#   * pg_restore's exit code was discarded with `|| true`.
#
# So it now enumerates the live tables instead of naming them, compares every
# one, and refuses to call an all-empty comparison a verified restore.
if [ "${1:-}" = "--verify" ]; then
  echo "==> Restoring into a scratch database and comparing"
  scratch="umay_restore_check"
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $scratch;" >/dev/null
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $scratch;" >/dev/null

  # Errors are shown rather than swallowed. Warnings are normal (ownership,
  # extensions), so the exit code decides, not the presence of output.
  if ! docker exec -i "$CONTAINER" pg_restore -U "$DB_USER" -d "$scratch" --no-owner < "$out" > /tmp/umay-restore.log 2>&1; then
    echo "!! pg_restore reported errors:"
    tail -20 /tmp/umay-restore.log | sed 's/^/       /'
    docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE $scratch;" >/dev/null
    exit 1
  fi

  # Every base table in the live database, not a list somebody has to remember
  # to update. A new table is compared the night it appears.
  tables="$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")"
  [ -n "$tables" ] || { echo "!! no tables found in $DB_NAME — refusing to claim a verified restore"; exit 1; }

  fail=0
  compared=0
  nonempty=0
  for t in $tables; do
    a="$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT count(*) FROM \"$t\"" 2>/dev/null || echo error)"
    b="$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$scratch" -tAc "SELECT count(*) FROM \"$t\"" 2>/dev/null || echo missing)"
    compared=$((compared + 1))
    if [ "$a" = "$b" ]; then
      [ "$a" != "0" ] && nonempty=$((nonempty + 1))
      # Only the tables with something in them are worth a line; the rest would
      # bury them under thirty "0 rows" every night.
      [ "$a" != "0" ] && printf '    %-24s %s rows — match\n' "$t" "$a"
    else
      printf '    %-24s live=%s restored=%s — MISMATCH\n' "$t" "$a" "$b"
      fail=1
    fi
  done

  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE $scratch;" >/dev/null
  [ "$fail" = 0 ] || { echo "!! the restore does not match the live database"; exit 1; }

  # The guard that makes the rest mean something. Without it, a restore that
  # recreated the schema and no data would pass every comparison above as long
  # as the live database were also empty — and it would go on passing every
  # night until the first time somebody needed the backup.
  if [ "$nonempty" = 0 ]; then
    echo "!! every one of the $compared tables was empty on both sides."
    echo "   That is not a verified restore, it is two empty databases agreeing."
    exit 1
  fi
  echo "    restore verified — $compared tables compared, $nonempty of them with rows"
fi

echo
echo "Backups in $DEST — $(ls -1 "$DEST/daily" | wc -l) daily, $(ls -1 "$DEST/monthly" 2>/dev/null | wc -l) monthly."
echo
echo "STILL TO DO: these live on the same machine as the database. A host that"
echo "dies takes both. Copy $DEST somewhere else — object storage, another box,"
echo "anything not this disk — see deploy/backup-install.sh for where to hook it."
