# Running the backend against a real Postgres

By default the backend runs **in-memory** (`USE_MEMORY_DB`, or simply no
`DATABASE_URL`): data does not persist across restarts. To exercise the real
persistence path — `pgRepository`, sync that survives a restart, the admin panel
reading stored rows — point it at a Postgres.

## What the database must have

`schema.sql` requires these extensions, and **two of them are used at runtime, not
just for optimisation** — a plain Postgres will not run this app:

| Extension | Why |
|---|---|
| `postgis` | geofence zones are stored as `geography`; `pgRepository` reads them with `ST_MakePoint` / `ST_AsGeoJSON` / `ST_X` / `ST_Y`. **Runtime.** |
| `timescaledb` | `pregnancy_health_metrics` and `location_history` are hypertables, plus a continuous aggregate. |
| `uuid-ossp`, `pg_trgm` | id generation; substring search on the admin user list. |

## Option A — Docker (recommended, one command each)

The compose file uses `timescale/timescaledb-ha:pg16`, which bundles TimescaleDB
**and** PostGIS, on host port **5433** (so it never fights a stock Postgres on
5432).

```bash
cd packages/backend
npm run db:up                                                   # start the DB
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run db:apply   # schema + migrations
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run dev        # backend in pg mode
# npm run db:reset  — wipe and rebuild from scratch
```

## Option B — an existing Postgres

Any Postgres that has the extensions above works. A stock install (e.g. the
Windows PostgreSQL installer) does **not** ship TimescaleDB or PostGIS — add them
via StackBuilder / the platform package first, then:

```bash
DATABASE_URL=postgres://<user>:<pass>@<host>:<port>/<db> npm run db:apply
DATABASE_URL=... npm run dev
```

## The migration runner

`db/apply.mjs` applies `schema.sql` then `migrations/NNN_*.sql` in order, once
each, tracked in a `schema_migrations` table — idempotent, so re-running is a
no-op and an interrupted run resumes. It uses the `pg` driver already in
`dependencies`.
