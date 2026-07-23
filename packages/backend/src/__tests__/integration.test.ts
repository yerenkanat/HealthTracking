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
import type { InjectPayload, Response as InjectResponse } from 'light-my-request';
import { buildServer } from '../server';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import type { Repository, SleepNight, DayLogRow, SafetyAlertRow, ProfileRow } from '../db/repository';
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

type StaffRole = 'admin' | 'clinician' | 'support';
function makeDeps(
  authUser: () => Promise<{ userId: string } | null> = async () => ({ userId: USER }),
  authAdmin: () => Promise<{ staffId: string; role: StaffRole } | null> = async () => ({ staffId: 's1', role: 'admin' }),
  chatLimiter?: import('../http/rateLimit').RateLimiter,
  ingestLimiter?: import('../http/rateLimit').RateLimiter,
) {
  const events: GeofenceEvent[] = [];
  const pushes = { emergency: 0, geofence: 0 };
  const healthRows: unknown[] = [];
  const calRows: unknown[] = [];
  let lastLocation: ChildLocationFix | null = null;
  const fenceState = new Map<string, 'in' | 'out'>(); // real Redis-like dedup

  // In-memory CRUD state
  const children: Array<{ id: string; name: string; gender?: 'boy' | 'girl' | null; dateOfBirth?: string | null }> = [];
  const appointments: Array<{ id: string; title: string; at: string; note: string; userId: string }> = [];
  const medRows: Array<{ id: string; name: string; dose: string; perDay: number; userId: string }> = [];
  const medicalIds = new Map<string, Record<string, string>>();
  const newbornRows = new Map<string, Array<{ at: string; kind: string; detail: string | null; durationMin: number | null }>>();
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null }> = [];
  const geofences = new Map<string, import('@fcs/shared').Geofence[]>();
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
  const sleepRows: SleepNight[] = [];
  const weightRows: Array<{ date: string; kg: number }> = [];
  const kickRows: Array<{ endedAt: string; count: number; durationSec: number }> = [];
  const contractionRows: Array<{ endedAt: string; count: number; avgDurationSec: number; avgIntervalSec: number }> = [];
  const dayLogs = new Map<string, DayLogRow>();
  const alertRows: SafetyAlertRow[] = [];
  const contentRows = new Map<string, import('../db/repository').ContentItemRow[]>();
  let profile: ProfileRow | null = null;
  let idSeq = 1;

  const repo: Repository = {
    insertHealthMetric: async (m) => void healthRows.push(m),
    insertBpCalibration: async (_u, c) => void calRows.push(c),
    latestBpCalibration: async () =>
      (calRows.length ? calRows[calRows.length - 1] : null) as never,
    loadGeofences: async (childId) =>
      childId === CHILD ? [HOME, ...(geofences.get(childId) ?? [])] : (geofences.get(childId) ?? []),
    insertGeofenceEvent: async (e) => void events.push(e),
    insertLocation: async () => {},
    guardianPushTokens: async () => ({ tokens: ['t'], childName: 'Sultan', locale: 'ru-KZ' }),
    guardianPushTokensForUser: async () => ({ tokens: ['t'], locale: 'ru-KZ' }),
    deletePushToken: async () => {},
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Doctor', tel: '+7700' }],
    deviceOwner: async (id) =>
      id === DEVICE || devices.some((d) => d.id === id) ? { userId: USER } : null,
    // Child- and zone-scoped routes now verify the caller owns the id in the
    // URL, so the fake has to answer ownership questions too.
    childOwner: async (id) =>
      id === CHILD || children.some((c) => c.id === id) ? { userId: USER } : null,
    geofenceOwner: async (id) =>
      [...geofences.values()].flat().some((g) => g.id === id) ? { userId: USER } : null,
    // CRUD
    listChildren: async () => children.map((c) => ({ id: c.id, name: c.name, gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null })),
    upsertChild: async (_u, c) => {
      const row = { id: c.id, name: c.name, gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null };
      const i = children.findIndex((x) => x.id === c.id);
      if (i >= 0) children[i] = row; else children.push(row);
    },
    deleteChild: async (id) => {
      const i = children.findIndex((c) => c.id === id);
      if (i >= 0) children.splice(i, 1);
    },
    listAppointments: async (uid) =>
      appointments.filter((a) => a.userId === uid).map(({ userId: _drop, ...a }) => a),
    upsertAppointment: async (uid, a) => {
      const i = appointments.findIndex((x) => x.id === a.id);
      const row = { ...a, note: a.note ?? '', userId: uid };
      if (i >= 0) appointments[i] = row; else appointments.push(row);
    },
    appointmentOwner: async (id) => {
      const a = appointments.find((x) => x.id === id);
      return a ? { userId: a.userId } : null;
    },
    deleteAppointment: async (id) => {
      const i = appointments.findIndex((a) => a.id === id);
      if (i >= 0) appointments.splice(i, 1);
    },
    listMedications: async (uid) => medRows.filter((m) => m.userId === uid).map(({ userId: _d, ...m }) => m),
    upsertMedication: async (uid, m) => {
      const i = medRows.findIndex((x) => x.id === m.id);
      const row = { ...m, userId: uid };
      if (i >= 0) medRows[i] = row; else medRows.push(row);
    },
    medicationOwner: async (id) => {
      const m = medRows.find((x) => x.id === id);
      return m ? { userId: m.userId } : null;
    },
    deleteMedication: async (id) => {
      const i = medRows.findIndex((m) => m.id === id);
      if (i >= 0) medRows.splice(i, 1);
    },
    listDevices: async () => devices.map((d) => ({ ...d })),
    createDevice: async (_u, d) => void devices.push({ ...d, childId: d.childId ?? null }),
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
    },
    upsertGeofence: async (childId, g) => {
      const list = geofences.get(childId) ?? [];
      const i = list.findIndex((x) => x.id === g.id);
      if (i >= 0) list[i] = g; else list.push(g);
      geofences.set(childId, list);
    },
    deleteGeofence: async (id) => {
      for (const [k, list] of geofences) geofences.set(k, list.filter((g) => g.id !== id));
    },
    recordNewbornEvent: async (childId, e) => {
      const list = newbornRows.get(childId) ?? [];
      const i = list.findIndex((x) => x.at === e.at && x.kind === e.kind);
      if (i >= 0) list[i] = e; else list.push(e);
      newbornRows.set(childId, list);
    },
    listNewbornEvents: async (userId, limit) => {
      if (userId !== USER) return [];
      const out: Array<Record<string, unknown>> = [];
      for (const [childId, list] of newbornRows) {
        const c = children.find((x) => x.id === childId);
        for (const e of list) out.push({ childId, childName: c?.name ?? 'Sultan', ...e });
      }
      out.sort((a, b) => String(b.at).localeCompare(String(a.at)));
      return out.slice(0, limit) as never;
    },
    upsertChildEmergency: async (childId, m) => void medicalIds.set(childId, { ...m } as Record<string, string>),
    listMedicalIds: async (userId) => {
      const out: Array<Record<string, unknown>> = [];
      if (userId !== USER) return out as never;
      for (const [childId, m] of medicalIds) {
        const c = children.find((x) => x.id === childId);
        out.push({ childId, childName: c?.name ?? 'Sultan', ...m });
      }
      return out as never;
    },
    getChildEmergency: async (childId) => (medicalIds.get(childId) ?? null) as never,
    queryMetrics: async () => [{ t: '2026-07-15T08:00:00Z', value: 72 }, { t: '2026-07-15T08:05:00Z', value: 80 }],
    listGeofenceEvents: async () => events.filter((e) => e.transition),
    // Sleep
    recordSleep: async (_u, s) => {
      const i = sleepRows.findIndex((x) => x.night === s.night);
      if (i >= 0) sleepRows[i] = s; else sleepRows.push(s);
    },
    listSleep: async (_u, limit) => [...sleepRows].sort((a, b) => b.night.localeCompare(a.night)).slice(0, limit),
    recordWeight: async (_u, w) => {
      const i = weightRows.findIndex((x) => x.date === w.date);
      if (i >= 0) weightRows[i] = w; else weightRows.push(w);
    },
    listWeight: async (_u, limit) => [...weightRows].sort((a, b) => b.date.localeCompare(a.date)).slice(0, limit),
    recordKickSession: async (_u, s) => {
      const i = kickRows.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) kickRows[i] = s; else kickRows.push(s);
    },
    listKickSessions: async (_u, limit) => [...kickRows].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    recordContractionSession: async (_u, s) => {
      const i = contractionRows.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) contractionRows[i] = s; else contractionRows.push(s);
    },
    listContractionSessions: async (_u, limit) => [...contractionRows].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    // Day logs
    upsertDayLog: async (_u, log) => void dayLogs.set(log.date, log),
    listDayLogs: async (_u, from, to) =>
      [...dayLogs.values()].filter((d) => d.date >= from && d.date <= to).sort((a, b) => a.date.localeCompare(b.date)),
    // Safety alerts
    recordAlert: async (_u, a) => void alertRows.unshift(a),
    listAlerts: async (_u, limit) => alertRows.slice(0, limit),
    // Profile + device reassignment
    getProfile: async () => profile,
    upsertProfile: async (_u, p) => void (profile = p),
    reassignDevice: async (id, childId) => {
      const d = devices.find((x) => x.id === id);
      if (d) d.childId = childId;
    },
    deleteAccount: async (userId) => {
      if (userId !== USER) return false;
      profile = null;
      children.length = 0;
      devices.length = 0;
      geofences.clear();
      sleepRows.length = 0;
      dayLogs.clear();
      alertRows.length = 0;
      healthRows.length = 0;
      return true;
    },
    // Admin
    adminStats: async () => ({ activeUsers: 1, devicesOnline: devices.length, alertsToday: pushes.emergency, ingestLastHour: healthRows.length }),
    childrenStats: async () => ({ total: 0, boys: 0, girls: 0, unknown: 0, withDob: 0, byAge: [] }),
    recentEmergencies: async () => [{ id: `${USER}|2026-07-15T08:00:00Z`, userId: USER, displayName: 'Aigerim', code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00Z', acknowledgedAt: null, acknowledgedBy: null }],
    acknowledgeEmergency: async () => true,
    adminListUsers: async () => ({ total: 1, users: [{ id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01' }] }),
    adminUserHealth: async (userId) =>
      userId === USER ? { latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 }, triage: [{ code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00Z' }] } : null,
    adminUserDetail: async (userId) =>
      userId === USER
        ? {
            id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01', locale: 'ru-KZ',
            // Given, so the panel's rendering of the populated case is exercised;
            // the memory repository seeds them null, which covers the other.
            birthDate: '1996-04-12', city: 'Алматы',
            children: children.map((c) => ({ id: c.id, name: c.name, dateOfBirth: null, zones: 0 })),
            devices: devices.map((d) => ({ ...d, batteryPct: 62 })),
            latest: { hr: 80 }, triage: [], alerts: [], sleepNights: sleepRows.length, loggedDays: dayLogs.size,
          }
        : null,
    adminDevices: async (limit) =>
      devices.slice(0, limit).map((d) => ({
        id: d.id, name: d.name, kind: d.kind, userId: USER, displayName: 'Aigerim',
        childName: null, batteryPct: 62, lastSeen: '2026-07-15T08:00:00Z',
      })),
    adminSafetyEvents: async (limit) =>
      alertRows.slice(0, limit).map((a) => ({
        userId: USER, displayName: 'Aigerim', childName: 'Sultan',
        kind: a.kind, zoneName: a.zoneName, at: a.at,
      })),
    adminAnalytics: async () => ({
      totalUsers: 1, pregnant: 1, withChildren: children.length, devices: devices.length,
      alerts7d: alertRows.length, sosAllTime: 0, stageDistribution: {},
      contentStages: contentRows.size, contentItems: 0, contentLinked: 0,
    }),
    // Computed rather than hand-written, so the fixture cannot claim a shape
    // the real metric code does not produce.
    adminBiMetrics: async () =>
      computeBiMetrics({
        users: [{ id: USER, createdAt: '2026-06-01T00:00:00Z' }],
        events: alertRows.map((a) => ({ userId: USER, at: a.at, kind: 'alert' as const })),
        devices: { total: devices.length, online: devices.length },
        now: new Date('2026-07-15T08:00:00Z'),
      }),
    contentCatalog: async () => Object.fromEntries(contentRows),
    putStageContent: async (stageKey, items) => {
      if (items.length === 0) contentRows.delete(stageKey);
      else contentRows.set(stageKey, items);
    },
    writeAudit: async (e) => void audit.push({ ...e, target: e.target ?? null, at: '2026-07-15T08:00:00Z' }),
    listAudit: async () => audit.map((a) => ({ ...a })),
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
      authUser,
      authAdmin,
      chatLimiter,
      ingestLimiter,
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

// The return type is stated explicitly because inject() also has a
// callback-style overload, and without it TypeScript resolves these to
// `void & Promise<Response> & Chain` — every `r.statusCode` in the file then
// fails to typecheck even though the calls are correct.
const post = (url: string, payload: InjectPayload): Promise<InjectResponse> =>
  app.inject({ method: 'POST', url, payload });
const get = (url: string): Promise<InjectResponse> =>
  app.inject({ method: 'GET', url });

describe('server wiring (in-process)', () => {
  it('GET /health', async () => {
    const r = await get('/health');
    expect(r.statusCode).toBe(200);
    expect(r.json().ok).toBe(true);
  });

  // ---- Erasing the account ----
  // The app's reset says "all data will be erased" and only cleared the phone;
  // there was no server-side deletion at all. With telemetry syncing, her
  // blood-pressure history, her child's name and date of birth and the
  // coordinates of her home and her child's school outlived the account she
  // believed she had removed.
  it('erases the account and everything belonging to it', async () => {
    await post('/children', { id: '55555555-5555-5555-5555-555555555555', name: 'Sultan' });
    await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 118,
            diastolicMmHg: 76,
          },
        },
      ],
    });
    expect((await get('/children')).json().children).toHaveLength(1);

    const r = await app.inject({ method: 'DELETE', url: '/account' });
    expect(r.statusCode).toBe(204);
    expect((await get('/children')).json().children).toHaveLength(0);
  });

  it('refuses to erase without a session', async () => {
    // There is no id in the path, so this can never be aimed at another
    // account — but it must still be impossible to fire unauthenticated.
    const { server } = makeDeps(async () => null); // nobody signed in
    await server.ready();
    const r = await server.inject({ method: 'DELETE', url: '/account' });
    expect(r.statusCode).toBe(401);
    await server.close();
  });

  // ---- Ingest is bounded, but only for a runaway ----
  it('stops a client that will not stop posting', async () => {
    // Ingest was unlimited on the reasoning that dropping it would lose health
    // data. A 429 does not drop anything — the client requeues, exactly as it
    // does with no signal — so the real choice was between a limit and letting
    // one authenticated caller write to a timeseries database as fast as it
    // can post 500-item batches.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 3, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, undefined, limiter);
    await server.ready();

    const send = () =>
      server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: {
          items: [
            {
              type: 'telemetry',
              payload: {
                deviceId: '',
                source: 'manual',
                recordedAt: new Date().toISOString(),
                heartRateBpm: 72,
              },
            },
          ],
        },
      });

    for (let i = 0; i < 3; i++) {
      expect((await send()).statusCode).toBe(200);
    }
    const blocked = await send();
    expect(blocked.statusCode).toBe(429);
    // Retry-After so the client backs off by the server's clock, not a guess.
    expect(blocked.headers['retry-after']).toBeTruthy();
    expect(blocked.json().retryAfterSec).toBeGreaterThan(0);
    await server.close();
  });

  it('a legitimate backlog drain never meets the limit', async () => {
    // The worst legitimate case is a phone coming back after a long spell
    // offline: a full 5000-item queue leaves in 25 back-to-back requests at
    // maxFlushItems=200. If the limit bit there it would cost real readings,
    // because the queue trims its oldest ordinary items once it overflows.
    const { server } = makeDeps(); // the production default: 120 per 5 min
    await server.ready();
    for (let i = 0; i < 25; i++) {
      const r = await server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: {
          items: [
            {
              type: 'telemetry',
              payload: {
                deviceId: '',
                source: 'manual',
                recordedAt: new Date().toISOString(),
                heartRateBpm: 70 + i,
              },
            },
          ],
        },
      });
      expect(r.statusCode, `request ${i + 1} of the drain was rejected`).toBe(200);
    }
    await server.close();
  });

  it('an unauthenticated ingest never spends the budget', async () => {
    // Same reasoning as the chat limiter: taking a token before knowing who is
    // asking would let anyone exhaust a named user's allowance.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(async () => null, undefined, undefined, limiter);
    await server.ready();
    for (let i = 0; i < 5; i++) {
      const r = await server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: { items: [] },
      });
      expect(r.statusCode).toBe(401);
    }
    expect(limiter.size).toBe(0);
    await server.close();
  });

  it('rejects a malformed batch with 400 (zod)', async () => {
    const r = await post('/ingest/batch', { items: [{ type: 'telemetry', payload: { deviceId: '' } }] });
    expect(r.statusCode).toBe(400);
  });

  // ---- Readings entered by hand ----
  // The most trustworthy number the product has is a cuff reading the mother
  // types in — an actual cuff, not a PPG estimate. Attribution went only
  // through deviceOwner(), so a reading with no device to name was refused at
  // the edge and dropped by the handler. Her clinician's view never showed
  // one, and nothing anywhere said so.
  it('accepts a hand-entered reading and attributes it to the caller', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 118,
            diastolicMmHg: 76,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().telemetryCount).toBe(1);
    expect(r.json().rejected).toBe(0);
  });

  it('runs the server-side emergency backstop on a hand-entered reading', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 175,
            diastolicMmHg: 118,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().emergencies).toBe(1);
  });

  it('still refuses a BAND reading with no device', async () => {
    // The relaxation is for hand-entered readings only. A band reading with no
    // device cannot be attributed to anyone either, and must keep failing at
    // the edge rather than being quietly credited to whoever posted it.
    const r = await post('/ingest/batch', {
      items: [
        { type: 'telemetry', payload: { deviceId: '', recordedAt: new Date().toISOString() } },
      ],
    });
    expect(r.statusCode).toBe(400);
  });

  it('still refuses a band reading for a device the caller does not own', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: 'someone-elses-band',
            recordedAt: new Date().toISOString(),
            heartRateBpm: 80,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().rejected).toBe(1);
    expect(r.json().telemetryCount).toBe(0);
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

  it('accepts a BP calibration with no body userId (identity from the session)', async () => {
    const r = await post('/calibration/bp', {
      cuffSystolic: 130, cuffDiastolic: 85, ppgSystolic: 122, ppgDiastolic: 80,
      measuredAt: '2026-07-22T09:00:00.000Z',
    });
    expect(r.statusCode).toBe(200);
    // ...and the owner can pull the latest back for a new-device restore.
    const got = (await get('/calibration/bp')).json().calibration;
    expect(got.systolicOffset).toBe(8); // 130 − 122
    expect(got.diastolicOffset).toBe(5); // 85 − 80
    expect(got.cuffSystolic).toBe(130);
    // ...and it surfaces in the clinician's wellness view.
    const wellness = (await get(`/admin/users/${USER}/wellness`)).json();
    expect(wellness.bpCalibration.diastolicOffset).toBe(5);
  });

  it('rejects a BP calibration whose body userId is not the caller', async () => {
    const r = await post('/calibration/bp', {
      userId: '99999999-9999-9999-9999-999999999999',
      cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      measuredAt: '2026-07-22T09:00:00.000Z',
    });
    expect(r.statusCode).toBe(403);
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

describe('/ai/chat rate limiting', () => {
  // The route spends money and reaches a third party on every call, and had no
  // limit of any kind — a broken retry loop was as expensive as an abusive one.
  const buildLimited = async (limit: number) => {
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, limiter);
    await server.ready();
    return { app: server, limiter };
  };

  const chat = (app: FastifyInstance, userId = USER) =>
    app.inject({
      method: 'POST',
      url: '/ai/chat',
      payload: { userId, locale: 'en', message: 'hello' } as InjectPayload,
    });

  it('refuses with 429 once the caller is over the limit', async () => {
    const { app } = await buildLimited(2);
    expect((await chat(app)).statusCode).toBe(200);
    expect((await chat(app)).statusCode).toBe(200);
    const over = await chat(app);
    expect(over.statusCode).toBe(429);
    expect(over.json().error).toBe('rate_limited');
    await app.close();
  });

  it('tells the client how long to wait, in a header and the body', async () => {
    const { app } = await buildLimited(1);
    await chat(app);
    const over = await chat(app);
    expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);
    expect(over.json().retryAfterSec).toBeGreaterThan(0);
    await app.close();
  });

  it('an unauthenticated request never spends the budget', async () => {
    // The limit is taken AFTER auth on purpose: if it ran first, anyone could
    // burn a stranger's allowance without ever proving who they are — a
    // denial-of-service on the assistant, aimed at one named user.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(async () => null, undefined, limiter); // nobody signed in
    await server.ready();

    for (let i = 0; i < 5; i++) {
      expect((await chat(server)).statusCode).toBe(401);
    }
    expect(limiter.size).toBe(0); // not one token spent
    await server.close();
  });

  it('a forbidden request does not spend the budget either', async () => {
    // Asking as somebody else is rejected at the ownership check; that must
    // not cost the impersonated user their allowance.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, limiter);
    await server.ready();

    const r = await server.inject({
      method: 'POST',
      url: '/ai/chat',
      payload: { userId: CHILD, locale: 'en', message: 'hi' } as InjectPayload,
    });
    expect(r.statusCode).toBe(403);
    expect(limiter.size).toBe(0);
    await server.close();
  });
});

