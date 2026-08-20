# Production deploy runbook

How to stand up the Ana-Bala backend (API + admin + storefront) on a fresh Linux
server, plus the optional cry-classifier service and the app build flags. Every
command and env var below is grounded in the code (`packages/backend/src/index.ts`,
`server.ts`, `db/schema.sql`); nothing here is executed automatically — review,
then run.

> **Status: live.** ana-bala.kz serves the landing, the storefront API and the
> back office at `/admin`, from one Node process behind Caddy on the box
> recorded outside this repo. Nightly backups run with a restore drill; the
> uptime check runs every few minutes.
>
> **Still closed:** every app-API route. `REAL_AUTH` is unset, so the backend
> still trusts an `x-user-id` header, and the edge allow-list names no app path.
> The app therefore has no server yet — see `GO_LIVE_APP_API.md` for the ordered
> procedure, and do not open the edge before the check in step 3 returns 401.
>
> **Still on the owner:** rotate the root password (it was shared in plaintext),
> install SSH keys, and choose an offsite backup destination — the backups
> currently sit on the machine they are backups of.

---

## Concrete setup — ana-bala.kz (fresh box, full stack)

Decided config for this deploy. Ready-to-use files live in [`deploy/`](../deploy/):

| Public name | Serves | Notes |
|---|---|---|
| `ana-bala.kz`, `www.ana-bala.kz` | Landing page (`/`) and the storefront API (`/shop…`) only | Root `/` is the Ana-Bala landing page — no redirect. The **app API is closed** at the edge until real auth exists (§9), so `API_BASE=https://ana-bala.kz` does not work yet. |
| `admin.ana-bala.kz` | Not created yet | The back office is served from the main name at **`/admin`** (`/admin/ui` redirects there). Moving it here is pending a DNS A record. |

