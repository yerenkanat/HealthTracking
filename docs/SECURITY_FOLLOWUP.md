# Security follow-ups — ana-bala.kz

State as of **2026-08-20**. The landing went live on `188.137.231.252` on
2026-08-03; items dated then have not all moved since.

> ## ⚠ STILL OPEN AFTER 17 DAYS — OWNER, NOBODY ELSE CAN DO IT
>
> **The server's root password has not been rotated.** It was pasted into a chat
> on **2026-07-29** and again on **2026-08-03**. Every other control on this page
> — the capability checks, the audit log, the encrypted backups added on
> 2026-08-20 — is defence behind a door whose key is in two chat transcripts.
> Root on that box is the database, the backup directory, and the backup
> encryption key's future.
>
> It is four commands and it is **§1 below**. Nothing in this repository can do
> it, and no amount of code review substitutes for it.

Nothing here is a hypothetical hardening exercise. Items 1–3 are open now and
each has a concrete consequence; 4–8 are smaller, except §8, which is a decision
rather than a task.

---

## 1. Rotate the root password — it has been pasted into a chat twice

**Status:** OPEN, 17 days. **Who:** owner. **Nobody else can.**

The server's root password was shared in conversation on 2026-07-29 and again on
2026-08-03, so it must be treated as compromised regardless of who saw it. It is
deliberately not written down in this repo or in any agent memory.

Every day this stays open, the exposure grows rather than fades: the database
now holds real families, and as of 2026-08-20 root also reaches
`/etc/umay/backup-recipient.pub` — an attacker with root cannot read past
backups, but can swap the recipient key so that every FUTURE backup is encrypted
to them and to nobody you know.

```bash
ssh root@188.137.231.252 'passwd'          # new password, not reused anywhere
ssh-copy-id -i ~/.ssh/<yourkey>.pub root@188.137.231.252
# then, in /etc/ssh/sshd_config:
#   PasswordAuthentication no
#   PermitRootLogin prohibit-password
ssh root@188.137.231.252 'systemctl reload sshd'
```

Do the key first and confirm it works in a **second terminal** before disabling
passwords, or a typo locks everyone out of the box.

---

## 2. Staff auth still does not exist; the panel is behind an edge password

**Status:** mitigated 2026-08-03, not solved. **Who:** developer.

The back-office is reachable again at **https://ana-bala.kz/admin/ui**, behind
HTTP basic auth. Read the password on the box — it is deliberately not in any
chat, ticket or commit:

```bash
ssh root@188.137.231.252 'cat /etc/umay/admin-credentials'
bash /opt/umay/deploy/admin-access.sh            # rotate it
bash /opt/umay/deploy/admin-access.sh --close    # take it away again
```

**That password is the entire boundary.** The page behind it carries the staff
header stub in its own source, so anyone who gets past basic auth has full
read/write over every family's data. Treat it like the root password. It also
belongs on `admin.ana-bala.kz` rather than a path — that DNS record does not
exist yet, which is the only reason it is not there.

Everything below still stands as the real fix.

---

**The original problem:** `authAdmin` trusts the `x-staff-id` / `x-staff-role`
headers outright.

`authAdmin` trusts the `x-staff-id` / `x-staff-role` headers outright. There is
no verifier behind them, and `authPosture()` hardcodes `adminStub = true` for
that reason — it is not an env flag, so it cannot be waved through.

Consequence: `/admin*` returns 404 at the edge, which means **nobody can read
the leads the landing page is collecting**, or set the WhatsApp number in
`shop_settings`. The form works and writes to `shop_leads`; the queue is simply
unreadable until this is built.

Two ways out, either acceptable:

- **Quick:** put the admin panel on `admin.ana-bala.kz` behind Caddy
  `basic_auth`, as `deploy/Caddyfile` already sketches. The header stub stays,
  but the edge password gates it. Good enough for a small staff.
- **Proper:** implement a real staff verifier, flip `adminStub` in
  `authPosture.ts`, and let the boot guard pass.

Until one of those ships, read leads directly:

