/**
 * Nothing in the local stack may be published to every interface.
 *
 * "5432:5432" looks like it means localhost and does not — Docker publishes on
 * 0.0.0.0. On a café, hotel or coworking network that made this Postgres
 * (password `fcs`) and this Redis (no password at all) reachable by anyone else
 * on it. The backend had already been bound to 127.0.0.1 for exactly that
 * reason; the two services it fronts had not.
 *
 * Checked here rather than left to review because the difference is one prefix
 * in a YAML string, and its absence looks like nothing.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const compose = readFileSync(
  fileURLToPath(new URL('../../../../infra/docker-compose.yml', import.meta.url)),
  'utf8',
);

/** Every published port mapping in the file, as written. */
function publishedPorts(): string[] {
  return [...compose.matchAll(/^\s*-\s*"([^"]+)"\s*$/gm)]
    .map((m) => m[1])
    // Volume mounts and command args also live in `- "..."` lists; a port
    // mapping is digits and colons only.
    .filter((s) => /^[\d.:]+$/.test(s));
}

describe('the local stack is not exposed to the network', () => {
  it('found the port mappings', () => {
    // Without this the check below would pass vacuously the moment the file's
    // formatting changed.
    expect(publishedPorts().length).toBeGreaterThanOrEqual(2);
  });

  it('every published port binds to loopback', () => {
    const exposed = publishedPorts().filter((p) => !p.startsWith('127.0.0.1:'));
    expect(
      exposed,
      `published on every interface: ${exposed.join(', ')}. ` +
        'Prefix with 127.0.0.1: — this stack has a guessable database password ' +
        'and a Redis with none.',
    ).toEqual([]);
  });

  it('still maps the ports the backend expects', () => {
    // Guards against "fixing" the exposure by deleting the mapping, which would
    // break every developer's stack instead.
    const ports = publishedPorts();
    expect(ports.some((p) => p.endsWith(':5432'))).toBe(true);
    expect(ports.some((p) => p.endsWith(':6379'))).toBe(true);
  });
});
