/**
 * Every back-office route must decide who is allowed to call it.
 *
 * The guard is written by hand at the top of each handler, so forgetting one is
 * free and silent: the route works, it returns real families' data, and it
 * answers anybody who can reach the port. Nothing failed when a route was
 * added without it — adminAudit.test.ts checks that routes RECORD who looked,
 * which is a different question from whether they should have been let in.
 *
 * All fourteen routes were in fact guarded when this was written. That is the
 * point: this file exists so the fifteenth cannot quietly not be, and so the
 * read/write split stays a rule rather than a habit.
 */

import { describe, it, expect } from 'vitest';
import { adminRoutes } from './helpers/adminRoutes.js';

/** requireStaff → any back-office account. requireAdmin → admins only. */
function guardOf(body: string): 'admin' | 'staff' | null {
  if (/requireAdmin\(/.test(body)) return 'admin';
  if (/requireStaff\(/.test(body)) return 'staff';
  return null;
}

/**
 * Reads that are admin-only because the response is a list of people rather
 * than one person a staff member is currently helping.
 */
const ADMIN_ONLY_READS = new Set([
  'GET /admin/users', // the whole user list, searchable by name and phone
  'GET /admin/audit', // who in the back office looked at whom
]);

/**
 * The three routes that cannot require a session, because they are how a
 * session is obtained, ended, or reported.
 *
 * Listed by name and nothing else: a route is exempt because it is one of
 * these, not because of a pattern in its path that a future route could
 * accidentally match. Each carries its own protection — the rate limit and the
 * constant-time comparison on login, the cookie on logout and me.
 */
const NO_SESSION_REQUIRED = new Set([
  'POST /admin/login',
  'POST /admin/logout',
  'GET /admin/me',
]);

/**
 * Writes that are deliberately not admin-only, with the reason each is safe.
 */
const NOT_ADMIN_ONLY_WRITES = new Set([
  // Your own password, verified against your current one. Making this
  // admin-only is how a team ends up sharing one password: nobody can rotate
  // their own without asking, so nobody does.
  'POST /admin/staff/me/password',
]);

describe('back-office authorization', () => {
  it('found the routes to check', () => {
    // Without this every check below passes vacuously the day the regex stops
    // matching — the failure mode of every source-reading guard.
    const found = adminRoutes();
    expect(found.length).toBeGreaterThan(8);
    expect(found.some((r) => r.path === '/admin/users/:id/health')).toBe(true);
  });

  it('no route is reachable without an identity', () => {
    const open = adminRoutes()
      .filter((r) => !NO_SESSION_REQUIRED.has(r.key))
      .filter((r) => guardOf(r.body) === null)
      .map((r) => r.key);
    expect(
      open,
      `these serve back-office data to anyone who can reach them: ${open.join(', ')}. ` +
        'Start the handler with requireStaff or requireAdmin.',
    ).toEqual([]);
  });

  it('every write requires an admin, not merely a signed-in staff member', () => {
    // A write changes what every user of the app sees — including which
    // products are put in front of a pregnant woman. Reading a record is part
    // of support; rewriting the catalogue is not.
    const weak = adminRoutes()
      .filter((r) => !NO_SESSION_REQUIRED.has(r.key) && !NOT_ADMIN_ONLY_WRITES.has(r.key))
      .filter((r) => r.method !== 'GET' && guardOf(r.body) !== 'admin')
      .map((r) => `${r.key} (${guardOf(r.body) ?? 'unguarded'})`);
    expect(weak, `writes not restricted to admins: ${weak.join(', ')}`).toEqual([]);
  });

  it('reads that list people are admin-only', () => {
    for (const key of ADMIN_ONLY_READS) {
      const route = adminRoutes().find((r) => r.key === key);
      expect(route, `${key} no longer exists — update ADMIN_ONLY_READS`).toBeDefined();
      expect(guardOf(route!.body), `${key} should be admin-only`).toBe('admin');
    }
  });

  it('the guard is the first thing each handler does', () => {
    // A check placed after the query has already run has still run the query.
    // Requiring it in the opening lines keeps "authorize, then act" visible at
    // a glance rather than buried in a branch.
    const late = adminRoutes()
      .filter((r) => {
        const guardLine = r.body.split('\n').findIndex((l) => /require(Staff|Admin)\(/.test(l));
        return guardLine > 3;
      })
      .map((r) => r.key);
    expect(late, `authorization happens too late in: ${late.join(', ')}`).toEqual([]);
  });

  it('a failed guard stops the handler', () => {
    // requireStaff/requireAdmin reply on failure and return null; the handler
    // has to bail on that. Without the early return the route replies twice —
    // and the second reply carries the data the first one refused.
    const missing = adminRoutes()
      .filter((r) => !NO_SESSION_REQUIRED.has(r.key))
      .filter((r) => !/if \(!s\) return;/.test(r.body))
      .map((r) => r.key);
    expect(
      missing,
      `these do not stop after a refused guard: ${missing.join(', ')}`,
    ).toEqual([]);
  });
});
