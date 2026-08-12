/**
 * Frame 11 «Устройства», driven end to end over HTTP against a real memory
 * repository: ingest writes, the back office reads it back.
 *
 * Three verified holes, all of which passed every existing test:
 *
 * 1. `devices.last_seen` and `devices.battery_pct` were SELECTed by the fleet
 *    view and written by NOTHING. There was no `UPDATE devices SET last_seen`
 *    anywhere in the repository, so «последний сигнал» was empty for every
 *    device that has ever been paired — an operator could not tell a flat
 *    watch from one that had never once reported.
 * 2. `firmware` was declared in the schema, SELECTed nowhere, and shown
 *    nowhere.
 * 3. `Repository.listWearableDays` — steps, distance, calories, stress,
 *    breathing rate, MET, wear state, the watch's own battery — was
 *    implemented in both repositories with no caller at all.
 *
 * So each test here goes in one end and comes out the other: POST /ingest/batch
 * the way the phone does, then GET the back-office route the panel calls.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

const USER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const BAND = 'AA:BB:CC:DD:EE:01';
const SILENT = 'AA:BB:CC:DD:EE:02';

let app: FastifyInstance;
let repo: Repository;
let cookie: string;

const REASON = 'жалоба на часы';

const snapshot = (extra: Record<string, unknown> = {}) => ({
  deviceId: BAND,
  day: '2026-07-21',
  recordedAt: '2026-07-21T14:00:00.000Z',
  steps: 6480, kcal: 320, meters: 4600,
  sleepMinutes: 445, deepSleepMinutes: 95, lightSleepMinutes: 280,
  stress: 42, breathRate: 16, met: 3,
  batteryPercent: 78, charging: false, worn: true,
  ...extra,
});

const post = (items: unknown[]) =>
  app.inject({ method: 'POST', url: '/ingest/batch', payload: { items } });

const fleet = () =>
  app.inject({ method: 'GET', url: '/admin/devices', headers: { cookie } });

beforeEach(async () => {
  repo = createMemoryRepository();
  // Pairing, as the app does it: the id registered is the id every later
  // reading is stamped with.
  await repo.createDevice(USER, { id: BAND, name: 'GTS10', kind: 'band', childId: null });
  await repo.createDevice(USER, { id: SILENT, name: 'Трекер', kind: 'tag', childId: null });
  app = buildServer({
    repo,
    guardrail: { callLLM: async () => 'ok' },
    ingest: {
      cacheLocation: async () => {},
      resolveTransition: async () => null,
      sendEmergencyPush: async () => {},
      sendGeofencePush: async () => {},
    },
    cacheLastLocation: async () => null,
    setBpCalibration: async () => {},
    authUser: async () => ({ userId: USER }),
    authAdmin: async (req: { headers: { cookie?: string } }) => {
      const token = readSessionCookie(req.headers.cookie);
      if (!token) return null;
      return repo.staffBySessionToken(hashToken(token));
    },
  } as never);
  await app.ready();
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});
afterEach(async () => { await app.close(); });

describe('a device that talks to us says so in the fleet view', () => {
  it('stamps «последний сигнал» when a reading arrives', async () => {
    const before = await fleet();
    expect(before.json().devices.find((d: { id: string }) => d.id === BAND).lastSeen)
      .toBeNull();

    await post([{
      type: 'telemetry',
      payload: { deviceId: BAND, recordedAt: '2026-07-21T08:00:00.000Z', heartRateBpm: 88 },
    }]);

    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.lastSeen, 'nothing wrote last_seen — the column the panel prints').not.toBeNull();
    // Stamped with ARRIVAL, not the reading's own recordedAt: a phone draining
    // a three-day offline queue is talking to us right now.
    expect(Date.now() - Date.parse(row.lastSeen)).toBeLessThan(60_000);
  });

  it('records the battery and firmware the payload carries', async () => {
    await post([{
      type: 'telemetry',
      payload: {
        deviceId: BAND, recordedAt: '2026-07-21T08:00:00.000Z', heartRateBpm: 88,
        battery: 64, firmware: 'v1.4.2',
      },
    }]);
    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.batteryPct, 'zod was stripping `battery` before any handler saw it').toBe(64);
    expect(row.firmware).toBe('v1.4.2');
  });

  it('takes the battery off the watch snapshot too — that is where it comes from today', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);
    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.batteryPct).toBe(78);
    expect(row.lastSeen).not.toBeNull();
  });

  it('leaves what a payload does not carry alone instead of blanking it', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);           // battery 78
    await post([{                                                      // no battery at all
      type: 'telemetry',
      payload: { deviceId: BAND, recordedAt: '2026-07-21T09:00:00.000Z', heartRateBpm: 90 },
    }]);
    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.batteryPct, 'a reading with no battery erased the last known one').toBe(78);
  });

  it('says nothing about a device that has never reported', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);
    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === SILENT);
    // Null, so the panel can print «ни разу не выходило на связь» in words. A
    // zero battery or an invented timestamp would both be lies.
    expect(row.lastSeen).toBeNull();
    expect(row.batteryPct).toBeNull();
    expect(row.firmware).toBeNull();
  });

  it('sends the threshold «на связи» is derived from, so the panel cannot disagree', async () => {
    const body = (await fleet()).json();
    expect(body.onlineWithinHours).toBeGreaterThan(0);
    expect(body.staleAfterDays).toBeGreaterThan(0);
  });
});

describe('«Пометить браком»', () => {
  const rowIdOf = async (mac: string) =>
    (await fleet()).json().devices.find((d: { id: string }) => d.id === mac).deviceId;

  it('marks the device, with who and why, and reads back', async () => {
    const id = await rowIdOf(BAND);
    const res = await app.inject({
      method: 'POST', url: `/admin/devices/${encodeURIComponent(id)}/defect`,
      headers: { cookie }, payload: { defect: true, note: 'не заряжается' },
    });
    expect(res.statusCode).toBe(200);

    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.defectAt).not.toBeNull();
    expect(row.defectNote).toBe('не заряжается');
    expect(row.defectBy).toBe('staff-dev');
  });

  it('can be taken back — the commonest reason to mark something is a mistake', async () => {
    const id = await rowIdOf(BAND);
    const mark = (defect: boolean) => app.inject({
      method: 'POST', url: `/admin/devices/${encodeURIComponent(id)}/defect`,
      headers: { cookie }, payload: { defect, note: defect ? 'ошибся' : '' },
    });
    await mark(true);
    await mark(false);
    const row = (await fleet()).json().devices.find((d: { id: string }) => d.id === BAND);
    expect(row.defectAt).toBeNull();
    expect(row.defectNote).toBeNull();
  });

  it('refuses a device it does not have rather than reporting a save', async () => {
    // The failure this guards: `ok: true` over an UPDATE that matched no row,
    // and a tick in the panel over a mark nobody stored.
    const res = await app.inject({
      method: 'POST', url: '/admin/devices/no-such-device/defect',
      headers: { cookie }, payload: { defect: true },
    });
    expect(res.statusCode).toBe(404);
  });

  it('is written to the action log under the name of whoever did it', async () => {
    const id = await rowIdOf(BAND);
    await app.inject({
      method: 'POST', url: `/admin/devices/${encodeURIComponent(id)}/defect`,
      headers: { cookie }, payload: { defect: true, note: 'экран треснул' },
    });
    const log = await app.inject({ method: 'GET', url: '/admin/audit', headers: { cookie } });
    const rows = log.json().audit ?? log.json().entries ?? [];
    const entry = rows.find((a: { action: string }) => a.action === 'device_defect');
    expect(entry, 'marking a customer device left no trace').toBeTruthy();
    expect(entry.reason).toBe('экран треснул');
  });

  it('is refused to a signed-out caller', async () => {
    const id = await rowIdOf(BAND);
    const res = await app.inject({
      method: 'POST', url: `/admin/devices/${encodeURIComponent(id)}/defect`,
      payload: { defect: true },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe('what the watch has actually been sending', () => {
  it('reaches the back office at all — this route did not exist', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);
    const res = await app.inject({
      method: 'GET',
      url: `/admin/users/${USER}/wearable?reason=${encodeURIComponent(REASON)}`,
      headers: { cookie },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.window).toBeGreaterThan(0);
    expect(body.days).toHaveLength(1);
    expect(body.days[0]).toMatchObject({
      deviceId: BAND, day: '2026-07-21', steps: 6480, meters: 4600,
      stress: 42, breathRate: 16, met: 3, batteryPercent: 78, worn: true,
    });
  });

  it('keeps an unmeasured indicator unmeasured', async () => {
    const { stress: _s, breathRate: _b, met: _m, ...partial } = snapshot();
    await post([{ type: 'wearable', payload: partial }]);
    const body = (await app.inject({
      method: 'GET',
      url: `/admin/users/${USER}/wearable?reason=${encodeURIComponent(REASON)}`,
      headers: { cookie },
    })).json();
    // 0 read back would be "perfectly calm", which is a measurement nobody took.
    expect(body.days[0].stress ?? null).toBeNull();
    expect(body.days[0].breathRate ?? null).toBeNull();
    expect(body.days[0].met ?? null).toBeNull();
  });

  it('answers with an empty window rather than another family\'s days', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);
    const body = (await app.inject({
      method: 'GET',
      url: `/admin/users/${OTHER}/wearable?reason=${encodeURIComponent(REASON)}`,
      headers: { cookie },
    })).json();
    expect(body.days).toEqual([]);
  });

  it('will not serve it without a reason for the log', async () => {
    const res = await app.inject({
      method: 'GET', url: `/admin/users/${USER}/wearable?reason=ok`, headers: { cookie },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('reason_required');
  });

  it('records who looked, at whom, and why', async () => {
    await app.inject({
      method: 'GET',
      url: `/admin/users/${USER}/wearable?reason=${encodeURIComponent(REASON)}`,
      headers: { cookie },
    });
    const log = await app.inject({ method: 'GET', url: '/admin/audit', headers: { cookie } });
    const rows = log.json().audit ?? log.json().entries ?? [];
    const entry = rows.find((a: { action: string }) => a.action === 'view_wearable');
    expect(entry, 'a read of her activity history recorded nobody').toBeTruthy();
    expect(entry.target).toBe(USER);
    expect(entry.reason).toBe(REASON);
  });

  it('is refused to a signed-out caller', async () => {
    const res = await app.inject({
      method: 'GET', url: `/admin/users/${USER}/wearable?reason=${encodeURIComponent(REASON)}`,
    });
    expect(res.statusCode).toBe(401);
  });
});
