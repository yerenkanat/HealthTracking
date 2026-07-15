# Integration harness

Spins up the real dependencies and exercises the backend end-to-end. The pure
request-handling logic is already unit-tested (see `packages/backend`); this proves
the **wiring** — zod validation, Postgres/TimescaleDB/PostGIS writes, Redis
last-location cache + geofence de-duplication, and the AI emergency escalation.

## Run

```bash
# 1. Dependencies (Postgres+Timescale+PostGIS, Redis). Schema auto-applies on init.
docker compose -f infra/docker-compose.yml up -d

# 2. Seed fixtures (one mother/device/child, Home + School geofences).
docker compose -f infra/docker-compose.yml exec -T db psql -U fcs -d fcs < infra/seed.sql

# 3. Start the backend against those services.
cd packages/backend && npm install
DATABASE_URL=postgres://fcs:fcs@localhost:5432/fcs \
REDIS_URL=redis://localhost:6379 \
ANTHROPIC_API_KEY=sk-ant-... \
npm run dev

# 4. In another shell, run the smoke test.
node infra/integration_smoke.mjs
```

## What the smoke test asserts
- `/ingest/batch` stores telemetry, flags the preeclampsia-range reading as an
  emergency, and emits a **Home enter** geofence event.
- A repeated Home fix is **de-duplicated** (Redis state) — no second alert.
- Moving away emits a single **exit**.
- `/children/:id/location` returns the cached last fix.
- `/calibration/bp` computes and persists the cuff→PPG offsets.
- `/ai/chat` with a critical reading attached returns `SHOW_EMERGENCY_SCREEN`
  (the LLM is bypassed) — the same guarantee the unit tests cover, now over HTTP.

## Teardown
```bash
docker compose -f infra/docker-compose.yml down -v
```
