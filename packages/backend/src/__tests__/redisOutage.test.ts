/**
 * What actually happens when Redis is unreachable.
 *
 * index.ts states, next to checkReady, that "Redis failure degrades to the DB
 * path rather than taking the service down, so it is not gated here" — and on
 * that basis readiness deliberately does not check Redis. So the box reports
 * itself healthy while Redis is down, and every path below is expected to keep
 * working.
 *
 * The cache is not the system of record for any of them: a location fix is
 * written to Postgres on the same request, and geofence state only debounces
 * an alert that Postgres records anyway. Nothing here needs Redis to answer
 * correctly — only to answer fast.
 *
 * The production box is in exactly this state now: REDIS_URL is unset, so
 * ioredis dials 127.0.0.1:6379 and the log fills with ECONNREFUSED.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEMO_CHILD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { withInProcessFallback } from '../geofence/inProcessTransitions';

let repo: Repository;
let inserted: number;

/** ioredis once `maxRetriesPerRequest` is exhausted: the command rejects. */
const DOWN = () => Promise.reject(new Error('connect ECONNREFUSED 127.0.0.1:6379'));

beforeEach(() => {
  const base = createMemoryRepository();
  inserted = 0;
  // Count the durable writes; there is no read-back for locations.
  repo = {
    ...base,
    insertLocation: async (fix) => {
      inserted++;
      return base.insertLocation(fix);
    },
  };
});

function appWithRedisDown(): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        // The Redis-backed deps as index.ts wires them: the raw cache write,
        // and the transition resolver behind the same fallback the composition
        // root uses. Passing a bare DOWN here would test a deployment that does
        // not exist.
        cacheLocation: DOWN,
        resolveTransition: withInProcessFallback(DOWN),
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: DOWN,
      setBpCalibration: DOWN,
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'admin' as const }),
    },
    { logger: false },
  );
}

const FIX = {
  items: [
    {
      type: 'location',
      payload: {
        childId: DEMO_CHILD,
        source: 'gps',
        observedAt: '2026-08-03T10:00:00.000Z',
        coords: { lat: 43.238949, lng: 76.889709, accuracyM: 12 },
      },
    },
  ],
};

describe('the service survives Redis being unreachable', () => {
  it('still accepts a location fix', async () => {
    // The tracker uploads on a schedule and drops what the server refuses, so a
    // 500 here loses the child's position for that interval — because a *cache*
    // was down. DEMO_CHILD also has a geofence, so this exercises
    // resolveTransition too, not just cacheLocation.
    const res = await appWithRedisDown().inject({
      method: 'POST', url: '/ingest/batch', payload: FIX,
    });
    expect(res.statusCode).toBe(200);
  });

  it('counts the fix as accepted rather than rejected', async () => {
    // The batcher resends whatever the server rejects. Reporting a cached-
    // write failure as a rejected item means the tracker retries the same fix
    // forever while Redis is down — and location_history has no uniqueness
    // constraint to absorb it, unlike telemetry, so each retry is another row.
    const res = await appWithRedisDown().inject({
      method: 'POST', url: '/ingest/batch', payload: FIX,
    });
    const body = res.json() as { locationCount: number; rejected: number };
    expect(body.rejected).toBe(0);
    expect(body.locationCount).toBe(1);
  });

  it('still evaluates geofences, so a child leaving home is not missed', async () => {
    // DEMO_CHILD has a home fence, and this fix is far outside it. The alert
    // is the product. Losing it because a *cache* was unreachable is the
    // failure that matters most here — and it was silent: the request came
    // back 200 with the crossing simply never considered.
    const a = appWithRedisDown();
    const res = await a.inject({ method: 'POST', url: '/ingest/batch', payload: FIX });
    const body = res.json() as { geofenceEvents: unknown[] };
    expect(body.geofenceEvents.length).toBeGreaterThan(0);
  });

  it('still writes the fix to the database', async () => {
    // The durable half of the same request. Losing this means the location is
    // gone from history, not merely uncached.
    await appWithRedisDown().inject({ method: 'POST', url: '/ingest/batch', payload: FIX });
    expect(inserted).toBe(1);
  });

  it('still answers "where is my child" from the database', async () => {
    // The whole point of the service. With the cache down this used to throw
    // out of the handler and 500 — while /ready still said the box was
    // healthy, because readiness deliberately does not gate on Redis.
    const a = appWithRedisDown();
    await a.inject({ method: 'POST', url: '/ingest/batch', payload: FIX });

    const res = await a.inject({ method: 'GET', url: `/children/${DEMO_CHILD}/location` });
    expect(res.statusCode).toBe(200);
    // Not merely a non-500: the real coordinates come back.
    expect(res.json()).toMatchObject({
      childId: DEMO_CHILD,
      coords: { lat: 43.238949, lng: 76.889709 },
    });
  });

  it('still reports no location when there genuinely is none', async () => {
    // The fallback must not turn "nothing recorded" into something. A parent
    // seeing a stale or invented pin is worse than seeing none.
    const res = await appWithRedisDown().inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/location`,
    });
    expect(res.statusCode).toBe(404);
  });

  it('/ready keeps saying ready, which is only honest if the above hold', async () => {
    // These two facts are linked: readiness excludes Redis *because* the
    // service is supposed to work without it. If that ever stops being true,
    // the exclusion becomes a lie and an outage goes unnoticed.
    const res = await appWithRedisDown().inject({ method: 'GET', url: '/ready' });
    expect(res.statusCode).toBe(200);
  });
});
