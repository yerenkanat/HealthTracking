#!/usr/bin/env bash
# =============================================================================
# Nightly backup of the Umay database — encrypted to a key the owner holds.
#
# Until this existed there was no backup of anything: one Docker volume, no
# dump, no snapshot. That is survivable while the only rows are shop_leads and
# stops being survivable the day real families are in there.
#
# Then it existed, and it was a plaintext `pg_dump -Fc > file` — fourteen copies
# of it, on the same disk as the database it copied. Nothing in this database is
# encrypted: not a mother's blood pressure, not her triage severity, not a
# child's location trail, not a child's allergy list. (The privacy block at the
# top of db/schema.sql claimed otherwise for a long time. It was wrong, and it
# has been corrected.) The dump is therefore a portable, self-contained copy of
# every one of those, and the copy is the thing that leaves: a stolen disk, a
# dump attached to a support ticket, an rsync to somewhere it should not go.
#
# So the dump is encrypted here, with age, to a PUBLIC key.
#
#   * A public key and not a passphrase, because this runs unattended at 03:20
#     from a systemd timer. A passphrase this script could read is a passphrase
#     sitting next to the ciphertext, which protects against nothing.
#   * The PRIVATE half is generated on the owner's machine and is never copied
#     to the server. That is the whole point: someone who takes this host gets
#     ciphertext and a public key, which is no use to them. It also means nobody
#     but the owner can restore, which is why the drill below matters.
#   * No key configured is a hard failure, not a plaintext fallback. A fallback
#     is where every plaintext dump in /var/backups/umay came from.
#
# What it does:
#   * pg_dump the whole database in the custom format (-Fc), which restores
#     selectively and compresses on its own;
#   * verify the dump is readable, and with --verify restore it into a scratch
#     database and compare row counts, BEFORE encrypting — verification needs
#     the plaintext, and the plaintext exists only inside this run;
#   * encrypt it, prove the file it kept is ciphertext, and shred the plaintext;
#   * write it OUTSIDE the Docker volume, so losing the volume does not lose the
#     backups with it;
#   * keep DAILY_KEEP days, and one dump per month indefinitely.
#
#   bash deploy/backup.sh            # take one now
#   bash deploy/backup.sh --verify   # take one, then restore it to a scratch
#                                    # database and compare row counts
#
# ---- One-time setup, on the OWNER's machine, not on the server --------------
#
#     age-keygen -o umay-backup-key.txt     # keep it. This file IS the backups.
#                                           # password manager, or offline media.
#     # it prints:  Public key: age1xxxxxxxx...
#
# Then on the server, the public half only:
#
#     install -d -m 700 /etc/umay
#     echo 'age1xxxxxxxx...' > /etc/umay/backup-recipient.pub
#
# ---- Restoring (the part that needs the private key) ------------------------
#
#     age -d -i umay-backup-key.txt -o umay.dump umay-2026-08-20T032000Z.dump.age
#     docker exec -i umay-db pg_restore -U umay -d umay --clean --no-owner < umay.dump
#
# Do that once, deliberately, into a scratch database, before believing any of
# this. An encrypted backup nobody has ever decrypted is not a backup.
#
# Install the timer with deploy/backup-install.sh.
# =============================================================================
set -euo pipefail
umask 077          # nothing this script writes is readable by anyone but root

CONTAINER="${CONTAINER:-umay-db}"
DB_USER="${DB_USER:-umay}"
DB_NAME="${DB_NAME:-umay}"
DEST="${DEST:-/var/backups/umay}"
DAILY_KEEP="${DAILY_KEEP:-14}"
RECIPIENT_FILE="${RECIPIENT_FILE:-/etc/umay/backup-recipient.pub}"

# ---- The key, checked before anything is dumped -----------------------------
#
# Before, not after: a run that dumps first and discovers the problem second has
# already written the plaintext it was trying not to write.
recipient="${BACKUP_RECIPIENT:-}"
if [ -z "$recipient" ] && [ -f "$RECIPIENT_FILE" ]; then
  # First line beginning age1. An age recipient is one such line; anything else
  # in the file is a person's note to themselves about which key it is.
  recipient="$(grep -m1 '^age1' "$RECIPIENT_FILE" || true)"
fi

if [ -z "$recipient" ]; then
  cat >&2 <<'NOKEY'
!! REFUSING TO BACK UP: no encryption key.

   This dump would be a complete, portable copy of every mother's health record
   and every child's location trail, in the clear, on the same disk as the
   database. There is deliberately no plaintext fallback.

   On YOUR machine (not the server):

       age-keygen -o umay-backup-key.txt

   Keep that file. It is the only thing that will ever read these backups.
   Then on the server, the public line only:

       install -d -m 700 /etc/umay
       echo 'age1...' > /etc/umay/backup-recipient.pub

   Or set BACKUP_RECIPIENT=age1... for a one-off run.
NOKEY
  exit 1
fi

case "$recipient" in
  age1*) : ;;
  *) echo "!! $RECIPIENT_FILE holds no age public key (want a line starting age1)" >&2; exit 1 ;;
esac

command -v age >/dev/null 2>&1 || {
  echo "!! age is not installed:  apt-get install -y age   (or age-encryption.org)" >&2
  exit 1
}

stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
day="$(date -u +%d)"
mkdir -p "$DEST/daily" "$DEST/monthly" "$DEST/staging"
chmod 700 "$DEST" "$DEST/daily" "$DEST/monthly" "$DEST/staging"

