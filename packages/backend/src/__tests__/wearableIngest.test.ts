/**
 * The watch's data, driven over HTTP into the real memory repository.
 *
 * Two defects live on this path and both were invisible from either end alone.
 *
 * 1. Every band reading the app has ever sent was DISCARDED on arrival. The app
 *    stamped readings with a compile-time constant that defaulted to the string
 *    'band-unpaired'; ingest resolves the owner of the named device, finds none,
 *    counts the item `rejected` and returns 200. Unit tests on both sides passed
 *    — the app enqueued, the server answered — and nothing was stored.
 *
 * 2. Everything the watch measures beyond the four triage vitals had nowhere to
 *    go at all. Steps, distance, calories, stress, breathing rate, MET, battery
 *    and the on-wrist flag were parsed, shown on one panel and never sent.
 *
 * So this drives the whole chain: register the device the way pairing does, post
 * what the app posts, and read it back out of the repository.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const USER = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const BAND = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

let app: FastifyInstance;
let repo: Repository;

const snapshot = (extra: Record<string, unknown> = {}) => ({
  deviceId: BAND,
  day: '2026-07-21',
  recordedAt: '2026-07-21T14:00:00.000Z',
  steps: 6480,
  kcal: 320,
  meters: 4600,
  sleepMinutes: 445,
  deepSleepMinutes: 95,
  lightSleepMinutes: 280,
  stress: 42,
  breathRate: 16,
  met: 3,
  batteryPercent: 78,
  charging: false,
  worn: true,
  ...extra,
});

const post = (items: unknown[]) =>
  app.inject({ method: 'POST', url: '/ingest/batch', payload: { items } });

beforeEach(async () => {
  repo = createMemoryRepository();
  // Pairing: the app registers the band it found, and the id it registers is
  // the id it later stamps on every reading. That equality is the whole fix.
  await repo.createDevice(USER, { id: BAND, name: 'GTS10', kind: 'band', childId: null });
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
    authAdmin: async () => null,
  } as never);
  await app.ready();
});
afterEach(async () => { await app.close(); });

describe('a reading from the band she actually paired', () => {
  it('is stored, not rejected', async () => {
    const res = await post([
      {
        type: 'telemetry',
        payload: { deviceId: BAND, recordedAt: '2026-07-21T08:00:00.000Z', heartRateBpm: 88, spo2Pct: 97 },
      },
    ]);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ telemetryCount: 1, rejected: 0 });
  });

  it('is refused when it names a device nobody owns', async () => {
    // Exactly what the app used to send on every single reading.
    const res = await post([
      {
        type: 'telemetry',
        payload: { deviceId: 'band-unpaired', recordedAt: '2026-07-21T08:00:00.000Z', heartRateBpm: 88 },
      },
    ]);
    expect(res.json()).toMatchObject({ telemetryCount: 0, rejected: 1 });
  });
});

describe('the watch activity snapshot', () => {
  it('is stored against the wearer, with every indicator intact', async () => {
    const res = await post([{ type: 'wearable', payload: snapshot() }]);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ wearableCount: 1, rejected: 0 });

    const [day] = await repo.listWearableDays(USER, 10);
    expect(day).toMatchObject({
      deviceId: BAND,
      day: '2026-07-21',
      steps: 6480,
      kcal: 320,
      meters: 4600,
      sleepMinutes: 445,
      deepSleepMinutes: 95,
      lightSleepMinutes: 280,
      stress: 42,
      breathRate: 16,
      met: 3,
      batteryPercent: 78,
      worn: true,
    });
  });

  it('does not invent a reading the watch never took', async () => {
    // The watch reports 0 for a wellness value it has not measured, and the app
    // drops those before sending. Nothing downstream may turn the absence back
    // into a number: a stress of 0 read back is "perfectly calm", not "unknown".
    const { stress: _s, breathRate: _b, met: _m, batteryPercent: _p, ...unmeasured } = snapshot();
    await post([{ type: 'wearable', payload: unmeasured }]);
    const [day] = await repo.listWearableDays(USER, 10);
    expect(day.stress ?? null).toBeNull();
    expect(day.breathRate ?? null).toBeNull();
    expect(day.met ?? null).toBeNull();
    expect(day.batteryPercent ?? null).toBeNull();
  });

  it('updates the day instead of piling up a row per poll', async () => {
    await post([{ type: 'wearable', payload: snapshot() }]);
    await post([{ type: 'wearable', payload: snapshot({ steps: 7000, recordedAt: '2026-07-21T15:00:00.000Z' }) }]);
    const days = await repo.listWearableDays(USER, 10);
    expect(days).toHaveLength(1);
    expect(days[0].steps).toBe(7000);
  });

  it('is refused for a device this account does not own', async () => {
    const res = await post([{ type: 'wearable', payload: snapshot({ deviceId: OTHER }) }]);
    expect(res.json()).toMatchObject({ wearableCount: 0, rejected: 1 });
    expect(await repo.listWearableDays(USER, 10)).toHaveLength(0);
  });

  it('refuses an impossible figure at the edge', async () => {
    const res = await post([{ type: 'wearable', payload: snapshot({ steps: -5 }) }]);
    expect(res.statusCode).toBe(400);
  });
});
