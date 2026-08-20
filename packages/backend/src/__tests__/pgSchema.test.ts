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
import { readFileSync, readdirSync, existsSync } from 'node:fs';
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
 * missing tables. Kept narrow — a name only counts when `AS (` is followed by a
 * statement keyword, so a genuinely misspelled table still fails.
 *
 * INSERT/UPDATE/DELETE are in that list as well as SELECT because a
 * data-modifying CTE is a real CTE: `, up AS (INSERT … RETURNING 1)` is how
 * vaccination_overrides writes its row and its history entry in ONE statement,
 * which is the only way frame 15b's log cannot drift from the rows it describes.
 */
function cteNames(): Set<string> {
  const out = new Set<string>();
  for (const m of repo.matchAll(/\bwith\s+([a-z_][a-z0-9_]*)\s+as\s*\(/gi)) out.add(m[1].toLowerCase());
  for (const m of repo.matchAll(/,\s*([a-z_][a-z0-9_]*)\s+as\s*\(\s*(?:select|insert|update|delete)\b/gi)) {
    out.add(m[1].toLowerCase());
  }
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

  // EXTRACT(YEAR FROM age(...)) is not a read of a table called "age".
  //
  // The FROM inside EXTRACT is part of its syntax, not a clause, and the sweep
  // below cannot tell the two apart. Stripped rather than added to the noise
  // list, because "age" IS a plausible table name and silencing the word would
  // hide a real missing table the day somebody creates one.
  const sql = repo.replace(/\bextract\s*\(\s*[a-z_]+\s+from\b/gi, 'extract(');

  const patterns = [
    /\bfrom\s+([a-z_][a-z0-9_]*)/gi,
    /\bjoin\s+([a-z_][a-z0-9_]*)/gi,
    /\binsert\s+into\s+([a-z_][a-z0-9_]*)/gi,
    /\bupdate\s+([a-z_][a-z0-9_]*)\s+set\b/gi,
    /\bdelete\s+from\s+([a-z_][a-z0-9_]*)/gi,
  ];
  for (const re of patterns) {
    for (const m of sql.matchAll(re)) out.add(m[1].toLowerCase());
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

  it('EVERY migration that creates an index has it in schema.sql too', () => {
    // schema.sql builds a fresh database; db/migrations/ brings an existing one
    // to the same state. They are two files that must describe one index set,
    // which is exactly the pair that silently diverges — an index added to only
    // one of them means either fresh installs or upgraded installs run without
    // it, and nothing fails loudly enough to notice.
    //
    // This read migration 001 alone, and 001 is the file NAMED for indexes — so
    // the one that actually drifted was 023, which creates
    // shop_orders_phone_normalized while doing something else entirely. Every
    // MIGRATED server had that index; a FRESH install matched an order to an
    // account by scanning the whole table. Nothing here looked at file 023.
    //
    // The sibling checks in this file compare tables and columns; the auditor
    // diffed every CREATE TABLE and every ALTER TABLE … ADD COLUMN across all
    // 49 migrations and found no other divergence, so indexes were the last
    // unguarded kind. They are guarded now, for every file in the folder.
    const stripComments = (sql: string) => sql
      .replace(/\/\*[\s\S]*?\*\//g, ' ')
      .replace(/^\s*--.*$/gm, ' '); // comments name indexes that are deliberately absent

    // UNIQUE and CONCURRENTLY are matched as well as the plain form: an index
    // this regex fails to see is an index the check silently stops guarding,
    // which is the exact failure mode that let 023 through for 26 migrations.
    const created = (sql: string) =>
      [...sql.matchAll(/create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)/gi)]
        .map((m) => m[1].toLowerCase());
    const dropped = (sql: string) =>
      [...sql.matchAll(/drop\s+index\s+(?:concurrently\s+)?(?:if\s+exists\s+)?([a-z_][a-z0-9_]*)/gi)]
        .map((m) => m[1].toLowerCase());

    const files = readdirSync(`${root}db/migrations`)
      .filter((f) => f.endsWith('.sql'))
      .sort(); // apply order, which is what decides whether a drop undoes a create

    // Guards the guard: a folder read that silently returned nothing would let
    // every assertion below pass while checking not one index.
    expect(files.length, 'no migrations were read — the folder scan broke').toBeGreaterThan(20);

    /** index name -> the migration that creates it, minus anything later dropped. */
    const wanted = new Map<string, string>();
    for (const f of files) {
      const sql = stripComments(readFileSync(`${root}db/migrations/${f}`, 'utf8'));
      // A migration may drop an index it or an earlier one created (a rebuild).
      // Dropping wins: an index the migrations have REMOVED must not be
      // demanded of schema.sql, or the fix for a bad index would be to weaken
      // this test.
      for (const n of created(sql)) if (!wanted.has(n)) wanted.set(n, f);
      for (const n of dropped(sql)) wanted.delete(n);
    }

    expect(wanted.size, 'the CREATE INDEX regex matched nothing').toBeGreaterThan(30);
    // 001 is the file named for indexes. If the sweep ever stops seeing it, the
    // check has quietly regressed to something narrower than it replaced.
    expect([...wanted.values()]).toContain('001_performance_indexes.sql');

    const inSchema = new Set(created(stripComments(schema)));
    const missing = [...wanted].filter(([n]) => !inSchema.has(n)).map(([n, f]) => `${n} (${f})`);
    expect(missing, `created by a migration and absent from schema.sql, so a fresh ` +
      `install runs without it: ${missing.join(', ')}`).toEqual([]);
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

  it('every qualified SELECT column (alias.col) exists in the aliased table', () => {
    // The gap the INSERT/UPDATE sweep above admits it leaves open, and the one
    // that cost the product its revoke button: familyMembers SELECTed
    // `u.phone` from `users u`. The column is phone_e164, so the query threw on
    // every real Postgres; the route caught it into an empty list, screen 40
    // showed no relatives, and there was no id to revoke anybody with.
    //
    // A qualified reference is NOT ambiguous: `u.x` where the query says
    // `FROM users u` is a claim about one named table, checkable here. Each SQL
    // literal is examined on its own so the same letter may alias different
    // tables in different queries.
    const cols = tableColumns();
    const KEYWORDS = new Set([
      'on', 'where', 'order', 'group', 'having', 'limit', 'offset', 'using',
      'left', 'right', 'inner', 'outer', 'full', 'cross', 'natural', 'join',
      'set', 'and', 'or', 'lateral', 'values', 'returning', 'union', 'for',
      'window', 'as', 'select', 'from', 'do', 'nothing', 'update', 'conflict',
    ]);
    const problems: string[] = [];
    let literals = 0;

    for (const lit of repo.match(/`[\s\S]*?`/g) ?? []) {
      const sql = lit.slice(1, -1);
      if (!/\b(from|join)\s/i.test(sql)) continue;
      literals++;
      const alias = new Map<string, string>();
      for (const m of sql.matchAll(/\b(?:from|join)\s+([a-z_][a-z0-9_]*)\s+(?:as\s+)?([a-z_][a-z0-9_]*)/gi)) {
        const table = m[1].toLowerCase();
        const a = m[2].toLowerCase();
        if (KEYWORDS.has(a) || !cols.has(table)) continue;
        alias.set(a, table);
      }
      if (!alias.size) continue;
      for (const m of sql.matchAll(/\b([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\b/gi)) {
        const table = alias.get(m[1].toLowerCase());
        if (!table) continue;
        if (!cols.get(table)!.has(m[2].toLowerCase())) {
          problems.push(`${m[1]}.${m[2]} — no such column in ${table}`);
        }
      }
    }

    // Guards the guard: an extraction that matched nothing would pass silently.
    expect(literals, 'no SQL literals were parsed — the extraction broke').toBeGreaterThan(20);
    expect(problems, `qualified column not in schema: ${problems.join(', ')}`).toEqual([]);
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
    //
    // Scanned inside `export interface Repository { … }` ONLY. Reading the
    // whole file, every two-space-indented `name(` counted — so the first
    // top-level helper function to contain a plain `for (` or `if (` made the
    // check demand that pgRepository implement a method called `for`, and the
    // fix would have looked like contorting the source to please a regex.
    // Other interfaces in the file are not Repository's contract either.
    const iface = readFileSync(`${root}src/db/repository.ts`, 'utf8');
    const start = iface.indexOf('export interface Repository {');
    expect(start, 'the Repository interface was not found').toBeGreaterThan(-1);
    // Ends at the first line that closes a block at column 0 — the interface's
    // own `}`. Nested braces inside it are always indented.
    const rest = iface.slice(start);
    const end = rest.search(/\n\}/);
    const body = end === -1 ? rest : rest.slice(0, end);

    const declared = [...body.matchAll(/^\s{2}([a-zA-Z][a-zA-Z0-9]*)\s*(?:<[^>]*>)?\s*\(/gm)]
      .map((m) => m[1]);

    // Guards the guard: an extraction that matched nothing would pass silently,
    // which is the most comfortable way to ship an unimplemented method.
    expect(declared.length,
      `parsed ${declared.length} interface methods — the extraction broke`)
      .toBeGreaterThan(50);
    expect(declared).toContain('shopProducts');
    expect(declared).not.toContain('for');

    const missing = declared.filter(
      (m) => !new RegExp(`\\basync ${m}\\s*\\(|\\b${m}\\s*:\\s*async`).test(repo),
    );
    expect(missing, `pgRepository is missing: ${missing.join(', ')}`).toEqual([]);
  });

  it('every migration lives where the runner will actually find it', () => {
    // db/apply.mjs plans from db/migrations/ and nowhere else. Two migrations
    // (032, 033) were written into packages/backend/migrations/ — a directory
    // that looks right, sits next to the code, and is read by nothing.
    //
    // The deploy reported success. The columns were never created. In
    // production that is GET /alerts returning 500 for everybody, the SOS
    // outcome unable to save, and the admin catalogue 500ing on open — while
    // «История дня» renders as though no SOS ever happened, because the route
    // catches the error and falls back to an empty list.
    //
    // Nothing caught it: this file compares the repository against schema.sql,
    // and schema.sql was correct. The gap was between the migration folder and
    // the runner, which no test looked at.
    const runner = readFileSync(`${root}db/apply.mjs`, 'utf8');
    expect(runner, 'apply.mjs no longer plans from db/migrations — update this test')
      .toContain("join(here, 'migrations')");

    // The directory not existing is the CORRECT state and must pass, not throw
    // — a guard that crashes when the thing it guards against is absent is a
    // guard somebody deletes.
    const stray = existsSync(`${root}migrations`)
      ? readdirSync(`${root}migrations`, { withFileTypes: true })
          .filter((e) => e.isFile() && e.name.endsWith('.sql'))
          .map((e) => e.name)
      : [];
    expect(
      stray,
      `these .sql files sit in packages/backend/migrations/, which the runner ` +
      `never reads — move them to db/migrations/: ${stray.join(', ')}`,
    ).toEqual([]);
  });

  it('schema.sql can be run top to bottom — no table references one declared later', () => {
    // Postgres has no forward references: `REFERENCES staff_accounts(id)` in a
    // CREATE TABLE forty tables above CREATE TABLE staff_accounts aborts the
    // whole file with «relation "staff_accounts" does not exist».
    //
    // shop_product_photos did exactly that. Migration 044 could write the
    // reference inline because on a LIVE server migration 019 had created
    // staff_accounts long before — so every migrated server was fine, and
    // `node db/apply.mjs` against an EMPTY database failed on step 1. No fresh
    // install could be built at all, and nothing noticed, because nothing in
    // this suite ever built one. It was found by trying to run db/smoke.ts.
    //
    // Forward-referencing a table is legal Postgres when the constraint is
    // added afterwards with ALTER TABLE, which is what the fix does; this guard
    // therefore looks only at inline REFERENCES inside CREATE TABLE bodies.
    const created = new Map<string, number>();
    for (const m of schema.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)/gi)) {
      const name = m[1].toLowerCase();
      if (!created.has(name)) created.set(name, m.index ?? 0);
    }

    const bodies = /create\s+table\s+(?:if\s+not\s+exists\s+)?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\n\s*\);/gi;
    const late: string[] = [];
    for (const m of schema.matchAll(bodies)) {
      const table = m[1].toLowerCase();
      const bodyStart = (m.index ?? 0);
      // Comments carry prose like "REFERENCES the order" — strip them first.
      const body = m[2].replace(/--.*$/gm, ' ');
      for (const r of body.matchAll(/\breferences\s+([a-z_][a-z0-9_]*)/gi)) {
        const target = r[1].toLowerCase();
        if (target === table) continue;            // self-reference is fine
        const declaredAt = created.get(target);
        if (declaredAt === undefined) { late.push(`${table} -> ${target} (never created)`); continue; }
        if (declaredAt > bodyStart) late.push(`${table} -> ${target} (created later in the file)`);
      }
    }

    // Guards the guard: an extraction that matched nothing would pass silently.
    expect(created.size, 'parsed no CREATE TABLE at all — the extraction broke').toBeGreaterThan(50);
    expect(
      late,
      `schema.sql references a table before it exists, so a FRESH database ` +
      `cannot be built from it: ${late.join('; ')}`,
    ).toEqual([]);
  });

  it('the schema names no source module that is not on disk', () => {
    // The durable half of a two-year lie.
    //
    // db/schema.sql's privacy block said health columns were "stored under
    // application-layer envelope encryption (see backend/src/crypto). DB stores
    // ciphertext." There is no backend/src/crypto and there never was. Nothing
    // failed, because a comment cannot fail — and the sentence did the one
    // thing a false comment does best: it stopped the next reviewer looking, so
    // every mother's blood pressure and every child's allergy list sat in
    // plaintext columns with a note above them saying otherwise.
    //
    // Every `backend/src/...` or `src/...` path the schema mentions must
    // resolve to a real file or directory. A comment that points somewhere is a
    // claim about this repository, and claims are checkable.
    const referenced = new Set<string>();
    for (const m of schema.matchAll(/\b(?:backend\/)?src\/[A-Za-z0-9_./-]+/g)) {
      // Trailing punctuation from prose: "see backend/src/crypto)." etc.
      referenced.add(m[0].replace(/[.,;:)]+$/, ''));
    }

    // Guards the guard: if the sweep matched nothing, this test would pass
    // while the schema said anything it liked. The privacy block is expected to
    // cite the modules that DO the protecting.
    expect(referenced.size, 'the schema cites no src/ path at all — either the ' +
      'sweep broke or the privacy block stopped naming where the controls live')
      .toBeGreaterThan(0);

    const missing = [...referenced].filter((rel) => {
      const p = rel.startsWith('backend/') ? rel.slice('backend/'.length) : rel;
      // Written without an extension in prose; a module may be either.
      return !['', '.ts', '.tsx', '.js', '.mjs'].some((ext) => existsSync(`${root}${p}${ext}`));
    });

    expect(
      missing,
      `db/schema.sql points at source that does not exist: ${missing.join(', ')}. ` +
      `A privacy comment naming a module nobody wrote reads as a control that ` +
      `is in place. Either write the module or correct the comment — and the ` +
      `comment is the one that moves.`,
    ).toEqual([]);
  });

  it('the schema does not claim health data is encrypted while it is plaintext', () => {
    // The narrower claim, checked against the columns themselves rather than
    // against a filename. bp_calibration.*_offset was named as ciphertext while
    // declared REAL NOT NULL; pregnancy_health_metrics, location_history,
    // children and child_emergency are plaintext too.
    //
    // This is not a ban on the word "encryption" — the file must be free to
    // describe what IS encrypted (the nightly dump) and what would be needed to
    // encrypt these columns. It is a ban on the present tense: on saying the
    // database stores ciphertext for columns that Postgres is holding in the
    // clear. When that stops being true, this test is the thing to change, in
    // the same commit as the crypto.
    const claims = [
      /DB stores ciphertext/i,
      /stored\s+under\s+application-layer\s+envelope\s+encryption/i,
      /(?:columns?|fields?|offsets?)\s+are\s+encrypted\s+at\s+rest/i,
    ];
    const found = claims.filter((re) => re.test(schema)).map(String);
    expect(
      found,
      `db/schema.sql claims these columns are encrypted. They are not: ` +
      `bp_calibration.systolic_offset is REAL NOT NULL, and there is no cipher ` +
      `anywhere in packages/backend/src. See docs/SECURITY_FOLLOWUP.md §8.`,
    ).toEqual([]);

    // And the columns really are declared in the clear, so the check above is
    // guarding a live situation rather than a historical one.
    expect(schema).toMatch(/systolic_offset\s+REAL\s+NOT\s+NULL/i);
  });
});
