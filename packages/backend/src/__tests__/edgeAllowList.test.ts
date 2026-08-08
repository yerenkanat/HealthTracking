/**
 * Every route the app calls must be reachable through Caddy.
 *
 * deploy/landing-takeover.sh ends in a catch-all `respond "Not found" 404`, so
 * a path missing from @app or @public is answered by the edge and never
 * reaches Fastify. From the app that looks like the server being down, and
 * nothing on the box shows it: the backend's own tests pass, its logs are
 * clean, and the route works perfectly over SSH on localhost.
 *
 * The allowlist is written by hand and the routes are not, so it drifts. It had
 * already drifted twice by the time this file was written — /metrics, the
 * vitals history chart, had never been allowed through at all.
 *
 * This reads both sides and compares them.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';

const here = dirname(fileURLToPath(import.meta.url));
const TAKEOVER = readFileSync(
  resolve(here, '../../../../deploy/landing-takeover.sh'), 'utf8');

/**
 * The path patterns from one `@name path a b c \` matcher, including its
 * backslash continuations.
 */
function matcherPaths(name: string): string[] {
  // Join backslash continuations FIRST, then find the matcher: the pattern
  // has to see one logical line, and an earlier version that tried to do both
  // at once matched only the first physical line and quietly reported six
  // paths out of twenty-five.
  const joined = TAKEOVER.replace(/\\\r?\n\s*/g, ' ');
  const m = joined.match(new RegExp(`@${name}\\s+path\\s+(.+)`));
  if (!m) return [];
  return m[1]
    .split(/\s+/)
    .map((s) => s.trim())
    .filter((s) => s.startsWith('/'));
}

/** Paths served by their own `handle /x* { ... }` block rather than a matcher. */
function handleBlockPaths(): string[] {
  return [...TAKEOVER.matchAll(/handle\s+(\/[^\s{]+)\s*\{/g)].map((m) => m[1]);
}

/** Does [pattern] (Caddy path syntax: exact, or a trailing *) cover [path]? */
function covers(pattern: string, path: string): boolean {
  if (pattern.endsWith('*')) return path.startsWith(pattern.slice(0, -1));
  return path === pattern;
}

/**
 * Reconstruct full paths from Fastify's printed route tree.
 *
 * The tree nests: a child line carries only the segment below its parent, so
 * `/appointments` is followed by an indented `/:id`. Two earlier attempts got
 * this wrong in opposite directions — reading the leaves alone produced sixty
 * phantom paths like `/accept`, and an onRoute hook added after buildServer
 * saw only sixteen of a hundred routes because the rest were registered before
 * the hook existed. Both PASSED, which is worse than either failing.
 */
export function pathsFromTree(tree: string): string[] {
  const out = new Set<string>();
  // Segment start → the prefix in force at that indent.
  const stack: Array<{ col: number; path: string }> = [];

  for (const raw of tree.split('\n')) {
    const m = raw.match(/^([^a-zA-Z/]*)(\S+)\s+\(([A-Z, ]+)\)\s*$/);
    if (!m) continue;
    const col = m[1].length;
    let seg = m[2];

    while (stack.length && stack[stack.length - 1].col >= col) stack.pop();
    const parent = stack.length ? stack[stack.length - 1].path : '';
    // A child segment may or may not lead with '/'; the tree prints both.
    if (parent && !seg.startsWith('/')) seg = `/${seg}`;
    const full = (parent + seg).replace(/\/{2,}/g, '/');
    stack.push({ col, path: full });

    const methods = m[3];
    if (methods.split(',').every((x) => ['HEAD', 'OPTIONS'].includes(x.trim()))) continue;
    out.add(full.length > 1 ? full.replace(/\/$/, '') : '/');
  }
  return [...out];
}

/** Every route the server actually registers, with its FULL path. */
async function registeredPaths(): Promise<string[]> {
  const app = buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => null,
    },
    { logger: false },
  );
  await app.ready();
  const tree = app.printRoutes({ commonPrefix: false });
  await app.close();
  return pathsFromTree(tree);
}

/**
 * Routes that are deliberately NOT reachable from the internet.
 *
 * /admin* is served on its own hostname with its own block; the ingest and
 * staff paths are covered by their own handles or are internal.
 */
const NOT_PUBLIC = [/^\/admin/, /^\/api\/v1/];

describe('the Caddy allowlist covers what the server serves', () => {
  it('found both sides — this file is worthless if either stops parsing', async () => {
    expect(matcherPaths('app').length).toBeGreaterThan(15);
    expect(matcherPaths('public').length).toBeGreaterThan(5);
    expect(handleBlockPaths().length).toBeGreaterThan(0);
    expect(TAKEOVER).toContain('respond "Not found" 404');

    // The route side too, and this assertion is the important one: both
    // earlier versions of this file PASSED while reading almost nothing, which
    // is the only way a test like this can be actively harmful.
    const routes = await registeredPaths();
    expect(routes.length, 'the route tree stopped parsing').toBeGreaterThan(80);
    // And it really is full paths, not leaf segments.
    expect(routes).toContain('/children/:id/day');
    expect(routes).toContain('/family/invites/accept');
  });

  it('rebuilds nested paths from the printed tree', () => {
    // The parser, on a fixture — so a Fastify upgrade that changes the drawing
    // is caught here rather than by the sweep silently going quiet.
    const paths = pathsFromTree([
      '├── /appointments (GET, HEAD, POST)',
      '│   ├── /extract (POST)',
      '│   └── /:id (DELETE)',
      '├── /health (HEAD)',
      '└── /family/ (GET)',
      '    └── access (GET)',
    ].join('\n'));
    expect(paths).toContain('/appointments');
    expect(paths).toContain('/appointments/extract');
    expect(paths).toContain('/appointments/:id');
    expect(paths).toContain('/family/access');
    // HEAD-only is not a route the app calls.
    expect(paths).not.toContain('/health');
  });

  it('every app-facing route is allowed through', async () => {
    const allowed = [
      ...matcherPaths('app'),
      ...matcherPaths('public'),
      ...handleBlockPaths(),
    ];
    const missing = (await registeredPaths())
      .filter((p) => !NOT_PUBLIC.some((re) => re.test(p)))
      // Parameterised segments stand in for any value; the allowlist is
      // prefix-based, so the prefix is what matters.
      .filter((p) => !allowed.some((a) => covers(a, p)))
      .sort();

    expect(
      missing,
      `these routes answer Caddy's 404 in production, and the app reads that ` +
        `as the server being down: ${missing.join(', ')}. Add them to @app ` +
        `(session-scoped) or @public in deploy/landing-takeover.sh.`,
    ).toEqual([]);
  });

  it('the family routes and the invitation page are through', async () => {
    // Named explicitly: the sweep above would also pass if somebody deleted
    // the routes, and these two are the ones this session added.
    const allowed = [...matcherPaths('app'), ...matcherPaths('public')];
    expect(allowed.some((a) => covers(a, '/family/access'))).toBe(true);
    expect(allowed.some((a) => covers(a, '/join/abc'))).toBe(true);
  });

  it('keeps the back office off the public hostname', async () => {
    // The panel has its own host block with its own guard; letting /admin
    // through here would put it on ana-bala.kz unauthenticated.
    const allowed = [...matcherPaths('app'), ...matcherPaths('public')];
    expect(allowed.some((a) => covers(a, '/admin'))).toBe(false);
  });
});
