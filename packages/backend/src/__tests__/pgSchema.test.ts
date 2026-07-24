/**
 * Does the pg repository only touch tables and columns that exist?
 *
 * The whole app runs on the in-memory repository in development, so nothing
 * here is exercised until it meets a real Postgres — and then it fails in
 * production, on one endpoint, at whatever hour someone first opens it.
 *
 * This is not a substitute for running against a real database. It is the part
 * that can be checked without one, and it already found adminUserDetail
 * querying `day_logs` when the table is `cycle_day_logs` — every other query in
 * the file had the name right.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const schema = readFileSync(`${root}db/schema.sql`, 'utf8');

/**
 * Comments are stripped before the sweep. Prose contains SQL-shaped phrases —
 * "the user row exists from signup" made `signup` look like a table — and the
 * alternative, adding each to a noise list, would mask a real table of that
 * name the day someone adds one.
 */
const repo = readFileSync(`${root}src/db/pgRepository.ts`, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/^\s*\/\/.*$/gm, ' ');

/** Table names the schema creates. */
function definedTables(): Set<string> {
  const out = new Set<string>();
  for (const m of schema.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)/gi)) {
    out.add(m[1].toLowerCase());
  }
  return out;
}

/**
 * table -> its column names, parsed from each CREATE TABLE body. A line is a
 * column definition when it starts with an identifier that isn't a table
 * constraint keyword (PRIMARY / FOREIGN / CONSTRAINT / CHECK / UNIQUE).
 */
function tableColumns(): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>();
  const re = /create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\n\s*\);/gi;
  for (const m of schema.matchAll(re)) {
    const cols = new Set<string>();
    for (const raw of m[2].split('\n')) {
      const line = raw.trim();
      const c = line.match(/^([a-z_][a-z0-9_]*)\s/i);
      if (c && !/^(primary|foreign|constraint|check|unique)\b/i.test(line)) cols.add(c[1].toLowerCase());
    }
    out.set(m[1].toLowerCase(), cols);
  }
  return out;
}

/**
 * Names bound by a WITH clause, which are queryable but not tables.
 *
 * Matches the CTE head `WITH x AS (` and each `, y AS (` that follows, so a
 * query that defines its own intermediate relations does not read as three
 * missing tables. Kept narrow — only names introduced by `AS (` count, so a
 * genuinely misspelled table still fails.
 */