describe('CRUD + history routes (in-process)', () => {
  it('children: create → list → delete', async () => {
    expect((await get('/children')).json().children).toHaveLength(0);
    const id = '66666666-6666-6666-6666-666666666666';
    const created = await post('/children', { id, name: 'Sultan' });
    expect(created.statusCode).toBe(201);
    expect((await get('/children')).json().children).toHaveLength(1);
    const del = await app.inject({ method: 'DELETE', url: `/children/${id}` });
    expect(del.statusCode).toBe(204);
    expect((await get('/children')).json().children).toHaveLength(0);
  });

  it('children: rejects empty name (zod 400)', async () => {
    expect((await post('/children', { id: '66666666-6666-6666-6666-666666666666', name: '' })).statusCode).toBe(400);
  });

  it('children: rejects a non-UUID id (zod 400)', async () => {
    expect((await post('/children', { id: 'child-1', name: 'Sultan' })).statusCode).toBe(400);
  });

  it('children: upsert is idempotent on the id and carries gender + DOB', async () => {
    const id = '77777777-7777-7777-7777-777777777777';
    await post('/children', { id, name: 'Aruzhan', gender: 'girl', dateOfBirth: '2024-03-01' });
    await post('/children', { id, name: 'Aruzhan B.', gender: 'girl', dateOfBirth: '2024-03-01' });
    const kids = (await get('/children')).json().children;
    expect(kids).toHaveLength(1); // updated, not duplicated
    expect(kids[0].name).toBe('Aruzhan B.');
    // GET returns gender + DOB so a new device can restore the full child.
    expect(kids[0].gender).toBe('girl');
    expect(kids[0].dateOfBirth).toBe('2024-03-01');
  });

  it('devices: create → list → delete', async () => {
    const r = await post('/devices', { id: 'AA:BB', name: 'Band', kind: 'band' });
    expect(r.statusCode).toBe(201);
    expect((await get('/devices')).json().devices).toHaveLength(1);
    expect((await post('/devices', { id: 'x', kind: 'nope' })).statusCode).toBe(400); // bad kind
    const del = await app.inject({ method: 'DELETE', url: '/devices/AA:BB' });
    expect(del.statusCode).toBe(204);
    expect((await get('/devices')).json().devices).toHaveLength(0);
  });

  it('geofences: upsert a circle for a child (client id), then list', async () => {
    const gid = 'aaaaaaaa-0000-4000-8000-000000000001';
    const r = await post(`/children/${CHILD}/geofences`, {
      id: gid, name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 80,
    });
    expect(r.statusCode).toBe(201);
    // Re-sync the same id with a new radius → updates, not duplicates.
    await post(`/children/${CHILD}/geofences`, {
      id: gid, name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 120,
    });
    const list = (await get(`/children/${CHILD}/geofences`)).json().geofences;
    const parks = list.filter((g: { name: string }) => g.name === 'Park');
    expect(parks).toHaveLength(1);
    expect(parks[0].radiusM).toBe(120);
  });

  it('geofences: rejects a non-UUID id (zod 400)', async () => {
    const r = await post(`/children/${CHILD}/geofences`, {
      id: 'zone-1', name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 80,
    });
    expect(r.statusCode).toBe(400);
  });

  it('newborn events: record for a child, read back via admin wellness (newest first)', async () => {
    expect((await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T08:00:00.000Z', kind: 'feed', detail: 'left' } })).statusCode).toBe(201);
    await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T10:00:00.000Z', kind: 'diaper', detail: 'wet' } });
    const evs = (await get(`/admin/users/${USER}/wellness`)).json().newbornEvents;
    expect(evs.length).toBeGreaterThanOrEqual(2);
    expect(evs[0].kind).toBe('diaper'); // newest first
    expect(evs[0].childName).toBeTruthy();

    // ...and the owner can pull the same events (tagged with childId) to restore
    // the baby log on a new device.
    const restore = (await get('/newborn-events')).json().events;
    expect(restore.length).toBeGreaterThanOrEqual(2);
    expect(restore[0].childId).toBe(CHILD);
    expect(restore.some((e: { kind: string }) => e.kind === 'feed')).toBe(true);
  });

  it('newborn events: rejects a bad kind (zod 400)', async () => {
    const r = await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T08:00:00.000Z', kind: 'burp' } });
    expect(r.statusCode).toBe(400);
  });

  it('emergency: upsert a child medical-ID, then read it via the admin wellness view', async () => {
    const r = await app.inject({
      method: 'PUT', url: `/children/${CHILD}/emergency`,
      payload: { bloodType: 'O+', allergies: 'penicillin', conditions: '', medications: '',
        doctorName: 'Dr Aliyeva', doctorPhone: '+7700', contactName: 'Gran', contactPhone: '+7701', notes: '' },
    });
    expect(r.statusCode).toBe(200);
    // The admin drawer reads it back joined with the child's name.
    const ids = (await get(`/admin/users/${USER}/wellness`)).json().medicalIds;
    const card = ids.find((m: { childId: string }) => m.childId === CHILD);
    expect(card.bloodType).toBe('O+');
    expect(card.allergies).toBe('penicillin');
    expect(card.childName).toBeTruthy();

    // ...and the owner can pull it back for a new-device restore.
    const restore = await get(`/children/${CHILD}/emergency`);
    expect(restore.statusCode).toBe(200);
    expect(restore.json().medicalId.bloodType).toBe('O+');
    expect(restore.json().medicalId.contactPhone).toBe('+7701');
  });

  it('emergency: GET returns null when a child has no medical-ID', async () => {
    const fresh = '44444444-4444-4444-4444-444444444444';
    await post('/children', { id: fresh, name: 'Nsurlan', gender: 'boy', dateOfBirth: null });
    const r = await get(`/children/${fresh}/emergency`);
    expect(r.statusCode).toBe(200);
    expect(r.json().medicalId).toBeNull();
  });

  it('metrics history query validates + returns points', async () => {
    expect((await get('/metrics?from=a&to=b&metric=nope')).statusCode).toBe(400);
    const r = await get('/metrics?from=2026-07-15T00:00:00Z&to=2026-07-16T00:00:00Z&metric=hr');
    expect(r.statusCode).toBe(200);
    expect(r.json().points.length).toBeGreaterThan(0);
  });

  it('401 when the request is unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/children' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'POST', url: '/children', payload: { name: 'X' } })).statusCode).toBe(401);
  });
});

