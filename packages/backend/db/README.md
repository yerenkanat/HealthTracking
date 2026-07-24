# Running the backend against a real Postgres

By default the backend runs **in-memory** (`USE_MEMORY_DB`, or simply no
`DATABASE_URL`): data does not persist across restarts. To exercise the real
persistence path — `pgRepository`, sync that survives a restart, the admin panel
reading stored rows — point it at a Postgres.

## What the database needs

Just standard contrib extensions, all bundled with any Postgres:

| Extension | Why |
|---|---|
| `uuid-ossp` | id generation (`uuid_generate_v4()`) |
| `pg_trgm` | substring search on the admin user list |
| `citext` | case-insensitive email uniqueness |

**No TimescaleDB or PostGIS.** They used to be required, but the app never used
either at query time (geofence math is done in TypeScript; the hypertables and
continuous aggregate were storage optimisation nothing read). The schema is now
plain PostgreSQL — so **any** local or managed Postgres works, and hosting has no
special requirement. See the portability note at the top of `schema.sql`.

## Option A — a local Postgres you already have

A stock PostgreSQL install works. Create a database and apply:

```bash
DATABASE_URL=postgres://<user>:<pass>@127.0.0.1:5432/<db> npm run db:apply
DATABASE_URL=... npm run dev            # backend in pg mode
DATABASE_URL=... npm run db:smoke       # optional: exercise pgRepository live
```

### A throwaway local cluster (no Docker, no touching your main install)

If you have the Postgres binaries but don't want to use your main cluster, spin up
a private one with `initdb` (trust auth, its own port):

```bash
PGBIN="/c/Program Files/PostgreSQL/16/bin"      # adjust for your install
DATA="$LOCALAPPDATA/umay-localpg/pgdata"
"$PGBIN/initdb" -D "$DATA" -U umay --auth-local=trust --auth-host=trust -E UTF8
"$PGBIN/pg_ctl" -D "$DATA" -o "-p 5433" -l "$DATA/../pg.log" start
"$PGBIN/psql" -U umay -h 127.0.0.1 -p 5433 -d postgres -c "CREATE DATABASE umay;"
DATABASE_URL=postgres://umay@127.0.0.1:5433/umay npm run db:apply
# stop later:  "$PGBIN/pg_ctl" -D "$DATA" stop
```

## Option B — Docker

`docker-compose.yml` runs a stock `postgres:16` on host port **5433** (so it never
fights a 5432 install):

```bash
npm run db:up
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run db:apply
DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay npm run dev
# npm run db:reset  — wipe and rebuild
```

## The migration runner

`db/apply.mjs` applies `schema.sql` then `migrations/NNN_*.sql` in order, once
each, tracked in a `schema_migrations` table — idempotent, so re-running is a
no-op and an interrupted run resumes. `node db/apply.mjs --plan` prints the plan
without a DB. Uses the `pg` driver already in `dependencies`.

> Note: full server operation also uses Redis (location + BP-calibration cache).
> Without it, the server still starts and pg-backed routes work; only those cache
> paths degrade. Add a Redis (or `docker compose` one) for the complete stack.