function cteNames(): Set<string> {
  const out = new Set<string>();
  for (const m of repo.matchAll(/\bwith\s+([a-z_][a-z0-9_]*)\s+as\s*\(/gi)) out.add(m[1].toLowerCase());
  for (const m of repo.matchAll(/,\s*([a-z_][a-z0-9_]*)\s+as\s*\(\s*select/gi)) out.add(m[1].toLowerCase());
  return out;
}

/**
 * Table names the repository reads or writes.
 *
 * Only the clauses where a table name can appear. UPDATE is deliberately
 * excluded from a bare-word sweep because `UPDATE x SET` would otherwise make
 * "set" look like a table.
 */
function referencedTables(): Set<string> {
  const out = new Set<string>();
  const patterns = [
    /\bfrom\s+([a-z_][a-z0-9_]*)/gi,
    /\bjoin\s+([a-z_][a-z0-9_]*)/gi,
    /\binsert\s+into\s+([a-z_][a-z0-9_]*)/gi,
    /\bupdate\s+([a-z_][a-z0-9_]*)\s+set\b/gi,
    /\bdelete\s+from\s+([a-z_][a-z0-9_]*)/gi,
  ];
  for (const re of patterns) {
    for (const m of repo.matchAll(re)) out.add(m[1].toLowerCase());
  }
  // Subquery aliases and SQL keywords that survive the sweep.
  for (const noise of ['select', 'lateral', 'unnest', 'values', 'only']) out.delete(noise);
  return out;
}

describe('pgRepository against db/schema.sql', () => {
  it('queries only tables the schema creates', () => {
    const defined = definedTables();
    const ctes = cteNames();
    const missing = [...referencedTables()].filter((t) => !defined.has(t) && !ctes.has(t));
    expect(missing, `no such table in schema.sql: ${missing.join(', ')}`).toEqual([]);
  });

  it('the CTE exemption does not swallow real tables', () => {
    // The exemption above is the only way a name can pass without existing in
    // the schema, so it has to stay narrow: if it ever matched a real table
    // name, a typo in a query against that table would go unreported.
    const defined = definedTables();
    const overlap = [...cteNames()].filter((n) => defined.has(n));
    expect(overlap, `CTE names shadow real tables: ${overlap.join(', ')}`).toEqual([]);
  });

  it('the schema actually defines the tables this test relies on', () => {
    // Guards the guard: if the extraction regex silently matched nothing, the
    // check above would pass vacuously and prove exactly nothing.
    const defined = definedTables();
    expect(defined.size).toBeGreaterThan(10);
    for (const core of ['users', 'children', 'geofences', 'timeline_content', 'cycle_day_logs']) {
      expect(defined.has(core), `schema.sql should define ${core}`).toBe(true);
    }
  });

  it('the repository actually references tables', () => {
    // Same reasoning in the other direction: an empty reference set would make
    // the first test pass no matter what the repository said.
    expect(referencedTables().size).toBeGreaterThan(5);
  });

  it('the index migration and schema.sql do not drift apart', () => {
    // schema.sql builds a fresh database; db/migrations/ brings an existing one
    // to the same state. They are two files that must describe one index set,
    // which is exactly the pair that silently diverges — a new index added to
    // only one of them means either fresh installs or upgraded installs run
    // without it, and nothing fails loudly enough to notice.
    const migration = readFileSync(`${root}db/migrations/001_performance_indexes.sql`, 'utf8')
      .replace(/^\s*--.*$/gm, ' '); // comments name indexes that are deliberately absent
    const names = (sql: string) =>
      new Set([...sql.matchAll(/create\s+index\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)/gi)]
        .map((m) => m[1].toLowerCase()));

    const inMigration = names(migration);
    expect(inMigration.size).toBeGreaterThan(3); // the regex actually matched
    const missingFromSchema = [...inMigration].filter((n) => !names(schema).has(n));
    expect(missingFromSchema, `in the migration but not schema.sql: ${missingFromSchema.join(', ')}`)
      .toEqual([]);
  });

  it('the hot filter columns the repository queries by are indexed', () => {
    // Each of these is a `WHERE <col> = $1` (or a range/sort on it) that runs on
    // a user-facing path, against a table that grows without bound. They were
    // picked by reading the queries, not guessed — see the migration for what
    // each one serves, and for the list of filters deliberately left to a
    // composite PRIMARY KEY or UNIQUE constraint.
    const indexed = schema.toLowerCase();
    for (const [what, needle] of [
      ['zones by child', 'idx_geofences_child'],
      ['the cross-user emergency feed', 'idx_phm_emergency'],
      ['the cross-user alert feed', 'idx_safety_alerts_at'],
      ['dead push tokens, deleted by token', 'idx_push_tokens_token'],
      ['admin user search (unanchored ILIKE)', 'idx_users_name_trgm'],
    ] as const) {
      expect(indexed.includes(needle), `schema.sql should index ${what} (${needle})`).toBe(true);
    }
    // The trigram indexes are useless without the extension that provides the
    // operator class, and CREATE INDEX would fail outright at build time.
    expect(indexed).toContain('create extension if not exists pg_trgm');
  });

  it('every INSERT / UPDATE column the repository writes exists in that table', () => {
    // The table-name sweep above catches a wrong TABLE; it can't catch a wrong
    // COLUMN. adminUserDetail SELECTed a bare `phone` when the column is
    // phone_e164 — the whole detail card threw on real Postgres while every
    // in-memory test passed. SELECT columns are ambiguous to parse (aliases,
    // joins, functions), but INSERT column lists and `col = $n` assignments are
    // unambiguous and single-table, so those we CAN verify without a live DB.
    const cols = tableColumns();
    const problems: string[] = [];

    // INSERT INTO <table> (a, b, c) — the first paren group is the column list.
    for (const m of repo.matchAll(/insert\s+into\s+([a-z_][a-z0-9_]*)\s*\(([^)]+)\)/gi)) {
      const table = m[1].toLowerCase();
      const known = cols.get(table);
      if (!known) continue; // unknown table is the other test's job
      for (const col of m[2].split(',').map((c) => c.trim().toLowerCase()).filter(Boolean)) {
        if (!known.has(col)) problems.push(`INSERT ${table}.${col}`);
      }
    }

    // UPDATE <table> SET ... — the `col = $n` assignments (skips COALESCE(...)
    // forms, which is fine: a false miss, never a false alarm).
    for (const m of repo.matchAll(/update\s+([a-z_][a-z0-9_]*)\s+set\s+([\s\S]*?)\s+where/gi)) {
      const table = m[1].toLowerCase();
      const known = cols.get(table);
      if (!known) continue;
      for (const a of m[2].matchAll(/([a-z_][a-z0-9_]*)\s*=\s*\$/gi)) {
        if (!known.has(a[1].toLowerCase())) problems.push(`UPDATE ${table}.${a[1]}`);
      }
    }

    expect(problems, `column not in schema: ${problems.join(', ')}`).toEqual([]);
  });

  it('the column parser actually found columns (guards the guard)', () => {
    const cols = tableColumns();
    expect(cols.get('users')?.has('phone_e164')).toBe(true);
    expect(cols.get('users')?.has('phone')).toBe(false); // the bug column must NOT exist
    expect(cols.get('med_doses')?.has('count')).toBe(true);
    expect((cols.get('children')?.size ?? 0)).toBeGreaterThan(3);
  });

  it('every repository method the interface declares is implemented', () => {
    // A method missing from the pg implementation is a runtime failure the
    // moment production reaches it, and TypeScript will not always catch it
    // through the object-literal-to-interface widening used here.
    const iface = readFileSync(`${root}src/db/repository.ts`, 'utf8');
    const declared = [...iface.matchAll(/^\s{2}([a-zA-Z][a-zA-Z0-9]*)\s*\(/gm)].map((m) => m[1]);
    const missing = declared.filter(
      (m) => !new RegExp(`\\basync ${m}\\s*\\(|\\b${m}\\s*:\\s*async`).test(repo),
    );
    expect(missing, `pgRepository is missing: ${missing.join(', ')}`).toEqual([]);
  });
});