describe('sleep / cycle / alerts routes (in-process)', () => {
  it('sleep: record nights → list newest-first', async () => {
    expect((await get('/sleep')).json().nights).toHaveLength(0);
    expect((await post('/sleep', { night: '2026-07-14', deepMin: 70, remMin: 90, lightMin: 250, awakeMin: 35 })).statusCode).toBe(201);
    await post('/sleep', { night: '2026-07-15', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25 });
    const nights = (await get('/sleep')).json().nights;
    expect(nights).toHaveLength(2);
    expect(nights[0].night).toBe('2026-07-15'); // newest first
    expect(nights[0].deepMin).toBe(95);
  });

  it('sleep: rejects out-of-range minutes (zod 400)', async () => {
    expect((await post('/sleep', { night: '2026-07-15', deepMin: -1, remMin: 0, lightMin: 0, awakeMin: 0 })).statusCode).toBe(400);
    expect((await post('/sleep', { night: '2026-07-15', deepMin: 0, remMin: 0, lightMin: 9999, awakeMin: 0 })).statusCode).toBe(400);
  });

  it('weight: record → list newest-first, upsert on the date', async () => {
    expect((await get('/weight')).json().entries).toHaveLength(0);
    expect((await post('/weight', { date: '2026-07-14', kg: 64.2 })).statusCode).toBe(201);
    await post('/weight', { date: '2026-07-15', kg: 64.5 });
    await post('/weight', { date: '2026-07-15', kg: 64.8 }); // same day → updates
    const entries = (await get('/weight')).json().entries;
    expect(entries).toHaveLength(2); // not 3 — the 15th was upserted
    expect(entries[0].date).toBe('2026-07-15'); // newest first
    expect(entries[0].kg).toBe(64.8);
  });

  it('weight: rejects an out-of-range or misfingered value (zod 400)', async () => {
    expect((await post('/weight', { date: '2026-07-15', kg: 3.5 })).statusCode).toBe(400); // grams, not kg
    expect((await post('/weight', { date: '2026-07-15', kg: 3500 })).statusCode).toBe(400);
    expect((await post('/weight', { date: 'nope', kg: 64 })).statusCode).toBe(400);
  });

  it('kick sessions: record → list newest-first, upsert on endedAt', async () => {
    expect((await get('/kick-sessions')).json().sessions).toHaveLength(0);
    expect((await post('/kick-sessions', { endedAt: '2026-07-20T10:00:00.000Z', count: 10, durationSec: 600 })).statusCode).toBe(201);
    await post('/kick-sessions', { endedAt: '2026-07-21T10:00:00.000Z', count: 8, durationSec: 900 });
    await post('/kick-sessions', { endedAt: '2026-07-21T10:00:00.000Z', count: 9, durationSec: 800 }); // same instant → updates
    const s = (await get('/kick-sessions')).json().sessions;
    expect(s).toHaveLength(2);
    expect(s[0].count).toBe(9); // newest, upserted
  });

  it('contraction sessions: record → list, and reject a bad body', async () => {
    expect((await post('/contraction-sessions', { endedAt: '2026-07-22T02:00:00.000Z', count: 6, avgDurationSec: 55, avgIntervalSec: 300 })).statusCode).toBe(201);
    const s = (await get('/contraction-sessions')).json().sessions;
    expect(s[0].avgIntervalSec).toBe(300);
    expect((await post('/contraction-sessions', { endedAt: 'nope', count: 1, avgDurationSec: 1, avgIntervalSec: 1 })).statusCode).toBe(400);
  });

  it('medications: upsert on the client id → list → delete', async () => {
    expect((await get('/medications')).json().medications).toHaveLength(0);
    expect((await post('/medications', { id: 'med-1', name: 'Фолиевая кислота', dose: '400 мкг', perDay: 1 })).statusCode).toBe(201);
    await post('/medications', { id: 'med-1', name: 'Фолиевая кислота', dose: '800 мкг', perDay: 2 }); // same id → updates
    const meds = (await get('/medications')).json().medications;
    expect(meds).toHaveLength(1); // upserted, not duplicated
    expect(meds[0].dose).toBe('800 мкг');
    expect(meds[0].perDay).toBe(2);
    const del = await app.inject({ method: 'DELETE', url: '/medications/med-1' });
    expect(del.statusCode).toBe(204);
    expect((await get('/medications')).json().medications).toHaveLength(0);
  });

  it('medications: rejects an empty name (zod 400)', async () => {
    expect((await post('/medications', { id: 'med-x', name: '' })).statusCode).toBe(400);
  });

  it('cycle day logs: upsert (PUT) + range query', async () => {
    const put = await app.inject({
      method: 'PUT', url: '/cycle/days',
      payload: { date: '2026-07-15', mood: 'calm', symptoms: ['cramps'], kicks: 3, flow: 'medium' },
    });
    expect(put.statusCode).toBe(200);
    // upsert same day updates in place
    await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', mood: 'happy', symptoms: [], kicks: 5 } });
    const days = (await get('/cycle/days?from=2026-07-01&to=2026-07-31')).json().days;
    expect(days).toHaveLength(1);
    expect(days[0].mood).toBe('happy');
    expect(days[0].kicks).toBe(5);
    expect(days[0].flow).toBeNull(); // omitted → cleared to null
  });

  it('cycle day logs: rejects a bad date + bad enum (zod 400)', async () => {
    expect((await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '15-07-2026' } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', flow: 'gushing' } })).statusCode).toBe(400);
    expect((await get('/cycle/days?from=only-one')).statusCode).toBe(400); // missing `to`
    // A malformed date is a client error, not something to hand to the database.
    expect((await get('/cycle/days?from=nonsense&to=2026-07-31')).statusCode).toBe(400);
    // Ordered correctly, so this can only 400 because the date itself is invalid.
    expect((await get('/cycle/days?from=2026-01-01&to=2026-13-45')).statusCode).toBe(400);
    // A backwards range can only be a mistake.
    expect((await get('/cycle/days?from=2026-07-31&to=2026-07-01')).statusCode).toBe(400);
  });

  it('alerts: record enter/exit → list newest-first', async () => {
    await post('/alerts', { childId: CHILD, kind: 'left', zoneName: 'Home', at: '2026-07-16T09:00:00Z' });
    await post('/alerts', { childId: CHILD, kind: 'entered', zoneName: 'School', at: '2026-07-16T09:05:00Z' });
    const alerts = (await get('/alerts')).json().alerts;
    expect(alerts).toHaveLength(2);
    expect(alerts[0].kind).toBe('entered');
    expect(alerts[0].zoneName).toBe('School');
    expect((await post('/alerts', { childId: CHILD, kind: 'teleported', zoneName: 'X', at: '2026-07-16T09:05:00Z' })).statusCode).toBe(400);
  });

  it('401 when unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/sleep' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'POST', url: '/alerts', payload: {} })).statusCode).toBe(401);
  });
});

