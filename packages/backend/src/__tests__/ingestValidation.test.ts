/**
 * What the ingest edge accepts into the health record.
 *
 * /calibration/bp bounds every number it takes, with a comment saying why:
 * unbounded integers let a typo or a hostile client write an offset that
 * silently distorts every later blood-pressure reading. The telemetry schema
 * sitting directly above it in the same file bounded nothing at all — and
 * telemetry is the path that actually reaches her chart, her clinician's view,
 * and the server-side triage that sends an emergency push.
 *
 * The reasoning was already written down. It just was not applied to the
 * bigger door.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { InjectPayload, Response as InjectResponse } from 'light-my-request';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';

const USER = '11111111-1111-1111-1111-111111111111';
const CHILD = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const DEVICE = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

let app: FastifyInstance;
let healthRows: Array<Record<string, unknown>>;
let locations: Array<Record<string, unknown>>;
let emergencyPushes: number;

function build() {
  healthRows = [];
  locations = [];
  emergencyPushes = 0;

  const repo = {
    insertHealthMetric: async (m: Record<string, unknown>) => void healthRows.push(m),
    insertLocation: async (f: Record<string, unknown>) => void locations.push(f),
    deviceOwner: async (id: string) => (id === DEVICE ? { userId: USER } : null),
    childOwner: async (id: string) => (id === CHILD ? { userId: USER } : null),
    loadGeofences: async () => [],
    insertGeofenceEvent: async () => {},
  } as unknown as Repository;

  return buildServer({
    repo,
    guardrail: { callLLM: async () => 'ok' },
    ingest: {
      cacheLocation: async () => {},
      resolveTransition: async () => null,
      sendEmergencyPush: async () => void emergencyPushes++,
      sendGeofencePush: async () => {},
    },
    cacheLastLocation: async () => null,
    setBpCalibration: async () => {},
    authUser: async () => ({ userId: USER }),
    authAdmin: async () => null,
  } as never);
}

const post = (url: string, payload: InjectPayload): Promise<InjectResponse> =>
  app.inject({ method: 'POST', url, payload });

const telemetry = (extra: Record<string, unknown>) => ({
  items: [
    {
      type: 'telemetry',
      payload: { deviceId: DEVICE, recordedAt: '2026-07-21T08:00:00.000Z', ...extra },
    },
  ],
});
const location = (coords: Record<string, unknown>) => ({
  items: [
    {
      type: 'location',
      payload: { childId: CHILD, coords, source: 'gps', observedAt: '2026-07-21T08:00:00.000Z' },
    },
  ],
});

beforeEach(async () => {
  app = build();
  await app.ready();
});
afterEach(async () => {
  await app.close();
});

describe('vitals outside the range a body can produce', () => {
  // ONE field per case. The first version of this test sent an impossible
  // systolic AND an impossible diastolic together, so it passed with the
  // systolic bound removed — the diastolic bound was carrying it. A test that
  // trips several guards at once cannot tell you which one is missing.
  it.each([
    ['systolic', { systolicMmHg: 999999 }],
    ['diastolic', { diastolicMmHg: 900 }],
    ['heart rate', { heartRateBpm: 100000 }],
    ['oxygen saturation', { spo2Pct: 140 }],
    ['core temperature', { coreTempC: 200 }],
    ['skin temperature', { skinTempC: 90 }],
  ])('refuses an impossible %s', async (_name, field) => {
    const r = await post('/ingest/batch', telemetry(field));
    expect(r.statusCode).toBe(400);
    expect(healthRows).toHaveLength(0);
  });

  it.each([
    ['systolic', { systolicMmHg: -50 }],
    ['diastolic', { diastolicMmHg: -1 }],
    ['heart rate', { heartRateBpm: -1 }],
    ['oxygen saturation', { spo2Pct: 0 }],
    ['core temperature', { coreTempC: -40 }],
  ])('refuses a negative or zero %s', async (_name, field) => {
    const r = await post('/ingest/batch', telemetry(field));
    expect(r.statusCode).toBe(400);
    expect(healthRows).toHaveLength(0);
  });

  it('does not send an emergency push for a number no person has ever had', async () => {
    // The consequence that makes this more than tidiness: 999999 clears the
    // emergency threshold, so the server told her to seek care now because of
    // a value that came from a bug or an attacker.
    const r = await post('/ingest/batch', telemetry({ systolicMmHg: 999999 }));
    expect(r.statusCode).toBe(400);
    expect(emergencyPushes).toBe(0);
  });

  it('still accepts a reading that is alarming but real', async () => {
    // The bounds exist to reject the impossible, not to sand off emergencies.
    // Pre-eclamptic pressures must pass and must still raise the alarm.
    const r = await post('/ingest/batch', telemetry({ systolicMmHg: 175, diastolicMmHg: 118 }));
    expect(r.statusCode).toBe(200);
    expect(healthRows).toHaveLength(1);
    expect(emergencyPushes).toBe(1);
  });

  it('accepts the edges of what a body can do', async () => {
    const r = await post(
      '/ingest/batch',
      telemetry({ systolicMmHg: 260, diastolicMmHg: 200, heartRateBpm: 220, spo2Pct: 100, coreTempC: 42 }),
    );
    expect(r.statusCode).toBe(200);
  });
});

describe('coordinates that are not on Earth', () => {
  it('refuses a latitude past the pole', async () => {
    const r = await post('/ingest/batch', location({ lat: 5000, lng: 76.9 }));
    expect(r.statusCode).toBe(400);
    expect(locations).toHaveLength(0);
  });

  it('refuses an infinite coordinate', async () => {
    // Reachable over the wire: JSON.parse('1e999') is Infinity, and a bare
    // z.number() accepts it. It would then flow into the geofence distance
    // maths, where every comparison against it is false — so a child sitting
    // at "Infinity" is inside no zone and leaving none either.
    const r = await app.inject({
      method: 'POST',
      url: '/ingest/batch',
      headers: { 'content-type': 'application/json' },
      payload: `{"items":[{"type":"location","payload":{"childId":"${CHILD}","coords":{"lat":1e999,"lng":76.9},"source":"gps","observedAt":"2026-07-21T08:00:00.000Z"}}]}`,
    });
    expect(r.statusCode).toBe(400);
    expect(locations).toHaveLength(0);
  });

  it('refuses a negative accuracy', async () => {
    const r = await post('/ingest/batch', location({ lat: 43.2, lng: 76.9, accuracyM: -1 }));
    expect(r.statusCode).toBe(400);
  });

  it('accepts a real position in Almaty', async () => {
    const r = await post('/ingest/batch', location({ lat: 43.238949, lng: 76.889709, accuracyM: 12 }));
    expect(r.statusCode).toBe(200);
    expect(locations).toHaveLength(1);
  });
});

describe('timestamps', () => {
  it('refuses a timestamp that is not a timestamp', async () => {
    // Stored as given, this reaches the app's freshness logic, which subtracts
    // it from now. "yesterday-ish" parses to NaN and every comparison against
    // NaN is false, so the reading is neither fresh nor stale.
    const r = await post('/ingest/batch', telemetry({ recordedAt: 'yesterday-ish', heartRateBpm: 80 }));
    expect(r.statusCode).toBe(400);
    expect(healthRows).toHaveLength(0);
  });

  it('refuses a location observed at a non-date', async () => {
    const r = await app.inject({
      method: 'POST',
      url: '/ingest/batch',
      payload: {
        items: [
          {
            type: 'location',
            payload: { childId: CHILD, coords: { lat: 43.2, lng: 76.9 }, source: 'gps', observedAt: 'now' },
          },
        ],
      },
    });
    expect(r.statusCode).toBe(400);
  });

  it('accepts an ISO instant', async () => {
    const r = await post('/ingest/batch', telemetry({ recordedAt: '2026-07-21T08:00:00Z', heartRateBpm: 80 }));
    expect(r.statusCode).toBe(200);
  });
});