```bash
docker exec umay-db psql -U umay -d umay \
  -c "SELECT created_at, customer_name, phone, package, locale, status FROM shop_leads ORDER BY created_at DESC;"
```

---

## 3. The app API is closed for the same reason

**Status:** open by design. **Who:** developer.

`authUser` is a header stub until `REAL_AUTH=1` plus a Firebase service account.
While it is open, anyone can read any family's data by typing a header — this
was live for a few hours on 2026-08-03 and is now closed:

```bash
curl -H 'x-user-id: <any id>' https://ana-bala.kz/children    # was 200, now 404
```

The edge serves an allow-list (`/`, `/landing/*`, `/shop/*`, `/health`,
`/ready`); everything else 404s. See `docs/DEPLOY.md` §9 for the exact order of
operations to open it. **The Flutter app cannot point at production until then.**

---

## 4. HSTS is `max-age=0`

**Status:** intentional, revisit. **Who:** developer.

Deliberate for the first deploy: a bad certificate with a live `max-age` traps
every visitor on a broken site for the cached duration. Raise it to `31536000`
once HTTPS has been stable for about a week, in `deploy/landing-takeover.sh`.

## 5. The test CRM's Supabase is still published on `:8081`

**Status:** open. **Who:** owner/developer.

`0.0.0.0:8081` proxies to that stack's Kong. It predates our deployment and was
carried over verbatim rather than changed under a landing-page task, but it is a
second front door on the box and nothing of ours needs it. If the CRM test
instance is finished with, remove the `:8081` site block and stop its containers:

```bash
docker ps --filter label=com.docker.compose.project=supabase
```

## 6. Backups: encrypted as of 2026-08-20, still on the same disk

**Status:** half done. **Who:** owner/developer.

There was no backup of anything until 2026-08-03. There is now a systemd timer
(`umay-backup.timer`, 03:20 UTC) that dumps the database, proves the archive is
readable, restores it into a scratch database and compares row counts, and keeps
14 daily plus one per month.

```bash
systemctl list-timers umay-backup     # when it next runs
journalctl -u umay-backup -n 40       # what the last run did
bash /opt/umay/deploy/backup.sh --verify   # take one now, verified
```

**Encryption (new, and it needs one owner action before the next run works).**
Until 2026-08-20 the dump was `pg_dump -Fc > file` — plaintext. Nothing in the
database is encrypted (§8), so each dump was a portable, self-contained copy of
every mother's blood pressure and triage severity, every child's location trail,
and every child's blood type and allergy list, readable by anyone who obtained
the file. `deploy/backup.sh` now encrypts with **age**, to a public key, and
**refuses to run at all if no key is configured** — there is no plaintext
fallback, because a fallback is where those files came from.

The private key is generated on the owner's machine and is never copied to the
server. That is the point: root on that box gets ciphertext. It also means the
server cannot verify a restore end to end, so the drill below is not optional.

```bash
# on YOUR machine, once
age-keygen -o umay-backup-key.txt        # keep this. It IS the backups.

# on the server, the public line only
apt-get install -y age
install -d -m 700 /etc/umay
echo 'age1...' > /etc/umay/backup-recipient.pub

# the drill: prove you can read one, before you need to
scp root@188.137.231.252:/var/backups/umay/daily/umay-*.dump.age .
age -d -i umay-backup-key.txt -o umay.dump umay-*.dump.age
pg_restore --list umay.dump | head
```

**Until that key is on the box the nightly backup fails,** and it fails loudly in
`journalctl -u umay-backup`. That is deliberate: a night with no backup is
recoverable, a plaintext copy of every family's health record leaving the box is
not. `deploy/backup-install.sh` refuses to install the timer without a key, so
the failure lands in front of whoever is at the terminal.

**Any dumps taken before 2026-08-20 are still plaintext** — including the
monthly one, which never rotates out. backup.sh counts them and prints the
one-liner that encrypts them in place; it does not delete them by itself.

**What is still missing is the half that matters:** every copy is in
`/var/backups/umay` on the same host as the database, so one dead machine loses
both. Add an offsite step — `deploy/backup-install.sh` prints the `rsync` and
`rclone` lines — and restore from it once before believing it. Copying ciphertext
offsite is safe in a way copying the old plaintext dumps was not.