describe('profile + device reassignment routes (in-process)', () => {
  it('profile: 404 until set, then PUT upsert → GET', async () => {
    expect((await get('/profile')).statusCode).toBe(404);
    const put = await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-12-01', locale: 'ru-KZ' },
    });
    expect(put.statusCode).toBe(200);
    const p = (await get('/profile')).json().profile;
    expect(p.displayName).toBe('Aigerim');
    expect(p.dueDate).toBe('2026-12-01');
  });

  it('profile: rejects empty name + malformed due date (zod 400)', async () => {
    expect((await app.inject({ method: 'PUT', url: '/profile', payload: { displayName: '' } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PUT', url: '/profile', payload: { displayName: 'A', dueDate: '12/01/2026' } })).statusCode).toBe(400);
  });

  it('reassign a tracker tag to another child (PATCH), then unlink', async () => {
    await post('/devices', { id: 'TAG-1', name: 'Tag', kind: 'tag', childId: CHILD });
    const find = async () => (await get('/devices')).json().devices.find((x: { id: string }) => x.id === 'TAG-1');
    expect((await find()).childId).toBe(CHILD);

    // Reassign to a second child the SAME user owns. Reassignment now checks
    // both ends, so an arbitrary child id is correctly refused (see
    // authorization.test.ts) — this test needs a real sibling.
    const other = '88888888-8888-8888-8888-888888888888';
    await post('/children', { id: other, name: 'Aida' });
    expect((await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: { childId: other } })).statusCode).toBe(200);
    expect((await find()).childId).toBe(other);

    await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: { childId: null } });
    expect((await find()).childId).toBeNull();
    // childId is required in the body
    expect((await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: {} })).statusCode).toBe(400);
  });

  it('401 when unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/profile' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'PUT', url: '/profile', payload: { displayName: 'X' } })).statusCode).toBe(401);
  });
});

