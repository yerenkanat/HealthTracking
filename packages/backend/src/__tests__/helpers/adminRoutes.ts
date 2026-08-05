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

import { readFileSync } from 'node:fs';
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
const SOURCES = [
  '../../routes/admin.ts',
  '../../routes/staffAdmin.ts',
  '../../routes/staffLogin.ts',
  '../../routes/inventory.ts',
];

const src = SOURCES.flatMap((rel) =>
  readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8').split('\n'),
);

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
