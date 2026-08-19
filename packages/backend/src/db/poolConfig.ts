/**
 * The Postgres pool's bounds — and what happens when they are reached.
 *
 * The pool was constructed as `new Pool({ connectionString })` with no other
 * options, so it ran on node-postgres's defaults. Nine of those are fine. One
 * is not: `connectionTimeoutMillis` defaults to **0, meaning wait forever**.
 *
 * WHAT THAT LOOKS LIKE IN PRODUCTION. One slow query holds a connection. The
 * other nine fill behind it. Every subsequent request then waits, without a
 * deadline, for a slot that is not coming. The process does not crash and
 * nothing is logged — the server simply stops answering, which is
 * indistinguishable from a network fault and is the single hardest failure to
 * diagnose from the outside. `/health` hangs too, so the uptime check reports
 * an outage with no cause.
 *
 * This is NOT a capacity change. `max` stays at ten, the effective default. The
 * ceiling was never the problem; what happened at the ceiling was.
 *
 * MIGRATIONS ARE UNAFFECTED. `packages/backend/db/apply.mjs:45` builds its own
 * pool in its own process, so `statementTimeoutMs` cannot interrupt a long
 * `CREATE INDEX` during a deploy. That was checked before choosing the number
 * rather than assumed.
 */

/** Concurrent connections. Ten is node-postgres's default, made visible. */
export const MAX_CONNECTIONS = 10;

/** How long an unused connection is kept. node-postgres's default, made visible. */
export const IDLE_TIMEOUT_MS = 10_000;

/**
 * How long a request waits for a connection before failing.
 *
 * Was 0 — for ever. Ten seconds is chosen so that the answer is an error rather
 * than a hang: a request that has already waited ten seconds for a *connection*
 * has failed from the mother's point of view whatever happens next, and an
 * error she can retry beats a spinner that never resolves.
 */
export const CONNECTION_TIMEOUT_MS = 10_000;

/**
 * Server-side ceiling on a single statement.
 *
 * Deliberately generous. `/admin/bi` computes its metrics with aggregates over
 * whole tables (`pgRepository.ts:1611-1630`), and a report that gets slower as
 * the product succeeds must not start failing because of a number chosen here.
 * Sixty seconds catches a runaway or a lock wait while leaving every legitimate
 * query far inside it.
 *
 * If a real query ever exceeds this, the fix is the query or an index — not a
 * larger ceiling. Raising it silently is how the bound stops meaning anything.
 */
export const STATEMENT_TIMEOUT_MS = 60_000;

/**
 * A transaction that opens, goes idle and never commits holds its connection
 * out of the pool for ever, which reaches pool exhaustion by a second road that
 * `statement_timeout` does not cover — no statement is running.
 */
export const IDLE_IN_TRANSACTION_TIMEOUT_MS = 60_000;

/** The options passed to `new Pool`, in one place so a test can read them. */
export function poolOptions(connectionString: string | undefined) {
  return {
    connectionString,
    max: MAX_CONNECTIONS,
    idleTimeoutMillis: IDLE_TIMEOUT_MS,
    connectionTimeoutMillis: CONNECTION_TIMEOUT_MS,
    statement_timeout: STATEMENT_TIMEOUT_MS,
    idle_in_transaction_session_timeout: IDLE_IN_TRANSACTION_TIMEOUT_MS,
  };
}
