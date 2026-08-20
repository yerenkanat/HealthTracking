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

Nothing here is a hypothetical hardening exercise. **§1 is open and only the
owner can close it**; §5 and §6 are half done. §2, §3 and §4 shipped and are
kept as the record of what changed — a page that says a control is missing after
it was built teaches people to stop reading the page. §8 is a decision rather
than a task.

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

## 2. Staff auth — **done**

**Status:** closed 2026-08-12. **Who:** developer. *(Rewritten 2026-08-20: this
section still described the system it replaced, which is worse than saying
nothing.)*

The back office is at **https://ana-bala.kz/admin** and asks for a phone number
and a password. Migration 019, `packages/backend/src/routes/staffLogin.ts`, roles
and capabilities in `src/auth/capabilities.ts`, session cookie in
`src/http/staffAuth.ts`.

Seed the first account — there is no default, and a back office nobody has an
account for is a locked door with no key:

```bash
DATABASE_URL=... STAFF_PHONE=7… STAFF_PASSWORD=… STAFF_ROLE=owner \
  node packages/backend/db/seed-staff.mjs
```

**What went away with it.** The edge `basic_auth` on `admin.ana-bala.kz` is
gone, and `deploy/landing-takeover.sh` now CHECKS it is gone on every run — an
edge password on top of a real login is a second credential nobody rotates and a
prompt that hides the real one. `deploy/admin-access.sh` and
`/etc/umay/admin-credentials` no longer exist. So did the `x-staff-id` /
`x-staff-role` header stub, and with it `authPosture().adminStub`.

**What is left.** `/admin*` is proxied to the app, and the app refuses without a
session cookie. Failed sign-ins are counted per phone number in the handler and
per source address at the edge (`zone admin_login`, 12 per 5 minutes), so nobody
can walk the eleven-digit phone space one number at a time.

`ADMIN_CLOSED=1 bash deploy/landing-takeover.sh` 404s the whole back office at
the edge — the fast way to shut it if a session ever has to be assumed stolen.

---

## 3. The app API is open, and defended by the app

**Status:** closed 2026-08-05. **Who:** developer. *(Rewritten 2026-08-20 for
the same reason as §2.)*

For a few hours on 2026-08-03, `curl -H 'x-user-id: <any uuid>'
https://ana-bala.kz/children` answered **200** with that family's children. The
dev shortcuts were gated on `REAL_AUTH`, which is about Firebase — and this
deployment has no Firebase, so they were never off. They are now gated on the
presence of a database, and the same request is refused.

The edge is an allow-list (`@public` and `@app` in
`deploy/landing-takeover.sh`); anything not named there is answered by Caddy's
catch-all 404 and never reaches the app.
`packages/backend/src/__tests__/edgeAllowlist.test.ts` compares the two sides
and fails when they part company — **check it on every release**, because a
route missing from that list looks exactly like the server being down and
nothing on the box shows it.

The Flutter app points at production.

---

## 4. HSTS — **done**, at the full year

**Status:** closed 2026-08-20. **Who:** developer.

Staged, deliberately: a bad certificate with a live `max-age` traps every
visitor on a broken site for the cached duration, and there is nothing the
server can do about it. `0` for the first days → `86400` on 2026-08-05 →
`31536000` on 2026-08-20, after fifteen days with a stable certificate and
`uptime-check.sh` watching expiry with ten days' warning. In
`deploy/landing-takeover.sh`.

Two things deliberately NOT added, so nobody has to re-derive why:

- **`preload`** — a hardcoded browser list, and getting off it takes months.
- **`includeSubDomains`** — `admin.ana-bala.kz` is a name this product intends
  to start using. Adding it now would make that subdomain unreachable for a year
  in every browser that had loaded the apex, from the moment it goes live until
  its certificate does. Add it once that record exists and serves HTTPS.

Since 2026-08-20 the edge and the app also send `X-Frame-Options: DENY` and a
Content-Security-Policy. The back office gets a strict, per-response nonce
policy; the public pages get a narrower one that does not restrict `script-src`.
`packages/backend/src/http/securityHeaders.ts` states exactly what that second
policy does not protect against and why it is written that way.

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

`deploy/landing-takeover.sh` ends by printing all of this itself, and
`deploy/verify-live.sh` checks the served pages. The lines below are the ones
worth running by hand, and they are written to be read as pass/fail rather than
as numbers to memorise — the previous version of this block asserted two status
codes that had both changed underneath it.

```bash
bash /opt/umay/deploy/landing-takeover.sh   # rewrites the edge config and prints its checks

# The landing answers.
curl -s -o /dev/null -w '%{http_code}\n' https://ana-bala.kz/                # 200

# A forged identity gets no data. Any code but 200 is a pass; 200 is an incident.
curl -s -o /dev/null -w '%{http_code}\n' \
  -H 'x-user-id: 11111111-1111-1111-1111-111111111111' https://ana-bala.kz/children

# The back office asks the APP for a password, not the browser. A
# WWW-Authenticate line here means an edge password came back.
curl -sI https://ana-bala.kz/admin | grep -i 'www-authenticate' && echo 'EDGE PASSWORD IS BACK'

# The headers added on 2026-08-20.
curl -sI https://ana-bala.kz/admin | grep -iE 'content-security-policy|x-frame-options|strict-transport'
```

On `/admin` the CSP must contain `'nonce-…'` and must NOT contain
`'unsafe-inline'` in `script-src`. If it reads
`base-uri 'none'; object-src 'none'; frame-ancestors 'none'` instead, that is
the EDGE default and the app's own policy did not arrive — either the backend
was not restarted, or the `?` was lost from `?Content-Security-Policy` in the
Caddyfile and Caddy is overwriting what the app sent.