One Node process on `127.0.0.1:8080` serves all of it; **Caddy** terminates TLS
(auto Let's Encrypt) and routes both names to it.

**DNS to set first** (TLS won't issue until these resolve to the server):
```
ana-bala.kz         A     188.137.231.252
www.ana-bala.kz     A     188.137.231.252
admin.ana-bala.kz   A     188.137.231.252
```
(add matching `AAAA` records for the IPv6 address if you use it).

> ### The box was not empty, and now is
>
> It ran a TEST deployment of the Aiti.kz CRM, which owned ana-bala.kz in its
> Caddyfile. That instance was stood down with `deploy/retire-test-crm.sh`
> (18 containers → 4); the CRM's real production lives on another server and
> was never touched. The Supabase passthrough on :8081 is still preserved
> verbatim by landing-takeover.sh, so nothing there breaks.

**Files in `deploy/`:**
- `landing-stack.sh` — brings up Postgres, Redis and the backend containers.
- `landing-takeover.sh` — generates and applies the live Caddy config, then
  verifies it. `--revert` restores the newest backup. **Use this rather than
  editing the Caddyfile**; it validates a candidate, checks the container is
  really reading what was written, and prints a verification block.
- `backup.sh` + `backup-install.sh` — nightly dump, **encrypted with age to a
  key the owner holds**, with a restore drill into a scratch database. The drill
  enumerates the live tables rather than naming them, and refuses to report
  success if every table was empty on both sides. It refuses to run at all when
  no key is configured; there is no plaintext fallback. See
  `docs/SECURITY_FOLLOWUP.md` §6 for the one-time key setup.
- `uptime-check.sh` + `uptime-install.sh` — the site, `/ready` and TLS expiry,
  every few minutes, alerting on transitions.
- `retire-test-crm.sh` — how the previous tenant of this box was stood down.
- `umay-backend.service`, `backend.env.example`, `bootstrap.sh` — the original
  fresh-box path, kept for standing up a second environment.

**Day-to-day deploy** is a pull and a restart; the backend runs from a bind
mount, so there is no build step:

```bash
cd /opt/umay && git pull && docker restart umay-backend
```

Restart is required for any change to the admin panel HTML, the storefront
pages or the landing — all three are read once at startup.

The step-by-step sections below explain each piece the script automates.

---

## 0. Architecture

- **Backend** — one Node process (`packages/backend`, `tsx src/index.ts`). It
  serves the JSON API **and** the static pages: the landing at `/`, the back
  office at `/admin`, the API docs at `/api-docs`, and the retired storefront
  URLs (`/shop`, `/shop/watch`, `/shop/tracker`, `/shop/umay-watch`), which now
  redirect to the landing. Static HTML is read **once at startup**, so a content
  edit needs a process restart to show.

  The panel is served `no-store`: that one file contains every line of its
  JavaScript, so a cached copy is a stale build of the whole back office. An
  owner lost an evening to one.
- **Landing page** — `/` is built from the exported artifact
  `docs/Ana-Bala Landing.html` into `packages/backend/landing/` (tracked in git).
  Rebuild it after every re-export, then restart the backend:

  ```bash
  node packages/backend/tools/build-landing.mjs
  systemctl restart umay-backend
  ```

  The page's callback form POSTs to `/shop/leads`; the requests show up in the
  admin panel under **Магазин → Заявки с лендинга**.
- **Postgres** — the system of record. Built from `db/schema.sql` on a fresh box.
- **Redis** *(optional)* — rate limiting / caches (`REDIS_URL`); the app runs
  without it.
- **cry-classifier** *(optional, separate service)* — `packages/cry-classifier`,
  a FastAPI model server the backend proxies to for `/cry/analyze`. Off unless
  deployed + `CRY_API_URL` is set (see §7).
- **App** — the Flutter client, built pointing at this backend via
  `--dart-define=API_BASE=…` (see §8).

---

## 1. Security first (do this before anything else)

1. **Rotate the root password** — it was shared in plaintext once and must be
   considered compromised.
2. Create a non-root deploy user; put the app under it (never run the service as
   root).
3. **SSH-key auth only** — install your public key, then set
   `PasswordAuthentication no` and `PermitRootLogin no` in `sshd_config` and
   reload sshd.
4. Firewall (ufw/nftables): allow 22, 80, 443 only. Postgres (5432) and the app
   port (8080) stay bound to localhost — never exposed publicly.
5. Give Postgres its own strong password; keep it (and all secrets) in the
   backend's env file (`chmod 600`, owned by the deploy user), not in git.

---

## 2. Prerequisites

- Node.js 24.x (the repo runs on `tsx`; `node --version` ≥ 24).
- PostgreSQL 15+ (`uuid-ossp`/`pgcrypto` as required by `schema.sql`).
- (optional) Docker + Compose for the cry-classifier and/or Redis.
- A domain pointed at the server (needed for TLS and for the WhatsApp/Kaspi
  deep-links to look trustworthy).

---

## 3. Database

Create the role + database, then build the schema.

```bash
sudo -u postgres psql -c "CREATE ROLE umay LOGIN PASSWORD '<strong-secret>';"
sudo -u postgres psql -c "CREATE DATABASE umay OWNER umay;"
```

**Fresh build (this box) — run the schema from scratch:**
```bash
psql "postgres://umay:<secret>@127.0.0.1:5432/umay" -f packages/backend/db/schema.sql
```
`schema.sql` creates every table (43 as of migration 026, incl.
`cry_results`, `sleep_nights.source/manual_asleep_min`, `cycle_day_logs.note`,
the inventory ledger and the Ма!Ма! course tables).

**Upgrading an existing DB instead — apply migrations in order:**
```bash
for f in packages/backend/db/migrations/0*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```
Migrations `001`–`026` are each idempotent (`IF NOT EXISTS`). Recent ones:
**019** (staff accounts, sessions and login attempts — what the back-office
sign-in runs on), **020** (phone sign-in for the app), **021** (the stock
ledger, bundles, cost and SKU), **023**–**024** (Ма!Ма! course entitlements and
lessons), **025** (bundle orders, and a product carrying what its sale grants),
**026** (course progress — how far each customer has got, keyed by phone).

Apply them with `node db/apply.mjs`, which records what it has run; `schema.sql`
and the migrations must agree, and `pgSchema.test.ts` fails when they drift. Note in `001`: on a live DB with real data, add
`CONCURRENTLY` to the index statements so they don't take an exclusive lock.

A fresh `schema.sql` box does **not** need the migrations (they'd no-op).

### 3a. Run `db:smoke` once, on a THROWAWAY database, before the first deploy

**Do this once per release that touches `db/` or `src/db/pgRepository.ts`, and
you must do it before the retention sweeps first fire on a box.**

```bash
cd packages/backend
docker compose up -d --wait                       # a scratch Postgres on :5433
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run db:apply
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run db:smoke
echo $?                                           # must be 0; read it directly
docker compose down -v
```

**Never point this at production.** It inserts rows and it runs the real
eight-table retention sweep — `sweepAll()`, the same call the scheduler makes —
against whatever database `DATABASE_URL` names. On a scratch box that is the
point; on production it would delete real rows on a cutoff computed from the
moment you ran it.

Why it is a step and not a nicety:

- `src/privacy/retention.ts` schedules **eight DELETEs every six hours**
  (`SWEEP_INTERVAL_MS`), starting at boot. They erase a child's zone crossings,
  a mother's sign-in history, her SOS record and the audit trail that proves
  nobody read her file unexplained. Every vitest test of them runs against the
  **in-memory** repository. `pgRepository.ts` is what actually deletes.
- `sweepOne()` never throws — a failing sweep is recorded in
  `RetentionResult.error` and logged, so a DELETE naming a column that does not
  exist looks exactly like a quiet, healthy, six-hourly no-op. Nothing on the
  box goes red.
- The full unit suite stays **green** with a wrong column in the
  `geofence_events` sweep. `db:smoke` reports
  `✗ geofence_events: the DELETE executed against real Postgres — column
  "created_at" does not exist`. That is the entire reason this step exists.
- It also proves the survivors: a row **exactly** at the cutoff must live
  (the predicate is `<`, never `<=`), a support thread with a recent reply must
  live with its replies, `phone_codes` must sweep on `created_at` and not on
  `expires_at`, and a five-year-old `shop_orders` row must be untouched by all
  eight (`RETENTION_KEPT` — accounting records have no period an engineer may
  invent).
- It builds the schema **from scratch**, which is the only way the
  `schema.sql`-only path gets exercised at all. That path was broken —
  `shop_product_photos` referenced `staff_accounts` forty tables before it
  exists, so `db/apply.mjs` aborted on step 1 and no fresh install could be
  built. Every migrated server was fine, which is why it went unnoticed.

---

## 4. Backend service

```bash
cd packages/backend
npm ci
```

Env file (`/etc/umay/backend.env`, `chmod 600`):

| Var | Required | Purpose |
|-----|----------|---------|
| `DATABASE_URL` | **yes** | `postgres://umay:<secret>@127.0.0.1:5432/umay`. If unset (or `USE_MEMORY_DB=true`), the server runs an **in-memory** repo — dev only, data not persisted. |
| `PORT` | no | Listen port (default **8080**). |
| `HOST` | no | Bind address (use `127.0.0.1`; the reverse proxy faces the world). |
| `NODE_ENV` | yes | `production`. |
| `REAL_AUTH` | **yes (prod)** | `1` turns on real Firebase user-token verification. Without it the server accepts a stub token — fine for dev, unsafe for prod. Needs a Firebase service account (see §5). |
| `ANTHROPIC_API_KEY` | for AI advisor | LLM-narrated advisories. Can instead be entered in the admin panel (see §6). |
| `CRY_API_URL` | for cry detector | Base URL of the cry-classifier (§7); unset ⇒ `/cry/analyze` returns 502/health-off. |
| `GOOGLE_MAPS_API_KEY` | for maps | Also settable via the admin panel (§6). |
| `CONTENT_API_KEY` | if locking `/content` | Guards the content-authoring API. |
| `APP_MIN_BUILD` / `APP_LATEST_BUILD` | no | Drives the app's force-update gate. |
| `REDIS_URL` | no | Enables Redis-backed features; omit to run without. |

systemd unit (`/etc/systemd/system/umay-backend.service`):
```ini
[Unit]
Description=Ana-Bala backend
After=network.target postgresql.service

[Service]
User=umay
WorkingDirectory=/opt/umay/packages/backend
EnvironmentFile=/etc/umay/backend.env
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```
`systemctl enable --now umay-backend`. **Restart it after any edit to the admin
or storefront HTML** — those are read at startup.

---

## 5. Auth posture

Two paths, and they became real at different times. `authPosture()` reports on
both, and the server refuses to start in production while either is a stub.

**Staff — real.** People sign in at `/admin` with a phone number and a password
and carry a session cookie (migration 019, `routes/staffLogin.ts`). Sessions
last 12 hours, failures are rate-limited per phone, and closing someone's access
deletes their sessions immediately. Create the first account with:

```bash
STAFF_PHONE=7071234567 STAFF_PASSWORD='…' node db/seed-staff.mjs
```

Re-running it with a new password is how a password is reset; it signs that
account's open sessions out. After the first account, staff are managed from the
panel under **Персонал** — the last enabled admin cannot be disabled or demoted,
by anyone, because there is no way back from that inside the product.

The `x-staff-id` / `x-staff-role` headers that preceded this are honoured **only**
with no `DATABASE_URL` or with `USE_MEMORY_DB=true` — i.e. local development.
Any deployment has Postgres, so they are worth nothing there.

The edge basic_auth this replaced is gone, along with `deploy/admin-access.sh`
which generated its credential. What remains at the edge is a per-IP rate limit
on `/admin/login`; the app counts failures per phone, so the two together cover
both one host trying many numbers and many hosts trying one.

**Users — still a stub.** `REAL_AUTH=1` plus a Firebase service account turns on
real token verification. Until then the backend accepts a stub token and the
`x-user-id` header, which is exactly why the edge allow-list does not include a
single app-API path. **Do not open them first** — see `docs/GO_LIVE_APP_API.md`
for the ordered procedure and the check that must return 401 before anything is
opened.

---

## 6. Admin-managed keys

At boot the backend bridges keys stored in `shop_settings` into `process.env`
**if the env var isn't already set** (`index.ts:73`): `ANTHROPIC_API_KEY` and
`GOOGLE_MAPS_API_KEY`. So the operator can enter them in the admin panel under
**Магазин → Настройки и ключи** (also WhatsApp number, Kaspi link, storefront
rating/reviews) instead of the env file. Restart the backend after saving so the
bridge re-runs.

---

## 7. Reverse proxy + TLS

Terminate TLS at nginx/Caddy and proxy to the backend on localhost. Caddy is the
shortest path to automatic HTTPS:

The live config is generated by `deploy/landing-takeover.sh`, not written by
hand — run that rather than editing the Caddyfile, so the allow-list and the
verification stay together. Its shape:

```
your-domain.kz {
    # The back office authenticates itself; the edge only rate-limits the login.
    handle /admin/login { rate_limit { zone admin_login { key {remote_host} events 12 window 5m } } 
                          reverse_proxy umay-backend:8080 }
    handle /admin*      { reverse_proxy umay-backend:8080 }

    # Deny by default. A new route is closed until it is named here, which is
    # the opposite of the deny-list this replaced — that one closed /admin and
    # left every app-API route open.
    @public path / /robots.txt /sitemap.xml /landing/* /shop /shop/* /health /ready /api-docs
    handle @public { reverse_proxy umay-backend:8080 }
    handle { respond "Not found" 404 }
}
```

> **The Caddyfile is bind-mounted, and a bind-mounted file follows the inode.**
> Anything that REPLACES it — `mv`, `cp -a`, an editor writing a new file —
> detaches the container, which then serves the old config forever while
> `caddy reload` and `caddy validate` both report success against the stale copy.
> Two deploys were verified this way and neither had been applied. Rewrite in
> place (`cat new > Caddyfile`); the script compares host and container
> checksums afterwards and refuses to claim a deploy if they differ.

Point the app's `API_BASE` and the storefront links at `https://your-domain.kz`.
`API_BASE` must have no path — see `data/http_transport.dart`.

---

## 8. Cry-classifier (optional feature)

The cry pipeline is code-complete but dark until a model exists.
1. **Train the model** (needs the Donate-a-Cry corpus):
   ```bash
   cd packages/cry-classifier
   python download_data.py && python train.py   # produces model.pkl
   ```
   `model.pkl` is intentionally not committed — mount it as a volume.
2. **Deploy** via `packages/cry-classifier/Dockerfile` / `docker-compose.yml`
   with the model mounted; confirm `GET /health` reports the model loaded.
3. **Wire it**: set `CRY_API_URL=http://<classifier-host>:8000` in the backend
   env (consumed at `index.ts` `forwardCry`), restart the backend.

Without steps 1–3, `/cry/analyze` returns 502 and the app shows its error
state; cry **history** still syncs (that path has no model dependency).

---

## 9. App build

> ### ⛔ `API_BASE=https://ana-bala.kz` does not work yet, on purpose
>
> The production edge serves an **allow-list**: `/`, `/landing/*`, `/shop/*`,
> `/health`, `/ready`. Every route the app needs — `/children`,
> `/appointments`, `/geofences`, `/devices`, `/vitals`, … — returns **404**.
>
> That is deliberate. `authUser` is a header stub until `REAL_AUTH=1` and a
> Firebase service account are configured (§5), so while the app routes are
> open anyone can read any family's data by typing a header:
>
> ```bash
> curl -H 'x-user-id: <any id>' https://ana-bala.kz/children   # was 200
> ```
>
> The backend's own boot guard refuses to start with `NODE_ENV=production` for
> exactly this reason. The edge allow-list is what lets it run at all.
>
> **The full procedure is `docs/GO_LIVE_APP_API.md`** — six ordered steps with
> the verification that must return 401 *before* the edge is opened, and a
> rollback for each. The short version: service account, `REAL_AUTH=1`, confirm
> the stub is dead, then open the allow-list, then build the app.
>
> Staff auth is no longer a stub — people sign in with a phone and a password
> (§5) — so `/admin*` is open at the edge and defended by the app itself.

Point the app at this backend and enable maps where wanted:
```bash
flutter build apk --release \
  --dart-define=API_BASE=https://your-domain.kz \
  --dart-define=MAPS_ENABLED=true
```
The default `API_BASE` is `http://localhost:8080` (unreachable from a device), so
the define is required for a real build.

---

## 10. Smoke test after deploy

This section is HTTP only. The database half — `npm run db:smoke`, including the
eight retention DELETEs — runs **before** the deploy, against a throwaway
Postgres, never against this box. See §3a.

`deploy/landing-takeover.sh` prints a verification block of its own after every
apply. This is the wider sweep — public surface, the app API staying shut, the
back office refusing anonymous callers, and the same routes answering once
signed in:

```bash
H=https://your-domain.kz
for p in / /robots.txt /sitemap.xml /health /ready /api-docs /admin /admin/ \
         /shop /shop/ /shop/og.png /shop/products /shop/config; do
  printf '%-28s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' $H$p)"
done                                    # 200, or 302 for the retired /shop pages

# Must stay shut until GO_LIVE_APP_API.md has been followed
curl -s -o /dev/null -w '%{http_code}\n' -H 'x-user-id: <any uuid>' $H/children   # 404

# Must refuse anonymous callers
curl -s -o /dev/null -w '%{http_code}\n' $H/admin/stats                            # 401

# And answer a real session
curl -s -c /tmp/c -o /dev/null -X POST -H 'content-type: application/json' \
     --data-raw '{"phone":"<staff phone>","password":"<password>"}' $H/admin/login
curl -s -o /dev/null -w '%{http_code}\n' -b /tmp/c $H/admin/stats                  # 200
```

Then open it in a browser and sign in. Two failures are invisible to curl:
- **The landing paints entirely from JavaScript**, so 200 does not mean it
  rendered. An unstyled pink page means an asset under `/landing/a/` is missing
  — rebuild it and restart the backend.
- **The back office can serve a working page you cannot use.** A sign-in card
  once sat painted on top of a fully loaded dashboard for two days, because a
  CSS `display` rule outranks the `hidden` attribute. Every request was a 200
  and every test passed. If sign-in appears to do nothing, check whether the
  panel is *behind* the card before assuming the login failed — and check the
  `staff_login_attempts` table, where a successful sign-in with no failures
  means the login was never the problem.

`/ready` returns 503 with a per-dependency breakdown when a dependency is down —
use it to confirm Postgres is reachable.

Two harnesses go further than curl can, against the real routes:

```bash
cd packages/backend
npx tsx tools/audit-panel.mts     # signs in, walks all 16 tabs, reports what drew
npx tsx tools/audit-landing.mts   # assets resolve, metadata, lead form, copy check
```

---

## 11. Backups & rollback

- **Nightly, installed.** `deploy/backup.sh --verify` runs from a systemd timer:
  `pg_dump -Fc` outside the Docker volume, 14 daily kept plus one a month
  forever, and the dump is restored into a scratch database and compared table
  by table.
- **Encrypted since 2026-08-20, and this needs a key before it will run.** The
  database itself is not encrypted at all — see `docs/SECURITY_FOLLOWUP.md` §8 —
  so a dump is a portable copy of every mother's health record and every child's
  location trail. `backup.sh` now encrypts each dump with `age` to the public key
  in `/etc/umay/backup-recipient.pub` and **refuses to run if that key is
  absent**, rather than falling back to plaintext. The private half lives on the
  owner's machine and never on the server, which is what makes a stolen disk or
  a leaked dump worth nothing — and also means the server cannot prove a restore
  works. Do the drill in §6 once, by hand, with the private key.
- Dumps taken before that date are still plaintext, including the monthly one
  that never rotates out. `backup.sh` counts them and prints the command that
  encrypts them in place.
- The drill **enumerates the live tables** rather than naming them, so a new
  table is covered the night it appears, and it refuses to report success when
  every table was empty on both sides. Before that it compared five hardcoded
  tables — one of which no longer existed — and three of the remaining four
  were empty, so "restore verified" rested on a single table with two rows.
- The drill runs BEFORE the encryption step, because verifying afterwards would
  need the private key, which is deliberately not on that machine.
- **These backups are on the machine they back up.** A dead host takes both.
  Choosing an offsite destination is an owner item and does not wait on
  anything else. Copying ciphertext offsite is safe in a way copying the old
  plaintext dumps was not.
- Deploy is `git pull` + restart; migrations are additive, so a code rollback
  does not require a schema rollback. The edge config rolls back with
  `bash deploy/landing-takeover.sh --revert`.
