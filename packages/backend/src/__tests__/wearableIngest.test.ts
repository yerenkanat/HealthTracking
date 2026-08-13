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

/**
 * A DAY the watch had stored, read back off the device after the fact.
 *
 * The live snapshot could only ever describe the minutes the app was open. The
 * watch keeps about a week of samples on the device itself and the vendor
 * documents a read command per metric (UniappSDKDocumentation.md §5.44–5.53,
 * §5.58); the app now walks them. A backfilled day therefore carries the vitals
 * as well as the activity — and until migration 042 not one of the five had a
 * column, so the sync could have restored how far she walked last Tuesday and
 * would have had to throw away what her heart was doing while she did it.
 */
const backfilled = (extra: Record<string, unknown> = {}) => ({
  ...snapshot(),
  day: '2026-07-19',
  recordedAt: '2026-07-19T23:59:59.000Z',
  heartRateAvg: 71,
  heartRateMin: 54,
  heartRateMax: 132,
  spo2Avg: 97,
  spo2Min: 93,
  systolicAvg: 116,
  diastolicAvg: 74,
  tempAvgTenths: 366,
  bloodSugarTenths: 52,
  // The history says nothing about the watch's battery today.
  batteryPercent: undefined,
  charging: false,
  worn: false,
  ...extra,
});

describe('a day backfilled from the watch', () => {
  it('keeps every vital it carries, all the way into the repository', async () => {
    const res = await post([{ type: 'wearable', payload: backfilled() }]);
    expect(res.json()).toMatchObject({ wearableCount: 1, rejected: 0 });

    const [day] = await repo.listWearableDays(USER, 10);
    // Named one by one on purpose. Zod strips keys the schema does not declare,
    // so a field added to the app and forgotten here reaches the server, gets a
    // 200, and vanishes — which is the exact shape of the defect this whole
    // change exists to close.
    expect(day).toMatchObject({
      day: '2026-07-19',
      heartRateAvg: 71,
      heartRateMin: 54,
      heartRateMax: 132,
      spo2Avg: 97,
      spo2Min: 93,
      systolicAvg: 116,
      diastolicAvg: 74,
      tempAvgTenths: 366,
      bloodSugarTenths: 52,
    });
  });

  it('re-syncing the same day updates it rather than duplicating it', async () => {
    // The backfill runs on every fresh connection, and a watch that reconnects
    // four times on a bus journey would otherwise write four rows for Sunday —
    // and the clinician's view would show the same day four times over.
    await post([{ type: 'wearable', payload: backfilled() }]);
    await post([{ type: 'wearable', payload: backfilled() }]);
    await post([
      { type: 'wearable', payload: backfilled({ steps: 9100, heartRateMax: 148 }) },
    ]);

    const days = await repo.listWearableDays(USER, 10);
    expect(days.filter((d) => d.day === '2026-07-19')).toHaveLength(1);
    const [day] = days.filter((d) => d.day === '2026-07-19');
    // The later read wins — a longer walk really did happen.
    expect(day.steps).toBe(9100);
    expect(day.heartRateMax).toBe(148);
  });

  it('a week of backfill is a week of rows, one per day', async () => {
    const week = [];
    for (let d = 13; d <= 19; d++) {
      week.push({
        type: 'wearable',
        payload: backfilled({ day: `2026-07-${d}`, recordedAt: `2026-07-${d}T23:59:59.000Z` }),
      });
    }
    // Sent twice — the second connection re-reads the same week.
    await post(week);
    const res = await post(week);
    expect(res.json()).toMatchObject({ wearableCount: 7, rejected: 0 });

    const days = await repo.listWearableDays(USER, 30);
    expect(days).toHaveLength(7);
    expect(days.map((d) => d.day)).toEqual([
      '2026-07-19', '2026-07-18', '2026-07-17',
      '2026-07-16', '2026-07-15', '2026-07-14', '2026-07-13',
    ]);
  });

  it('a metric the watch never measured stays null, not zero', async () => {
    const { heartRateAvg: _a, heartRateMin: _b, heartRateMax: _c, spo2Avg: _d,
            spo2Min: _e, tempAvgTenths: _f, bloodSugarTenths: _g, ...noVitals } = backfilled();
    await post([{ type: 'wearable', payload: noVitals }]);
    const [day] = await repo.listWearableDays(USER, 10);
    expect(day.heartRateAvg ?? null).toBeNull();
    expect(day.spo2Avg ?? null).toBeNull();
    expect(day.tempAvgTenths ?? null).toBeNull();
    expect(day.bloodSugarTenths ?? null).toBeNull();
    // …and the day is still stored: a day of walking with no heart rate in it
    // is a real day.
    expect(day.steps).toBe(6480);
  });

  it('drops one mis-decoded metric instead of rejecting the day for ever', async () => {
    // A byte read at the wrong offset lands outside human physiology. Rejecting
    // the batch would make the phone resend the same day until the battery ran
    // out; the day is stored with that one metric absent, which is the truth.
    const res = await post([
      { type: 'wearable', payload: backfilled({ heartRateAvg: 5, spo2Avg: 3 }) },
    ]);
    expect(res.json()).toMatchObject({ wearableCount: 1, rejected: 0 });
    const [day] = await repo.listWearableDays(USER, 10);
    expect(day.heartRateAvg ?? null).toBeNull();
    expect(day.spo2Avg ?? null).toBeNull();
    expect(day.heartRateMax).toBe(132); // the plausible ones survived
    expect(day.steps).toBe(6480);
  });
});
