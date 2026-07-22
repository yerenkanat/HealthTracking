/**
 * App version policy — the module reads the floor/latest from the environment
 * and the public route serves it. A too-old client must be able to learn it is
 * too old without authenticating.
 */
import { describe, it, expect, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import { appVersionInfo } from '../app/version';

const ORIGINAL = { min: process.env.APP_MIN_BUILD, latest: process.env.APP_LATEST_BUILD };
afterEach(() => {
  process.env.APP_MIN_BUILD = ORIGINAL.min;
  process.env.APP_LATEST_BUILD = ORIGINAL.latest;
});

describe('appVersionInfo', () => {
  it('defaults to an inert floor (blocks nobody)', () => {
    delete process.env.APP_MIN_BUILD;
    delete process.env.APP_LATEST_BUILD;
    const info = appVersionInfo();
    expect(info.minBuild).toBe(0);
    expect(info.latestBuild).toBe(1);
  });

  it('reads a raised floor from the environment', () => {
    process.env.APP_MIN_BUILD = '7';
    process.env.APP_LATEST_BUILD = '9';
    const info = appVersionInfo();
    expect(info.minBuild).toBe(7);
    expect(info.latestBuild).toBe(9);
  });

  it('ignores a garbage value rather than blocking everyone', () => {
    process.env.APP_MIN_BUILD = 'not-a-number';
    expect(appVersionInfo().minBuild).toBe(0);
  });
});

function makeApp(): FastifyInstance {
  return buildServer(
    {
      repo: {} as Repository,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => null,
    },
    { logger: false },
  );
}

describe('GET /app/version', () => {
  it('is public and returns the policy', async () => {
    process.env.APP_MIN_BUILD = '3';
    process.env.APP_LATEST_BUILD = '5';
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/app/version' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.minBuild).toBe(3);
    expect(body.latestBuild).toBe(5);
    await app.close();
  });
});
