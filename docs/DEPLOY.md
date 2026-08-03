# Production deploy runbook

How to stand up the Umay backend (API + admin + storefront) on a fresh Linux
server, plus the optional cry-classifier service and the app build flags. Every
command and env var below is grounded in the code (`packages/backend/src/index.ts`,
`server.ts`, `db/schema.sql`); nothing here is executed automatically — review,
then run.

> **Status:** not yet deployed. The target box is recorded outside the repo.
> Deploy only after the security step below.

---

## Concrete setup — ana-bala.kz (fresh box, full stack)

Decided config for this deploy. Ready-to-use files live in [`deploy/`](../deploy/):

| Public name | Serves | Notes |
|---|---|---|
| `ana-bala.kz`, `www.ana-bala.kz` | Landing page (`/`), storefront (`/shop…`) **and** the app API | The Flutter app builds with `API_BASE=https://ana-bala.kz`. Root `/` is the Ana-Bala landing page — no redirect. |
| `admin.ana-bala.kz` | Staff back-office (`/admin/ui` + `/admin/*`) | Basic-auth gated at the edge (no staff RBAC yet). Root `/` → `/admin/ui`. |

One Node process on `127.0.0.1:8080` serves all of it; **Caddy** terminates TLS
(auto Let's Encrypt) and routes both names to it.

**DNS to set first** (TLS won't issue until these resolve to the server):
```
ana-bala.kz         A     188.137.231.252
www.ana-bala.kz     A     188.137.231.252
admin.ana-bala.kz   A     188.137.231.252
```
(add matching `AAAA` records for the IPv6 address if you use it).

> ### ⚠ The target box is not empty
>
> As of **2026-08-03**, `188.137.231.252` is already serving a different, live
> application — *Aiti.kz — Қойма басқару жүйесі*, a warehouse-management SPA that
> answers 200 on every path of `ana-bala.kz`. The owner has authorised replacing
> it, but `bootstrap.sh` assumes a **fresh** box: it overwrites
> `/etc/caddy/Caddyfile` and takes ports 80/443, which stops that site dead.
>
> Take a copy you can put back **before** running anything:
> ```bash
> ssh root@188.137.231.252 'tar czf /root/preexisting-site-$(date +%F).tgz \
>     /etc/caddy /etc/nginx /var/www /etc/systemd/system/*.service 2>/dev/null; \
>   systemctl list-units --type=service --state=running > /root/preexisting-services.txt'
> ```
> Then confirm what that app is and where else it lives. Once Caddy is
> reconfigured and its service is stopped, the site is down until someone
> restores it.

**Files in `deploy/`:**
- `Caddyfile` — the two site blocks above (set the admin basic-auth hash).
- `umay-backend.service` — systemd unit (runs as the `umay` user, env from `/etc/umay/backend.env`).
- `backend.env.example` — the env matrix, ready to fill.
- `bootstrap.sh` — a reviewable fresh-box script that does §2–§7 below end to end.

**Blocked on you to run it:** SSH access (rotate the leaked root password, add my
key or share a fresh one securely) and the DNS records above. Then it's:
`REPO_URL=… DB_PASS=… ./deploy/bootstrap.sh` on the box, plus the manual steps it
prints (Firebase for `REAL_AUTH`, the admin hash, the app build).

The step-by-step sections below explain each piece the script automates.

---

## 0. Architecture

- **Backend** — one Node process (`packages/backend`, `tsx src/index.ts`). It
  serves the JSON API **and** the static pages: the landing page at `/`, admin
  at `/admin/ui`, the storefront at `/shop`, `/shop/watch`, `/shop/umay-watch`,
  `/shop/tracker`, and the API docs at `/docs/api`. Static HTML is read **once at
  startup**, so a content edit needs a process restart to show.
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
`schema.sql` creates every table (verified to build cleanly, 32 tables incl.
`cry_results`, `sleep_nights.source/manual_asleep_min`, `cycle_day_logs.note`).

**Upgrading an existing DB instead — apply migrations in order:**
```bash
for f in packages/backend/db/migrations/0*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```
Migrations `001`–`016` are each idempotent (`IF NOT EXISTS`). New since the last
deploy: **014** (sleep source/asleep-total), **015** (day-log note), **016**
(cry-results history). Note in `001`: on a live DB with real data, add
`CONCURRENTLY` to the index statements so they don't take an exclusive lock.

A fresh `schema.sql` box does **not** need the migrations (they'd no-op).

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
Description=Umay backend
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

`REAL_AUTH=1` + `initFirebaseAuth()` (a Firebase service account in the env)
turns on real verification of the **user** path. Caveat from the code
(`index.ts:334`): the **admin** path is a separate header stub with no real RBAC
verifier yet — keep `/admin/*` and `/admin/ui` behind the reverse proxy (IP
allow-list or basic-auth) until staff auth exists.

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

```
your-domain.kz {
    reverse_proxy 127.0.0.1:8080
    # optional: restrict the staff console
    @admin path /admin/ui /admin/*
    basicauth @admin { <user> <bcrypt-hash> }
}
```
Point the app's `API_BASE` and the storefront links at `https://your-domain.kz`.

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

```bash
curl -fsS https://your-domain.kz/health           # liveness → 200
curl -sS  https://your-domain.kz/ready            # readiness + per-dep status
curl -s -o /dev/null -w '%{http_code}\n' https://your-domain.kz/cry/results  # 401 (auth), not 500
open      https://your-domain.kz/                 # landing page renders (not a blank pink screen)
open      https://your-domain.kz/shop/umay-watch  # storefront renders
open      https://your-domain.kz/admin/ui         # admin loads (behind allow-list)
```
The landing page paints entirely from JavaScript, so "200 OK" does not mean it
rendered. Open it in a browser: an unstyled pink page means an asset under
`/landing/a/` is missing — rebuild it and restart the backend.
`/ready` returns 503 with a per-dependency breakdown when a dependency is down —
use it to confirm Postgres is reachable.

---

## 11. Backups & rollback

- Nightly `pg_dump` of the `umay` DB before each deploy; keep the last N.
- Deploy is `git pull` + `npm ci` + apply any **new** migrations + restart. To
  roll back code, check out the previous tag and restart; DB migrations are
  additive, so a code rollback does not require a schema rollback.
