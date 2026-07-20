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
) {
  const events: GeofenceEvent[] = [];
  const pushes = { emergency: 0, geofence: 0 };
  const healthRows: unknown[] = [];
  const calRows: unknown[] = [];
  let lastLocation: ChildLocationFix | null = null;
  const fenceState = new Map<string, 'in' | 'out'>(); // real Redis-like dedup

  // In-memory CRUD state
  const children: Array<{ id: string; name: string }> = [];
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null }> = [];
  const geofences = new Map<string, import('@fcs/shared').Geofence[]>();
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
  const sleepRows: SleepNight[] = [];
  const dayLogs = new Map<string, DayLogRow>();
  const alertRows: SafetyAlertRow[] = [];
  const contentRows = new Map<string, import('../db/repository').ContentItemRow[]>();
  let profile: ProfileRow | null = null;
  let idSeq = 1;

  const repo: Repository = {
    insertHealthMetric: async (m) => void healthRows.push(m),
    insertBpCalibration: async (_u, c) => void calRows.push(c),
    loadGeofences: async (childId) =>
      childId === CHILD ? [HOME, ...(geofences.get(childId) ?? [])] : (geofences.get(childId) ?? []),
    insertGeofenceEvent: async (e) => void events.push(e),
    insertLocation: async () => {},
    guardianPushTokens: async () => ({ tokens: ['t'], childName: 'Sultan' }),
    guardianPushTokensForUser: async () => ['t'],
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
    listChildren: async () => children.map((c) => ({ ...c })),
    createChild: async (_u, name) => {
      const c = { id: `child-${idSeq++}`, name };
      children.push(c);
      return c;
    },
    deleteChild: async (id) => {
      const i = children.findIndex((c) => c.id === id);
      if (i >= 0) children.splice(i, 1);
    },
    listDevices: async () => devices.map((d) => ({ ...d })),
    createDevice: async (_u, d) => void devices.push({ ...d, childId: d.childId ?? null }),
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
    },
    createGeofence: async (childId, g) => {
      const withId = { ...g, id: `gf-${idSeq++}` };
      geofences.set(childId, [...(geofences.get(childId) ?? []), withId]);
      return withId;
    },
    deleteGeofence: async () => {},
    queryMetrics: async () => [{ t: '2026-07-15T08:00:00Z', value: 72 }, { t: '2026-07-15T08:05:00Z', value: 80 }],
    listGeofenceEvents: async () => events.filter((e) => e.transition),
    // Sleep
    recordSleep: async (_u, s) => {
      const i = sleepRows.findIndex((x) => x.night === s.night);
      if (i >= 0) sleepRows[i] = s; else sleepRows.push(s);
    },
    listSleep: async (_u, limit) => [...sleepRows].sort((a, b) => b.night.localeCompare(a.night)).slice(0, limit),
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
    // Admin
    adminStats: async () => ({ activeUsers: 1, devicesOnline: devices.length, alertsToday: pushes.emergency, ingestLastHour: healthRows.length }),
    recentEmergencies: async () => [{ userId: USER, displayName: 'Aigerim', code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00Z' }],
    adminListUsers: async () => ({ total: 1, users: [{ id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01' }] }),
    adminUserHealth: async (userId) =>
      userId === USER ? { latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 }, triage: [{ code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00Z' }] } : null,
    adminUserDetail: async (userId) =>
      userId === USER
        ? {
            id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01', locale: 'ru-KZ',
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

describe('CRUD + history routes (in-process)', () => {
  it('children: create → list → delete', async () => {
    expect((await get('/children')).json().children).toHaveLength(0);
    const created = await post('/children', { name: 'Sultan' });
    expect(created.statusCode).toBe(201);
    const id = created.json().id;
    expect((await get('/children')).json().children).toHaveLength(1);
    const del = await app.inject({ method: 'DELETE', url: `/children/${id}` });
    expect(del.statusCode).toBe(204);
    expect((await get('/children')).json().children).toHaveLength(0);
  });

  it('children: rejects empty name (zod 400)', async () => {
    expect((await post('/children', { name: '' })).statusCode).toBe(400);
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

  it('geofences: create a circle for a child, then list', async () => {
    const r = await post(`/children/${CHILD}/geofences`, {
      name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 80,
    });
    expect(r.statusCode).toBe(201);
    expect(r.json().name).toBe('Park');
    const list = (await get(`/children/${CHILD}/geofences`)).json().geofences;
    expect(list.some((g: { name: string }) => g.name === 'Park')).toBe(true);
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
    const other = (await post('/children', { name: 'Aida' })).json().id as string;
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
