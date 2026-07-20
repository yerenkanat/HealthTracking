/**
 * Authorization: authentication is not authorization.
 *
 * Every route below already required a logged-in user, which is easy to mistake
 * for being safe. But most child-scoped routes took the child id straight from
 * the URL and never checked that the child belongs to the CALLER — so any
 * account could read or delete another family's data by supplying their id.
 * And /children/:id/location, the endpoint that answers "where is this child
 * right now", had no auth check at all.
 *
 * These tests drive the real server with two different signed-in users.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { InjectPayload, Response as InjectResponse } from 'light-my-request';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import type { Geofence } from '@fcs/shared';

const ALICE = '11111111-1111-1111-1111-111111111111';
const MALLORY = '99999999-9999-9999-9999-999999999999';

/** Alice's child. Mallory is a legitimate user of the app — just not the parent. */
const ALICE_CHILD = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const ALICE_DEVICE = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const ALICE_FENCE = 'ffffffff-ffff-ffff-ffff-ffffffffffff';

const HOME: Geofence = {
  id: ALICE_FENCE,
  name: 'Home',
  shape: 'circle',
  center: { lat: 43.238949, lng: 76.889709 },
  radiusM: 100,
};

function makeApp(callerId: string) {
  const children = new Map<string, string>([[ALICE_CHILD, ALICE]]);
  const devices = new Map<string, string>([[ALICE_DEVICE, ALICE], ['mallory-device', MALLORY]]);
  const deleted: string[] = [];

  const repo = {
    childOwner: async (childId: string) =>
      children.has(childId) ? { userId: children.get(childId)! } : null,
    deviceOwner: async (deviceId: string) =>
      devices.has(deviceId) ? { userId: devices.get(deviceId)! } : null,
    geofenceOwner: async (fenceId: string) =>
      fenceId === ALICE_FENCE ? { userId: ALICE } : null,
    loadGeofences: async () => [HOME],
    createGeofence: async (_c: string, g: Geofence) => ({ ...g, id: 'new' }),
    deleteGeofence: async (id: string) => void deleted.push(`fence:${id}`),
    deleteChild: async (id: string) => void deleted.push(`child:${id}`),
    deleteDevice: async (id: string) => void deleted.push(`device:${id}`),
    listGeofenceEvents: async () => [{ childName: 'Sultan', transition: 'enter' }],
    listChildren: async () => [],
    listDevices: async () => [],
    createChild: async () => ({ id: 'c', name: 'n' }),
    createDevice: async () => {},
    insertHealthMetric: async () => {},
    insertBpCalibration: async () => {},
    insertGeofenceEvent: async () => {},
    insertLocation: async () => {},
    guardianPushTokens: async () => ({ tokens: [], childName: '' }),
    guardianPushTokensForUser: async () => [],
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [],
    queryMetrics: async () => [],
    recordSleep: async () => {},
    listSleep: async () => [],
    upsertDayLog: async () => {},
    listDayLogs: async () => [],
    recordAlert: async () => {},
    listAlerts: async () => [],
    getProfile: async () => null,
    upsertProfile: async () => {},
    reassignDevice: async () => {},
    adminStats: async () => ({ activeUsers: 0, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }),
    recentEmergencies: async () => [],
    adminListUsers: async () => ({ total: 0, users: [] }),
    adminUserHealth: async () => null,
    writeAudit: async () => {},
    listAudit: async () => [],
  } as unknown as Repository;

  const server = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => ({ lat: 43.238949, lng: 76.889709, at: '2026-07-20T08:00:00Z' }),
      setBpCalibration: async () => {},
      authUser: async () => (callerId ? { userId: callerId } : null),
      authAdmin: async () => null,
    },
    { logger: false },
  );
  return { server, deleted };
}

let app: FastifyInstance;
let deleted: string[];
const get = (url: string): Promise<InjectResponse> => app.inject({ method: 'GET', url });
const post = (url: string, payload: InjectPayload): Promise<InjectResponse> =>
  app.inject({ method: 'POST', url, payload });
const del = (url: string): Promise<InjectResponse> => app.inject({ method: 'DELETE', url });

describe("a signed-in user cannot reach another family's child", () => {
  beforeEach(async () => {
    const made = makeApp(MALLORY); // authenticated, but NOT the parent
    app = made.server;
    deleted = made.deleted;
    await app.ready();
  });

  it("cannot read the child's geofences", async () => {
    expect((await get(`/children/${ALICE_CHILD}/geofences`)).statusCode).toBe(403);
  });

  it("cannot add a geofence to the child", async () => {
    const r = await post(`/children/${ALICE_CHILD}/geofences`, {
      name: 'Mine', shape: 'circle', center: { lat: 1, lng: 2 }, radiusM: 50,
    });
    expect(r.statusCode).toBe(403);
  });

  it("cannot read the child's movement history", async () => {
    expect((await get(`/children/${ALICE_CHILD}/events`)).statusCode).toBe(403);
  });

  it('cannot delete the child', async () => {
    expect((await del(`/children/${ALICE_CHILD}`)).statusCode).toBe(403);
    expect(deleted).toEqual([]);
  });

  it("cannot delete the child's tracker", async () => {
    expect((await del(`/devices/${ALICE_DEVICE}`)).statusCode).toBe(403);
    expect(deleted).toEqual([]);
  });

  it("cannot delete the child's safe zone", async () => {
    expect((await del(`/geofences/${ALICE_FENCE}`)).statusCode).toBe(403);
    expect(deleted).toEqual([]);
  });

  it('cannot read where the child is right now', async () => {
    expect((await get(`/children/${ALICE_CHILD}/location`)).statusCode).toBe(403);
  });

  it("cannot move somebody else's tracker", async () => {
    const r = await app.inject({
      method: 'PATCH',
      url: `/devices/${ALICE_DEVICE}`,
      payload: { childId: ALICE_CHILD },
    });
    expect(r.statusCode).toBe(403);
  });

  it("cannot attach their own tracker to somebody else's child", async () => {
    // The other direction: owning the DEVICE is not enough if the target child
    // belongs to another family — it would wire a stranger's tracker to them.
    const r = await app.inject({
      method: 'PATCH',
      url: '/devices/mallory-device',
      payload: { childId: ALICE_CHILD },
    });
    expect(r.statusCode).toBe(403);
  });
});