## 7. Postgres credentials

**Status:** fine, noted. `/etc/umay/backend.env` is `chmod 600` and its password
was generated on the box, never typed into a chat. `umay-db` publishes no port —
it is reachable only from the `supabase_default` Docker network.

## 8. Health and location are NOT encrypted at rest — an owner decision

**Status:** open, deliberately not implemented. **Who:** owner decides; developer
implements only after that decision. **Recorded 2026-08-20.**

### What is actually true today

Every one of these is a plaintext column in Postgres:

| Table | Columns | What a reader learns |
|---|---|---|
| `pregnancy_health_metrics` | `heart_rate_bpm`, `spo2_pct`, `systolic_mmhg`, `diastolic_mmhg`, `core_temp_c`, `glucose_mmol`, `triage_severity` | her blood pressure, and which readings the app graded an emergency |
| `bp_calibration` | `systolic_offset`, `diastolic_offset`, the cuff readings | her tonometer readings, weekly |
| `location_history` | `lat`, `lng`, `observed_at` | a child's trail for the last 90 days |
| `children` | `name`, `date_of_birth`, the beacon/tag identity | who the child is |
| `child_emergency` | `blood_type`, `allergies`, `conditions`, `medications`, `doctor_phone`, `contact_phone` | the child's medical card |
| `users` | `phone_e164`, `address`, `doctor_phone`, `due_date`, cycle baselines | where to find her, and that she is pregnant |

`db/schema.sql` claimed the opposite until 2026-08-20. Its privacy block said
`bp_calibration.*_offset` and free text were "stored under application-layer
envelope encryption (see backend/src/crypto). DB stores ciphertext." There is no
`backend/src/crypto`; there never has been; there is no `createCipheriv`, no
`pgcrypto`, no key material anywhere in `packages/backend/src`. The only effect
that sentence ever had was to stop reviewers looking. It has been replaced with
what is true, `pgRepository.ts`'s header along with it, and `pgSchema.test.ts`
now fails the build if this file ever again names a crypto module that is not on
disk.

What IS cryptographic, and this is the entire list: staff passwords (salted
scrypt) and staff session cookies (sha256), both in `src/http/staffAuth.ts`.

What protects health and location instead is a capability check plus an
`audit_log` row with a stated reason on every protected read. That is real and
it is tested — but it is a control on the *running server*. It does nothing at
all for a copy of the data, which is why §6 (the encrypted dump) was the change
worth making first.

### The question that has to be answered before any code is written

**Where does the key live?**

The app and the database are the same box, 188.137.231.252. The backend must
decrypt a mother's blood pressure to render her own screen, unattended, at any
hour. So the key must be reachable by a process on that host without a human —
and anyone who reaches that host as root reaches it too. Encrypting the columns
with a key stored in `/etc/umay/backend.env` next to the database it protects
buys **nothing** against the threat that matters, and costs the queries below.
It would, however, look like protection in an audit, which is worse than the
honest gap.

The options, and what each one is actually worth:

1. **Key on the same host** (env file, systemd credential, file with mode 600).
   Protects against: a stolen *dump* — but §6 already covers that, better.
   Does not protect against: anyone with root, which is the realistic breach.
   **Not worth the query cost.**
2. **Key in an external KMS** (cloud KMS, Vault) — the app calls out to decrypt
   or to unwrap a data key. Protects against a stolen disk and a stolen dump,
   and gives revocation and an access log the box cannot tamper with. Costs a
   dependency the product does not currently have, a network hop on every read
   path, and a decision about what happens when the KMS is unreachable at 3 a.m.
   **This is the only option that changes the answer.**
3. **Key held by the mother** (derived from her credential, decrypted on her
   device). Strongest, and it ends the back office: staff could not read a
   record even with a capability and a reason, so the medical-review queue,
   the emergency feed and support-led troubleshooting all stop working. That is
   a product decision, not a security one.
4. **Full-disk / volume encryption on the host.** Protects against a disk
   physically leaving the datacentre and nothing else — the volume is mounted
   and readable the whole time the machine is up. Cheap, honest, worth doing on
   the next rebuild, and not a substitute for any of the above.

