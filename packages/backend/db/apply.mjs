#!/usr/bin/env node
/**
 * Apply the schema and every migration to the database at $DATABASE_URL, in order,
 * exactly once each. Idempotent: a tracking table (`schema_migrations`) records what
 * has run, so re-running is a no-op and a half-finished run resumes cleanly.
 *
 *   DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay node db/apply.mjs
 *
 * Requires a Postgres with the extensions schema.sql declares (timescaledb, postgis,
 * uuid-ossp, pg_trgm). `docker compose up -d` in this package starts one that has
 * them; see db/README.md. The `pg` driver is already a backend dependency.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));

/** The ordered set of SQL steps: schema.sql first, then migrations/NNN_*.sql. */
function buildPlan() {
  const migDir = join(here, 'migrations');
  const migrations = readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort();
  return [
    { name: 'schema.sql', path: join(here, 'schema.sql') },
    ...migrations.map((f) => ({ name: `migrations/${f}`, path: join(migDir, f) })),
  ];
}

// --plan / DRY_RUN: print the ordered plan and exit, without a DB or DATABASE_URL.
// Lets the discovery + ordering be checked anywhere.
if (process.argv.includes('--plan') || process.env.DRY_RUN === '1') {
  const plan = buildPlan();
  console.log('Would apply, in order:');
  for (const [i, s] of plan.entries()) console.log(`  ${i + 1}. ${s.name}`);
  process.exit(0);
}

const { default: pg } = await import('pg');
const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL is not set. Example:\n  DATABASE_URL=postgres://umay:umay@127.0.0.1:5433/umay node db/apply.mjs');
  process.exit(2);
}

const pool = new pg.Pool({ connectionString: url });

/** Run one SQL file inside a transaction, recording it as applied. */
async function applyFile(name, sql) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [name]);
    await client.query('COMMIT');
    console.log(`  applied ${name}`);
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw new Error(`${name} failed: ${e.message}`);
  } finally {
    client.release();
  }
}

async function main() {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`);
  const done = new Set(
    (await pool.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name),
  );

  const plan = buildPlan();
  let ran = 0;
  for (const step of plan) {
    if (done.has(step.name)) continue;
    await applyFile(step.name, readFileSync(step.path, 'utf8'));
    ran++;
  }
  console.log(ran ? `\n✓ ${ran} step(s) applied.` : '\n✓ already up to date.');
  await pool.end();
}

main().catch((e) => {
  console.error('\n✗ migration failed:', e.message);
  process.exit(1);
});
