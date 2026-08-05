/**
 * Read the back-office routes out of their source file.
 *
 * Shared by the audit-coverage and authorization guards. Both need the same
 * "what routes exist, and what does each handler body contain" view, and two
 * copies of this parser would be two definitions of which routes exist — the
 * kind of drift that lets a route be checked by one guard and not the other.
 *
 * Not named *.test.ts on purpose: vitest collects only test/spec files, so this
 * is a helper rather than an empty suite.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

export interface AdminRoute {
  method: string;
  path: string;
  /** Source from this route's registration up to the next one. */
  body: string;
  key: string;
}

/**
 * Every file that registers something under /admin.
 *
 * Started as admin.ts alone, which quietly turned both guards off for anything
 * registered elsewhere: the staff-management routes landed in their own file
 * and were invisible to the rule whose entire point is to fail a NEW route by
 * default. A route is not exempt from being audited or authorized because of
 * which file it lives in.
 *
 * staffLogin.ts is here too. Its three routes are the ones that must NOT
 * require a session — they are how you get one — and the authorization guard
 * names them explicitly rather than never seeing them.
 */
/**
 * Every file in routes/, discovered rather than listed.
 *
 * This was a hardcoded array, and it went stale three times in one week —
 * staffAdmin.ts, inventory.ts and entitlements.ts each added routes that were
 * invisible to the guard whose entire purpose is to fail a NEW route by
 * default. Each time the fix was to append one more path, which is the same
 * mistake with a longer list.
 *
 * A directory read cannot go stale. A new routes file is covered the moment it
 * exists, which is the only version of this that actually holds.
 */
const ROUTES_DIR = fileURLToPath(new URL('../../routes', import.meta.url));
const SOURCES = readdirSync(ROUTES_DIR)
  .filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'))
  .sort()
  .map((f) => join(ROUTES_DIR, f));

const src = SOURCES.flatMap((abs) => readFileSync(abs, 'utf8').split('\n'));

export function adminRoutes(): AdminRoute[] {
  const starts: Array<{ i: number; method: string; path: string }> = [];
  src.forEach((line, i) => {
    const m = line.match(/app\.(get|put|post|delete|patch)\('(\/admin[^']*)'/);
    if (m) starts.push({ i, method: m[1].toUpperCase(), path: m[2] });
  });
  return starts.map((s, n) => ({
    method: s.method,
    path: s.path,
    key: `${s.method} ${s.path}`,
    body: src.slice(s.i, n + 1 < starts.length ? starts[n + 1].i : src.length).join('\n'),
  }));
}

export const adminSource = (): string => src.join('\n');
