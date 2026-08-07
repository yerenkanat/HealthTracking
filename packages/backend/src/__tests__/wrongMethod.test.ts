/**
 * What a GET to a POST-only route answers.
 *
 * This exists because deploy/update.sh's `proxy` helper checks routes with a
 * plain `curl` GET and treats 404 as "Caddy swallowed it, the path is missing
 * from the allowlist". Two of its checks point at POST-only routes, so the
 * release would have failed on a healthy server with a message sending
 * somebody to edit the Caddyfile — a wrong diagnosis is worse than none.
 *
 * The distinction the deploy actually needs is not the STATUS but WHO
 * answered: Caddy's 404 is text/plain "Not found", Fastify's is JSON. This
 * pins the shape the deploy script now keys on.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

let app: FastifyInstance;

beforeEach(() => {
  app = buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => null,
    },
    { logger: false },
  );
});

describe('a wrong-method request is answered by US, not by the proxy', () => {
  it.each(['/devices/claim', '/auth/phone/start'])(
    'GET %s is a JSON 404 from Fastify',
    async (path) => {
      const res = await app.inject({ method: 'GET', url: path });
      expect(res.statusCode).toBe(404);
      // The marker the deploy script keys on. Caddy's 404 for a path missing
      // from the allowlist is text/plain "Not found" with no JSON at all.
      expect(res.headers['content-type']).toContain('application/json');
      expect(() => res.json()).not.toThrow();
      await app.close();
    },
  );

  it('and the same path DOES exist for its own method', async () => {
    // Otherwise the test above passes for a route that is genuinely missing,
    // which is the failure it is meant to tell apart.
    const res = await app.inject({ method: 'POST', url: '/devices/claim', payload: {} as never });
    expect(res.statusCode).not.toBe(404);
    await app.close();
  });
});
