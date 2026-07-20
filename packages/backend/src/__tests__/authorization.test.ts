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
  const devices = new Map<string, string>([[ALICE_DEVICE, ALICE]]);
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
