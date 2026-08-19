/**
 * The Postgres pool has bounds, and the composition root actually uses them.
 *
 * The defect this guards is not a wrong number — it is an ABSENT one.
 * `new Pool({ connectionString })` inherits node-postgres's
 * `connectionTimeoutMillis: 0`, which means a request waits for a connection
 * for ever. The server then stops answering without crashing or logging, which
 * reads from outside exactly like a network fault.
 *
 * Two of these tests are about the values. The third is the one that matters:
 * asserting the constants alone would stay green while `index.ts` quietly went
 * back to constructing its own options object, which is precisely how this
 * config would be lost.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  poolOptions,
  CONNECTION_TIMEOUT_MS,
  STATEMENT_TIMEOUT_MS,
  MAX_CONNECTIONS,
} from '../db/poolConfig';

const root = fileURLToPath(new URL('../', import.meta.url));

describe('the Postgres pool is bounded', () => {
  it('never waits for a connection for ever', () => {
    const o = poolOptions('postgres://example/db');
    expect(o.connectionTimeoutMillis, 'a zero connection timeout means wait for ever')
      .toBeGreaterThan(0);
    expect(Number.isFinite(o.connectionTimeoutMillis)).toBe(true);
    expect(o.max, 'the pool has no ceiling').toBeGreaterThan(0);
    // Not a capacity change: ten is node-postgres's own default, made visible.
    expect(MAX_CONNECTIONS).toBe(10);
  });

  it('caps a statement, but generously enough for the BI aggregates', () => {
    // /admin/bi aggregates over whole tables. A ceiling tight enough to be
    // "safe" would start failing the report as the product succeeds, and the
    // fix for a slow query is the query or an index — never a smaller bound
    // quietly raised later.
    expect(STATEMENT_TIMEOUT_MS).toBeGreaterThanOrEqual(30_000);
    const o = poolOptions(undefined);
    expect(o.statement_timeout).toBe(STATEMENT_TIMEOUT_MS);
    // An idle-but-open transaction holds a connection with no statement
    // running, so statement_timeout cannot reach it.
    expect(o.idle_in_transaction_session_timeout).toBeGreaterThan(0);
  });

  it('is what index.ts actually constructs the pool with', () => {
    // The load-bearing assertion. Everything above would pass with poolConfig
    // exported, documented, tested — and called by nobody.
    const src = readFileSync(`${root}index.ts`, 'utf8');
    expect(src, 'index.ts builds its own pool options again, so poolConfig is dead code')
      .toMatch(/new Pool\(\s*poolOptions\(/);
    expect(src, 'index.ts constructs a Pool from a bare connection string')
      .not.toMatch(/new Pool\(\s*\{\s*connectionString/);
  });

  it('leaves migrations alone', () => {
    // apply.mjs runs in its own process with its own pool, so the statement
    // ceiling cannot interrupt a long CREATE INDEX mid-deploy. If that ever
    // changes, this fails and the ceiling has to be reconsidered.
    const apply = readFileSync(`${root}../db/apply.mjs`, 'utf8');
    expect(apply, 'the migration runner now shares the app pool, so '
      + 'STATEMENT_TIMEOUT_MS can abort a CREATE INDEX during a deploy')
      .not.toMatch(/poolOptions/);
    expect(CONNECTION_TIMEOUT_MS).toBeGreaterThan(0);
  });
});