describe('admin API (in-process, RBAC + audit)', () => {
  it('stats returns KPIs to staff', async () => {
    const r = await get('/admin/stats');
    expect(r.statusCode).toBe(200);
    expect(r.json()).toHaveProperty('activeUsers');
    expect(r.json()).toHaveProperty('alertsToday');
  });

  it('emergency feed returns events and writes an audit entry', async () => {
    const r = await get('/admin/emergencies');
    expect(r.statusCode).toBe(200);
    expect(r.json().emergencies[0].code).toBe('PREECLAMPSIA_BP');
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string }) => a.action === 'view_emergencies')).toBe(true);
  });

  it('patient health view is audited; unknown user 404', async () => {
    const r = await get(`/admin/users/${USER}/health`);
    expect(r.statusCode).toBe(200);
    expect(r.json().latest.systolic).toBe(138);
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string; target: string }) => a.action === 'view_health' && a.target === USER)).toBe(true);
    expect((await get('/admin/users/00000000-0000-0000-0000-000000000000/health')).statusCode).toBe(404);
  });

  it('user list + audit require the admin role (clinician → 403)', async () => {
    const clinician = makeDeps(undefined, async () => ({ staffId: 'c1', role: 'clinician' })).server;
    await clinician.ready();
    expect((await clinician.inject({ method: 'GET', url: '/admin/users' })).statusCode).toBe(403);
    expect((await clinician.inject({ method: 'GET', url: '/admin/audit' })).statusCode).toBe(403);
    // but a clinician can still view stats + patient health
    expect((await clinician.inject({ method: 'GET', url: '/admin/stats' })).statusCode).toBe(200);
  });

  it('admin can list users', async () => {
    const r = await get('/admin/users');
    expect(r.statusCode).toBe(200);
    expect(r.json().total).toBe(1);
    expect(r.json().users[0].displayName).toBe('Aigerim');
  });

  it('401 when staff is unauthenticated', async () => {
    const anon = makeDeps(undefined, async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/admin/stats' })).statusCode).toBe(401);
  });

  it('patient wellness (sleep/cycle/alerts) is staff-viewable + audited', async () => {
    // Seed the target user's data via the client API (same USER in tests).
    await post('/sleep', { night: '2026-07-15', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25 });
    await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', mood: 'calm', symptoms: [], kicks: 2 } });
    await post('/alerts', { childId: CHILD, kind: 'entered', zoneName: 'School', at: '2026-07-16T09:00:00Z' });

    const r = await get(`/admin/users/${USER}/wellness`);
    expect(r.statusCode).toBe(200);
    expect(r.json().sleep[0].deepMin).toBe(95);
    expect(r.json().days[0].mood).toBe('calm');
    expect(r.json().alerts[0].zoneName).toBe('School');
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string; target: string }) => a.action === 'view_wellness' && a.target === USER)).toBe(true);
  });

  it('a clinician can view wellness but not the audit log', async () => {
    const clinician = makeDeps(undefined, async () => ({ staffId: 'c1', role: 'clinician' as const })).server;
    await clinician.ready();
    expect((await clinician.inject({ method: 'GET', url: `/admin/users/${USER}/wellness` })).statusCode).toBe(200);
    expect((await clinician.inject({ method: 'GET', url: '/admin/audit' })).statusCode).toBe(403);
  });
});
