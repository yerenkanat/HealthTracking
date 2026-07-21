/**
 * Every back-office route that can reach a family's data must leave a trace.
 *
 * The audit call is written by hand in each handler, so forgetting one is free
 * and invisible: the route works, the data is served, and nothing records who
 * looked. That is how /admin/devices came to be unaudited while
 * /admin/users/:id/health was — the same names, reached a different way.
 *
 * This reads the routes out of the source rather than checking a list of them,
 * so a NEW route is failed by default. Adding one forces a decision: audit it,
 * or declare here why it does not need to be.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(
  fileURLToPath(new URL('../routes/admin.ts', import.meta.url)),
  'utf8',
).split('\n');

/**
 * Routes that serve ONLY aggregates — counts, rates, series — and name nobody.
 *
 * Deliberately short, and each entry has to be true of the response body, not
 * merely of its name. Auditing these would bury the entries that matter: the
 * dashboard polls them, so every refresh would write rows nobody will read,
 * and the log people actually search would fill with noise.
 */
const AGGREGATES_ONLY = new Set([
  'GET /admin/stats', // active users, devices online, alerts today — counts
  'GET /admin/analytics', // totals and content coverage
  'GET /admin/bi', // DAU/WAU/MAU, retention, engagement — all counts
  'GET /admin/content', // the published catalogue; about content, not people
  'GET /admin/audit', // the log itself; admin-only, and auditing reads of the
  // audit log makes the log describe mostly itself
]);

interface Route {
  method: string;
  path: string;
  body: string;
}

function routes(): Route[] {
  const starts: Array<{ i: number; method: string; path: string }> = [];
  src.forEach((line, i) => {
    const m = line.match(/app\.(get|put|post|delete|patch)\('(\/admin[^']*)'/);
    if (m) starts.push({ i, method: m[1].toUpperCase(), path: m[2] });
  });
  return starts.map((s, n) => ({
    method: s.method,
    path: s.path,
    body: src.slice(s.i, n + 1 < starts.length ? starts[n + 1].i : src.length).join('\n'),
  }));
}

describe('back-office audit coverage', () => {
  it('found the routes to check', () => {
    // Without this the checks below would pass vacuously if the regex ever
    // stopped matching — the failure mode of every source-reading guard.
    const found = routes();
    expect(found.length).toBeGreaterThan(8);
    expect(found.some((r) => r.path === '/admin/users/:id/health')).toBe(true);
  });

  it('every route that can reach a family is audited', () => {
    const unaudited = routes()
      .filter((r) => !r.body.includes('writeAudit'))
      .map((r) => `${r.method} ${r.path}`)
      .filter((k) => !AGGREGATES_ONLY.has(k));
    expect(
      unaudited,
      `these serve or change data and record nobody: ${unaudited.join(', ')}. ` +
        'Add repo.writeAudit, or add it to AGGREGATES_ONLY if it truly names nobody.',
    ).toEqual([]);
  });

  it('every write is audited, with no exemption available', () => {
    // A read that names nobody can reasonably go unrecorded. A write cannot:
    // it changes what every user sees, including what is offered for sale.
    const writes = routes().filter((r) => r.method !== 'GET');
    expect(writes.length).toBeGreaterThan(0);
    const silent = writes
      .filter((r) => !r.body.includes('writeAudit'))
      .map((r) => `${r.method} ${r.path}`);
    expect(silent, `unaudited writes: ${silent.join(', ')}`).toEqual([]);
  });

  it('the exemption list does not name routes that no longer exist', () => {
    // A stale exemption is an exemption nobody reviewed. If a route is renamed,
    // the old entry would sit here quietly excusing something that is gone —
    // and the renamed route would be caught, which is the point.
    const live = new Set(routes().map((r) => `${r.method} ${r.path}`));
    const stale = [...AGGREGATES_ONLY].filter((k) => !live.has(k));
    expect(stale, `AGGREGATES_ONLY names routes that do not exist: ${stale.join(', ')}`).toEqual([]);
  });

  it('audit actions are distinct per route', () => {
    // Two routes logging the same action makes the log ambiguous about what was
    // actually opened.
    const actions = [...src.join('\n').matchAll(/action:\s*'([a-z_]+)'/g)].map((m) => m[1]);
    expect(actions.length).toBeGreaterThan(5);
    expect(new Set(actions).size).toBe(actions.length);
  });
});