### What ciphertext would break, named

Application-layer envelope encryption means the database sees opaque bytes. It
cannot compare them, order them, range them or index them. Concretely, in
`packages/backend/src/db/pgRepository.ts` and `db/schema.sql`:

- **`triage_severity` is the expensive one.** It is filtered in SQL in four
  places — the mother's own emergency count, the 24-hour emergency total on the
  owner dashboard, the cross-user admin emergency feed, and her recent
  warning/emergency list (`WHERE triage_severity = 'emergency'`,
  `IN ('warning','emergency')`). It also carries a `CHECK (triage_severity IN
  ('ok','info','warning','emergency'))` and the **partial index
  `idx_phm_emergency … WHERE triage_severity = 'emergency'`**, which exists
  precisely because that feed was scanning the largest table in the database.
  Encrypt this column and all four queries become full scans with decryption in
  application code, the CHECK goes, and the index cannot be built at all.
  (Deterministic encryption would keep equality — at the cost of leaking which
  rows are emergencies to anyone counting repeats, which is most of the signal.)
- **The sanity CHECK constraints go.** `sane_hr`, `sane_spo2`, `sane_bp`,
  `sane_device_temp` on `pregnancy_health_metrics`, and `sane_stress`,
  `sane_breath`, `sane_battery`, `sane_hr`, `sane_spo2`, `sane_bp`,
  `sane_temp_day`, `sane_sugar_day` on the daily watch-history table. Postgres
  cannot range-check a ciphertext. Every one of those bounds would have to be
  re-enforced in TypeScript at ingest, and a bound enforced in one place instead
  of two is a bound that eventually is not enforced at all.
- **`ORDER BY c.name`** on `children` — the vaccination list, the emergency-card
  list and the family list all sort children alphabetically in SQL. Ciphertext
  sorts by ciphertext, i.e. randomly. Sorting moves into the app, which also
  means paging over children stops being possible in SQL.
- **`users` search.** The admin user list is `display_name ILIKE $1 OR email
  ILIKE $1 OR regexp_replace(phone_e164 …) LIKE $2`, served by the trigram index
  `idx_users_name_trgm`. If identity columns are in scope, that search ends;
  substring matching over ciphertext is not a thing. This is the boundary
  question to settle: health only, or health plus identity.
- **What does NOT break, and it is more than expected.** Every retention sweep
  (`src/privacy/retention.ts`) filters on timestamps, so the 90-day route purge,
  the audit purge and the rest are untouched. `queryMetrics` filters on
  `user_id`, a time range and `IS NOT NULL`, so the charts survive if NULL stays
  NULL. Foreign keys and `ON DELETE CASCADE` are unaffected, so account deletion
  still works. And `bp_calibration.systolic_offset` / `diastolic_offset` — the
  two columns the false comment actually named — are never filtered or sorted
  on, only read back newest-first by `measured_at`. **Those two could be
  encrypted tomorrow at zero query cost**, which makes them the honest place to
  start if the answer to the key question is ever "yes".

### The decision

Not implemented, and deliberately not shipped as a half-measure. Answer this,
in writing, before any crypto lands in `packages/backend/src`:

> Is there a key store off this host that the backend may call on every read,
> and what should happen to a mother's screen when it is unreachable?

"Yes, KMS" makes option 2 worth doing, starting with bp_calibration. "No" means
this stays as it is, and the honest posture is: **encrypted backups, access
control and audit on the live server, no encryption at rest** — which is what
`db/schema.sql` now says, and it must keep saying it until this changes.

Related: `BACKLOG.md` "Envelope-encrypt health + location columns" and the same
line in `README.md` and `STATUS.md` are this item. They are correct that it is
undone; this section is why.


---

## Verifying the current posture

```bash
bash /opt/umay/deploy/landing-takeover.sh          # prints the checks below
curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/admin/ui                 # 404
curl -s -o /dev/null -w '%{http_code}\n' -H 'x-user-id: x' https://ana-bala.kz/children  # 404
curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/                          # 200
```
