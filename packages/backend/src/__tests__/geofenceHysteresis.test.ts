/**
 * The two guards on the geofence path — over HTTP, through the real ingest
 * handler, against the demo fence.
 *
 * Both were WRITTEN, documented at length, and never reached production.
 * geofencePipeline.ts applied an accuracy gate and a hysteresis buffer and had
 * no caller anywhere — not one, not even a test. The live path
 * (routes/ingestHandler.ts) meanwhile decided every crossing with a bare
 * `signedDistance <= 0` injected as `checkInside`, which buildServer Omitted
 * from its public deps, so production always got exactly that one.
 *
 * So the hole the dead file's own comment described as fixed was live the whole
 * time: "a child standing still at the edge of the school fence alternates
 * in/out, and every alternation reached a parent's phone as an alert."
 *
 * The demo fence is a 100 m circle, so bufferForFence gives 30 m: a fix between
 * 70 m and 130 m from the centre is inside the band and decides nothing.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEMO_CHILD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { decideTransition } from '../cache/redis';

const CENTRE = { lat: 43.238949, lng: 76.889709 };
/** Metres per degree of latitude here — good enough to place a test point. */
const M_PER_DEG_LAT = 111_132;

/** A point [d] metres due north of the fence centre. */
const northOf = (d: number) => ({ lat: CENTRE.lat + d / M_PER_DEG_LAT, lng: CENTRE.lng });

let app: FastifyInstance;
let repo: Repository;
/** Real IN/OUT state, so a flip is a flip — the debounce we are NOT testing. */
let state: Map<string, 'in' | 'out'>;

function makeApp() {
  repo = createMemoryRepository();
  state = new Map();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        // The REAL decision, over in-process state instead of Redis. Hand-
        // rolling it here got the first fix wrong — a hand-rolled fake also
        // suppressed a first-ever `enter`, which the real one emits — and a
        // fake that disagrees with production tests the fake.
        resolveTransition: async (childId, fenceId, inside) => {
          const key = `${childId}:${fenceId}`;
          const prev = state.get(key) ?? null;
          state.set(key, inside ? 'in' : 'out');
          return decideTransition(prev, inside);
        },
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => null,
    },
    { logger: false },
  );
}

/** One fix through the real route. Returns the crossings it emitted. */
async function fix(
  coords: { lat: number; lng: number },
  opts: { accuracyM?: number; at?: string } = {},
) {
  const r = await app.inject({
    method: 'POST',
    url: '/ingest/batch',
    payload: {
      items: [
        {
          type: 'location',
          payload: {
            childId: DEMO_CHILD,
            coords: opts.accuracyM == null ? coords : { ...coords, accuracyM: opts.accuracyM },
            source: 'gps',
            observedAt: opts.at ?? new Date().toISOString(),
          },
        },
      ],
    },
  });
  expect(r.statusCode).toBe(200);
  return r.json() as { geofenceEvents: Array<{ transition: string }>; locationCount: number };
}

beforeEach(() => { app = makeApp(); });

describe('a fix too vague to place decides nothing', () => {
  it('ignores a fix worse than the usable accuracy', async () => {
    // Indoors the platform falls back to cell towers and returns a position
    // good to hundreds of metres. Acting on it reports a child leaving school
    // from inside the classroom.
    const s = await fix(CENTRE, { accuracyM: 500 });
    expect(s.geofenceEvents).toEqual([]);
    await app.close();
  });

  it('still STORES the vague fix — it is only barred from deciding', async () => {
    // The map may show it, greyed. Dropping the position outright would leave
    // a parent with no last-known location at all.
    const s = await fix(CENTRE, { accuracyM: 500 });
    expect(s.locationCount).toBe(1);
    await app.close();
  });

  it('acts on a fix inside the usable accuracy', async () => {
    const s = await fix(CENTRE, { accuracyM: 20 });
    expect(s.geofenceEvents.map((e) => e.transition)).toEqual(['enter']);
    await app.close();
  });

  it('acts on a fix that reports no accuracy at all', async () => {
    // Unknown is not the same as bad. Refusing these would silence every
    // tracker that does not report accuracy — which is most cheap ones.
    const s = await fix(CENTRE);
    expect(s.geofenceEvents.map((e) => e.transition)).toEqual(['enter']);
    await app.close();
  });
});

describe('jitter at the boundary does not become an alert storm', () => {
  it('emits nothing while she stands at the edge', async () => {
    // Six fixes alternating two metres either side of a 100 m fence — a phone
    // sitting still at the gate. Every one of these is a state FLIP, so the
    // Redis debounce alone would have passed all six through: five alerts.
    await fix(northOf(0)); // establish: well inside
    const transitions: string[] = [];
    for (const d of [98, 102, 98, 102, 98, 102]) {
      const s = await fix(northOf(d));
      transitions.push(...s.geofenceEvents.map((e) => e.transition));
    }
    expect(transitions).toEqual([]);
    await app.close();
  });

  it('still reports a real departure', async () => {
    // The guard must not buy quiet by never alerting. Two hundred metres out
    // is a hundred metres clear of the fence and is not jitter.
    await fix(northOf(0));
    const s = await fix(northOf(200));
    expect(s.geofenceEvents.map((e) => e.transition)).toEqual(['exit']);
    await app.close();
  });

  it('still reports a real return', async () => {
    await fix(northOf(0));
    await fix(northOf(200));
    const s = await fix(northOf(0));
    expect(s.geofenceEvents.map((e) => e.transition)).toEqual(['enter']);
    await app.close();
  });

  it('a walk out through the band alerts once, not once per fix', async () => {
    // What actually happens when a child leaves: a few fixes crossing the
    // boundary, then clear of it. Exactly one «вышла».
    await fix(northOf(0));
    const transitions: string[] = [];
    for (const d of [80, 95, 105, 120, 160, 220, 300]) {
      const s = await fix(northOf(d));
      transitions.push(...s.geofenceEvents.map((e) => e.transition));
    }
    expect(transitions).toEqual(['exit']);
    await app.close();
  });
});