describe('the location endpoint requires authentication at all', () => {
  beforeEach(async () => {
    app = makeApp('').server; // nobody signed in
    await app.ready();
  });

  it('refuses an anonymous request for a child location', async () => {
    // The single most sensitive endpoint in the product: it answers "where is
    // this child". It must never be readable by an unauthenticated caller.
    expect((await get(`/children/${ALICE_CHILD}/location`)).statusCode).toBe(401);
  });
});

describe('write endpoints do not take identity from the request body', () => {
  // These three took a userId (or a device id) straight from the payload with
  // no authentication at all, so any caller could act AS another user.
  beforeEach(async () => {
    app = makeApp('').server; // nobody signed in
    await app.ready();
  });

  it('refuses anonymous telemetry and location ingest', async () => {
    // Unauthenticated ingest lets anyone fabricate a child's position — forging
    // "left school" alerts, or masking a real departure — and inject vitals that
    // trigger a false emergency for the mother.
    const r = await post('/ingest/batch', {
      items: [{
        type: 'location',
        payload: { childId: ALICE_CHILD, coords: { lat: 43.3, lng: 76.9 }, source: 'gps', observedAt: '2026-07-20T08:00:00Z' },
      }],
    });
    expect(r.statusCode).toBe(401);
  });

  it('refuses an anonymous chat request', async () => {
    // The body carried the userId, and the handler looked up that user's
    // emergency contacts and returned them in the response.
    const r = await post('/ai/chat', { userId: ALICE, locale: 'ru', message: 'привет' });
    expect(r.statusCode).toBe(401);
  });

  it('refuses an anonymous blood-pressure calibration write', async () => {
    // Calibration offsets shift every later BP reading, and those readings feed
    // preeclampsia triage — corrupting them can suppress or fabricate an alert.
    const r = await post('/calibration/bp', {
      userId: ALICE, cuffSystolic: 180, cuffDiastolic: 120,
      ppgSystolic: 110, ppgDiastolic: 70, measuredAt: '2026-07-20T08:00:00Z',
    });
    expect(r.statusCode).toBe(401);
  });
});

describe('a signed-in user cannot act as somebody else', () => {
  beforeEach(async () => {
    app = makeApp(MALLORY).server;
    await app.ready();
  });

  it('cannot request chat as another user', async () => {
    const r = await post('/ai/chat', { userId: ALICE, locale: 'ru', message: 'привет' });
    expect(r.statusCode).toBe(403);
  });

  it('cannot write calibration for another user', async () => {
    const r = await post('/calibration/bp', {
      userId: ALICE, cuffSystolic: 180, cuffDiastolic: 120,
      ppgSystolic: 110, ppgDiastolic: 70, measuredAt: '2026-07-20T08:00:00Z',
    });
    expect(r.statusCode).toBe(403);
  });

  it("cannot ingest location for another family's child", async () => {
    const r = await post('/ingest/batch', {
      items: [{
        type: 'location',
        payload: { childId: ALICE_CHILD, coords: { lat: 43.3, lng: 76.9 }, source: 'gps', observedAt: '2026-07-20T08:00:00Z' },
      }],
    });
    // Accepted-but-ignored is fine; silently RECORDING it is not.
    const body = r.statusCode === 200 ? (r.json() as { locationCount: number; rejected: number }) : null;
    expect(body === null || body.locationCount === 0).toBe(true);
  });
});

describe('the real parent still has full access', () => {
  beforeEach(async () => {
    const made = makeApp(ALICE);
    app = made.server;
    deleted = made.deleted;
    await app.ready();
  });

  it('reads geofences', async () => {
    expect((await get(`/children/${ALICE_CHILD}/geofences`)).statusCode).toBe(200);
  });

  it('reads the location', async () => {
    expect((await get(`/children/${ALICE_CHILD}/location`)).statusCode).toBe(200);
  });

  it('reads movement history', async () => {
    expect((await get(`/children/${ALICE_CHILD}/events`)).statusCode).toBe(200);
  });

  it('deletes their own child, device and zone', async () => {
    expect((await del(`/children/${ALICE_CHILD}`)).statusCode).toBe(204);
    expect((await del(`/devices/${ALICE_DEVICE}`)).statusCode).toBe(204);
    expect((await del(`/geofences/${ALICE_FENCE}`)).statusCode).toBe(204);
    expect(deleted).toHaveLength(3);
  });
});
