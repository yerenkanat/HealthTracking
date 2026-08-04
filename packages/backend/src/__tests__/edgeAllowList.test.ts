/**
 * The reverse proxy's allow-list has to name every path the public is meant to
 * reach.
 *
 * deploy/landing-takeover.sh puts Caddy in front of the backend with a
 * DENY-BY-DEFAULT rule: `@public path …` lists what is proxied and everything
 * else gets a 404 at the edge. That is deliberate — the app API is still on the
 * header-trusting auth stub, so it must not be reachable from the internet —
 * but it means a route can exist, be tested, be deployed, and still be missing
 * in production because the edge never forwards it.
 *
 * That is exactly what happened to /robots.txt and /sitemap.xml: written,
 * served by the backend, and 404 to every crawler.
 *
 * So this compares the two lists rather than trusting either. It reads the
 * shell script as text because that IS the deployed artefact.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const script = readFileSync(
  fileURLToPath(new URL('../../../../deploy/landing-takeover.sh', import.meta.url)),
  'utf8',
);

/** The `@public path …` line, as Caddy will see it. */
const allowList: string[] = (() => {
  const line = script.split('\n').find((l) => l.trim().startsWith('@public path '));
  if (!line) throw new Error('no @public matcher in landing-takeover.sh');
  return line.trim().replace('@public path ', '').split(/\s+/);
})();

/** Public paths the backend serves, and why each one has to be reachable. */
const MUST_BE_PUBLIC: Array<[string, string]> = [
  ['/', 'the landing page itself'],
  ['/robots.txt', 'every crawler requests it first; a 404 is its first impression'],
  ['/sitemap.xml', 'named by robots.txt, so a 404 here contradicts what we just told the crawler'],
  ['/health', 'liveness'],
  ['/ready', 'readiness'],
];

/** Paths that must NOT be reachable while staff auth is the header stub. */
const MUST_NOT_BE_PUBLIC = ['/admin', '/admin/settings', '/children', '/ingest/batch', '/profile'];

/** Does the Caddy matcher cover this exact path? `/landing/*` covers prefixes. */
function covered(path: string): boolean {
  return allowList.some((p) => (p.endsWith('*') ? path.startsWith(p.slice(0, -1)) : p === path));
}

describe('the edge allow-list matches what the backend serves', () => {
  it.each(MUST_BE_PUBLIC)('lets the public reach %s — %s', (path) => {
    expect(covered(path), `${path} is missing from the @public matcher, so the edge 404s it`).toBe(true);
  });

  it.each(MUST_NOT_BE_PUBLIC)('does not expose %s', (path) => {
    // The app API trusts x-user-id and the admin API trusts x-staff-role, so
    // the edge is the only thing standing between those and the internet. A
    // wildcard added carelessly here would open them silently.
    expect(covered(path), `${path} would be reachable from the internet`).toBe(false);
  });

  it('keeps the deny-by-default handler', () => {
    // An allow-list only means anything while the fall-through refuses. If the
    // final `handle` ever starts proxying, every assertion above becomes
    // decoration.
    expect(script).toMatch(/handle\s*\{[^}]*(respond|abort|error)/);
  });
});