out="$DEST/daily/umay-$stamp.dump.age"
plain="$DEST/staging/umay-$stamp.dump"

# The plaintext exists for the length of this run and no longer — including when
# the run dies halfway. shred where it is available; the fallback still unlinks.
# Without this trap a pg_restore failure leaves exactly the file this whole
# change is about, lying in the backups directory.
cleanup() {
  [ -e "$plain" ] || return 0
  shred -u "$plain" 2>/dev/null || rm -f "$plain"
}
trap cleanup EXIT INT TERM

docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "$CONTAINER is not running"; exit 1; }

echo "==> Dumping $DB_NAME"
# -Fc: custom format. Plain SQL would be simpler to read and far worse to
# restore — no selective restore, no parallelism, and it grows without bound.
docker exec "$CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$plain"

# A dump that cannot be listed is not a backup. pg_restore --list parses the
# archive's table of contents, which is the cheapest proof the file is intact.
# It runs on the plaintext because that is the only form pg_restore understands:
# after encryption, nothing on this host can open the file at all.
if ! docker exec -i "$CONTAINER" pg_restore --list < "$plain" >/dev/null 2>&1; then
  echo "!! the dump is unreadable — removing it rather than keeping a corpse"
  exit 1
fi

# ---- Optional: verify by actually restoring ---------------------------------
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
#
# It moved ABOVE the encryption step when the dumps became ciphertext, and it
# cannot move back: verifying afterwards would need the private key, and the
# private key is deliberately not on this machine.
if [ "${1:-}" = "--verify" ]; then
  echo "==> Restoring into a scratch database and comparing"
  scratch="umay_restore_check"
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $scratch;" >/dev/null
  docker exec "$CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $scratch;" >/dev/null

  # Errors are shown rather than swallowed. Warnings are normal (ownership,
  # extensions), so the exit code decides, not the presence of output.
  if ! docker exec -i "$CONTAINER" pg_restore -U "$DB_USER" -d "$scratch" --no-owner < "$plain" > /tmp/umay-restore.log 2>&1; then
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

# ---- Encrypt, then prove the file it kept is ciphertext ---------------------
echo "==> Encrypting to $recipient"
age -r "$recipient" -o "$out" "$plain"

# Two checks, because "age exited 0" is not the same as "the file on disk is
# encrypted", and what that guards against is the failure nobody notices: a dump
# that looks backed up and is readable by anyone who copies it.
#
#   * age's binary header begins with the literal age-encryption.org/v1;
#   * PGDMP is pg_dump's custom-format magic. If the kept file starts with that,
#     the plaintext came through and the encryption did nothing.
if ! head -c 21 "$out" | grep -q 'age-encryption.org'; then
  echo "!! $out is not an age file — refusing to keep it"; rm -f "$out"; exit 1
fi
if [ "$(head -c 5 "$out")" = "PGDMP" ]; then
  echo "!! $out is a PLAINTEXT pg_dump — refusing to keep it"; rm -f "$out"; exit 1
fi
[ -s "$out" ] || { echo "!! $out is empty"; rm -f "$out"; exit 1; }

cleanup            # the plaintext goes now, not at exit
trap - EXIT INT TERM

size="$(du -h "$out" | cut -f1)"
echo "    $out  ($size, encrypted)"

# One dump a month kept forever: daily rotation alone means a corruption nobody
# noticed for three weeks has already aged out of every copy.
if [ "$day" = "01" ]; then
  cp -a "$out" "$DEST/monthly/umay-$stamp.dump.age"
  echo "    kept as monthly"
fi

echo "==> Rotating (keeping $DAILY_KEEP daily)"
ls -1t "$DEST/daily"/umay-*.dump.age 2>/dev/null | tail -n +$((DAILY_KEEP + 1)) | while read -r old; do
  rm -f "$old"
  echo "    removed $(basename "$old")"
done

# ---- Dumps written before this script encrypted anything --------------------
#
# They do not rotate out of monthly/ — that directory keeps forever — and they
# are precisely the files this change exists to stop creating. Not deleted here:
# deleting somebody's only backups because a script changed shape is its own
# incident. Named, loudly, every run until they are gone.
legacy="$(find "$DEST" -maxdepth 2 -name 'umay-*.dump' 2>/dev/null | wc -l)"
if [ "$legacy" -gt 0 ]; then
  echo
  echo "!! $legacy PLAINTEXT dump(s) predate this script encrypting anything."
  echo "   Each is a full copy of every family's health and location data in the"
  echo "   clear. Encrypt them in place and they are gone:"
  echo
  echo "     find $DEST -maxdepth 2 -name 'umay-*.dump' | while read -r f; do"
  echo "       age -r $recipient -o \"\$f.age\" \"\$f\" && shred -u \"\$f\"; done"
fi

echo
echo "Backups in $DEST — $(ls -1 "$DEST/daily" | wc -l) daily, $(ls -1 "$DEST/monthly" 2>/dev/null | wc -l) monthly."
echo
echo "STILL TO DO: these live on the same machine as the database. A host that"
echo "dies takes both. Copy $DEST somewhere else — object storage, another box,"
echo "anything not this disk — see deploy/backup-install.sh for where to hook it."
echo
echo "NOT PROVEN BY THIS SCRIPT: that you can decrypt them. Nothing on this host"
echo "can — that is the design. Run the restore drill in the header with your"
echo "private key, once, or the backups are a guess."
