/**
 * Every back-office route must decide who is allowed to call it.
 *
 * The guard is written by hand at the top of each handler, so forgetting one is
 * free and silent: the route works, it returns real families' data, and it
 * answers anybody who can reach the port. Nothing failed when a route was
 * added without it — adminAudit.test.ts checks that routes RECORD who looked,
 * which is a different question from whether they should have been let in.
 *
 * This reads the SOURCE, so it catches the route added tomorrow with no guard
 * at all. What each guard actually admits is checked over HTTP in
 * roleAccess.test.ts; neither file replaces the other.
 *
 * The rule this used to enforce was "writes are admin-only", and it was the
 * best available when `requireAdmin` was the only real check. It is now the
 * wrong rule: a warehouse hand booking a stock move is a write, and making it
 * admin-only is how a company ends up with one shared owner login. The rule is
 * now that every route names a CAPABILITY — with `requireStaff` alone allowed
 * only where the answer genuinely does not depend on the job.
 */

import { describe, it, expect } from 'vitest';
import { adminRoutes } from './helpers/adminRoutes.js';

/**
 * The capability a handler asks for, ANY for a route open to every signed-in
 * account, or null for no guard at all.
 *
 * ANY is a symbol rather than the string 'staff'. There IS a capability called
 * `staff` — managing colleagues — and spelling both the same made every route
 * guarded on it read as ungarded, which is exactly backwards for the two most
 * sensitive routes in the panel.
 */
const ANY = Symbol('any signed-in staff');

function guardOf(body: string): string | typeof ANY | null {
  const cap = body.match(/requireCap\(req, reply, '([a-z]+)'\)/);
  if (cap) return cap[1];
  if (/requireStaff\(/.test(body)) return ANY;
  return null;
}

/**
 * Routes that are open to any signed-in member of staff, with the reason each
 * is safe. Everything else must name a capability.
 *
 * The test is the list: adding a route here is a decision somebody has to make
 * on purpose, in a file whose diff says what it means.
 */
const ANY_STAFF = new Map<string, string>([
  // Static protocol tables — the antenatal schedule, the vaccination calendar.
  // Public health guidance, identical for every account, nobody's data.
  ['GET /admin/reference/:kind', 'reference data, the same for everyone'],
  // Counts for the header strip: how many users, how many alerts today. No row
  // identifies anybody, and every role's screen shows it.
  ['GET /admin/stats', 'aggregate counters, no personal data'],
  ['GET /admin/analytics', 'aggregates only'],
  ['GET /admin/bi', 'DAU/WAU/retention — aggregates only'],
  // Reading the catalogue. A seller quoting what a lesson covers needs it;
  // CHANGING it is `content`.
  ['GET /admin/content', 'the catalogue as published, read-only'],
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
 * Writes that deliberately name no capability, with the reason each is safe.
 */
const NO_CAPABILITY_WRITES = new Set([
  // Your own password, verified against your current one. Gating this is how a
  // team ends up sharing one password: nobody can rotate their own without
  // asking, so nobody does.
  'POST /admin/staff/me/password',
]);

/** Reads whose response is people, and the capability each must therefore hold. */
const SENSITIVE_READS = new Map<string, string>([
  ['GET /admin/users', 'customers'], // the whole user list, searchable by name and phone
  ['GET /admin/users/:id/health', 'health'],
  ['GET /admin/users/:id/wellness', 'health'],
  ['GET /admin/users/:id/detail', 'health'],
  ['GET /admin/children/stats', 'health'],
  ['GET /admin/safety', 'health'],
  ['GET /admin/devices', 'health'], // every row carries a guardian and a child by name
  ['GET /admin/audit', 'staff'], // who in the back office looked at whom
  ['GET /admin/dashboard', 'finance'], // revenue, margin, stock value
  ['GET /admin/settings', 'staff'], // the stored API keys are in this response
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
        'Start the handler with requireStaff or requireCap.',
    ).toEqual([]);
  });

  it('every route names the capability its job needs', () => {
    const weak = adminRoutes()
      .filter((r) => !NO_SESSION_REQUIRED.has(r.key) && !NO_CAPABILITY_WRITES.has(r.key))
      .filter((r) => guardOf(r.body) === ANY && !ANY_STAFF.has(r.key))
      .map((r) => r.key);
    expect(
      weak,
      'these are open to every signed-in account, including a warehouse hand: ' +
        `${weak.join(', ')}. Give each a requireCap, or add it to ANY_STAFF with a reason.`,
    ).toEqual([]);
  });

  it('the reads that return people hold the right capability', () => {
    for (const [key, cap] of SENSITIVE_READS) {
      const route = adminRoutes().find((r) => r.key === key);
      expect(route, `${key} no longer exists — update SENSITIVE_READS`).toBeDefined();
      expect(guardOf(route!.body), `${key} should require '${cap}'`).toBe(cap);
    }
  });

  it('the ANY_STAFF list has not gone stale', () => {
    // A route named here that has since been given a capability — or deleted —
    // leaves a permanent exemption for a route that no longer needs one, and
    // the next route to take that path inherits it silently.
    const routes = adminRoutes();
    for (const key of ANY_STAFF.keys()) {
      const route = routes.find((r) => r.key === key);
      expect(route, `${key} is exempted but no longer exists`).toBeDefined();
      expect(guardOf(route!.body), `${key} is exempted but now names a capability`).toBe(ANY);
    }
  });

  it('the guard is the first thing each handler does', () => {
    // A check placed after the query has already run has still run the query.
    // Requiring it in the opening lines keeps "authorize, then act" visible at
    // a glance rather than buried in a branch.
    const late = adminRoutes()
      // The three sessionless routes have no guard to be early or late, and
      // the last route in a file has a 'body' that runs to the end of the
      // concatenation — so /admin/me was picking up the next file's guard.
      .filter((r) => !NO_SESSION_REQUIRED.has(r.key))
      .filter((r) => {
        const guardLine = r.body.split('\n').findIndex((l) => /require(Staff|Cap|Admin)\(/.test(l));
        return guardLine > 3;
      })
      .map((r) => r.key);
    expect(late, `authorization happens too late in: ${late.join(', ')}`).toEqual([]);
  });

  it('a failed guard stops the handler', () => {
    // requireStaff/requireCap reply on failure and return null; the handler
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
