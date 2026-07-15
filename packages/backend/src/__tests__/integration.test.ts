/**
 * IN-PROCESS integration test — boots the REAL Fastify server (buildServer) and
 * drives it with fastify.inject(). Exercises the actual routing, zod validation,
 * and handlers (ingestHandler, geofence geometry, guardrail, bp calibration) with
 * in-memory fakes for the DB/Redis/push/LLM. Runs with `npx vitest run` — no
 * Docker/Postgres/Redis required. (The docker-compose smoke additionally exercises
 * the literal pg/Timescale/PostGIS + ioredis drivers.)
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import type { Geofence, GeofenceEvent, ChildLocationFix } from '@fcs/shared';

const USER = '11111111-1111-1111-1111-111111111111';
const CHILD = '33333333-3333-3333-3333-333333333333';
const DEVICE = '22222222-2222-2222-2222-222222222222';

const HOME: Geofence = {
  id: '44444444-4444-4444-4444-444444444444',
  name: 'Home',
  shape: 'circle',
  center: { lat: 43.238949, lng: 76.889709 },
  radiusM: 100,
};

function makeDeps() {
  const events: GeofenceEvent[] = [];
  const pushes = { emergency: 0, geofence: 0 };
  const healthRows: unknown[] = [];
  const calRows: unknown[] = [];
  let lastLocation: ChildLocationFix | null = null;
  const fenceState = new Map<string, 'in' | 'out'>(); // real Redis-like dedup

  const repo: Repository = {
    insertHealthMetric: async (m) => void healthRows.push(m),
    insertBpCalibration: async (_u, c) => void calRows.push(c),
    loadGeofences: async (childId) => (childId === CHILD ? [HOME] : []),
    insertGeofenceEvent: async (e) => void events.push(e),
    insertLocation: async () => {},
    guardianPushTokens: async () => ({ tokens: ['t'], childName: 'Sultan' }),
    guardianPushTokensForUser: async () => ['t'],
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Doctor', tel: '+7700' }],
    deviceOwner: async (id) => (id === DEVICE ? { userId: USER } : null),
  };

  const server = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'Rest and hydrate gently.' },
      ingest: {
        cacheLocation: async (fix) => void (lastLocation = fix),
        resolveTransition: async (childId, fenceId, inside) => {
          const key = `${childId}:${fenceId}`;
          const next = inside ? 'in' : 'out';
          const prev = fenceState.get(key) ?? null;
          fenceState.set(key, next);
          if (prev === next) return null;
          if (prev === null && next === 'out') return null;
          return inside ? 'enter' : 'exit';
        },
        sendEmergencyPush: async () => void pushes.emergency++,
        sendGeofencePush: async () => void pushes.geofence++,
      },
      cacheLastLocation: async () => lastLocation,
      setBpCalibration: async () => {},
    },
    { logger: false },
  );

  return { server, events, pushes, healthRows, calRows, get lastLocation() { return lastLocation; } };
}

let ctx: ReturnType<typeof makeDeps>;
let app: FastifyInstance;
beforeEach(async () => {
  ctx = makeDeps();
  app = ctx.server;
  await app.ready();
});

const post = (url: string, payload: unknown) => app.inject({ method: 'POST', url, payload });
const get = (url: string) => app.inject({ method: 'GET', url });

describe('server wiring (in-process)', () => {
  it('GET /health', async () => {
    const r = await get('/health');
    expect(r.statusCode).toBe(200);
    expect(r.json().ok).toBe(true);
  });

  it('rejects a malformed batch with 400 (zod)', async () => {
    const r = await post('/ingest/batch', { items: [{ type: 'telemetry', payload: { deviceId: '' } }] });
    expect(r.statusCode).toBe(400);
  });

  it('ingests emergency telemetry + Home enter, dedups, then exit', async () => {
    const home = { lat: 43.238949, lng: 76.889709 };
    const away = { lat: 43.30, lng: 77.0 };

    const r1 = await post('/ingest/batch', {
      items: [
        { type: 'telemetry', payload: { deviceId: DEVICE, recordedAt: new Date().toISOString(), systolicMmHg: 148, diastolicMmHg: 95 } },
        { type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } },
      ],
    });
    expect(r1.statusCode).toBe(200);
    const s1 = r1.json();
    expect(s1.telemetryCount).toBe(1);
    expect(s1.emergencies).toBe(1);
    expect(ctx.pushes.emergency).toBe(1);
    expect(s1.geofenceEvents.some((e: GeofenceEvent) => e.geofenceName === 'Home' && e.transition === 'enter')).toBe(true);

    // Duplicate Home fix → no second alert (real dedup).
    const r2 = await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    expect(r2.json().geofenceEvents).toHaveLength(0);

    // Move away → exit.
    const r3 = await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: away, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    expect(r3.json().geofenceEvents.some((e: GeofenceEvent) => e.transition === 'exit')).toBe(true);
  });

  it('rejects telemetry from an unknown device', async () => {
    const r = await post('/ingest/batch', {
      items: [{ type: 'telemetry', payload: { deviceId: '99999999-9999-9999-9999-999999999999', recordedAt: new Date().toISOString(), heartRateBpm: 80 } }],
    });
    expect(r.json().rejected).toBe(1);
    expect(r.json().telemetryCount).toBe(0);
  });

  it('returns last known child location', async () => {
    const away = { lat: 43.30, lng: 77.0 };
    await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: away, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    const r = await get(`/children/${CHILD}/location`);
    expect(r.statusCode).toBe(200);
    expect(r.json().coords.lat).toBeCloseTo(away.lat);
  });

  it('computes BP calibration offsets', async () => {
    const r = await post('/calibration/bp', {
      userId: USER, cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      measuredAt: new Date().toISOString(),
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().systolicOffset).toBe(8);
    expect(r.json().diastolicOffset).toBe(4);
  });

  it('AI chat with a critical reading forces the emergency screen (LLM bypassed)', async () => {
    const r = await post('/ai/chat', {
      userId: USER, locale: 'ru-KZ', message: 'is everything okay?',
      latestTelemetry: { systolicMmHg: 150, diastolicMmHg: 96 },
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().action).toBe('SHOW_EMERGENCY_SCREEN');
  });

  it('AI chat normal question returns a grounded reply', async () => {
    const r = await post('/ai/chat', { userId: USER, locale: 'en', message: 'tips for sleep?' });
    expect(r.json().kind).toBe('chat');
  });
});
