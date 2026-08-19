/**
 * Two mothers, one date. Does each read back her own?
 *
 * The in-memory repository is what the whole product runs on in development
 * and what almost every test in this folder is written against — so a fake
 * that ignores the user id does not merely give a developer somebody else's
 * numbers. It makes a whole class of bug UNTESTABLE: no "did we scope this to
 * the right user" assertion written against it could ever fail.
 *
 * Eight methods took `(_u, …)` and ignored it, and one of them was a WRITE.
 * `upsertDayLog` keyed the map on the DATE alone while Postgres upserts ON
 * CONFLICT (user_id, log_date), so the second mother to save her diary for 15
 * July DESTROYED the first mother's entry — her mood, her symptoms and the note
 * she typed — and every later read served the wrong woman's day. The four
 * sibling writes (sleep, weight, kick and contraction sessions) upserted on the
 * night, the date and the instant with the same omission, and the alert feed
 * plus `setAlertOutcome` let one family read and CLOSE another family's alarm.
 *
 * The shape here is deliberately the honest one: both mothers write the SAME
 * key, and each then reads back her own value. Two writes to two different
 * dates would pass against the broken fake and prove nothing.
 *
 * Over HTTP, against a real memory repository, through the routes the app
 * actually calls — because that is the chain that has to hold, not the method.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;
let app: FastifyInstance;
/** Aigerim and Dana — two accounts the repository genuinely created. */
let A: string;
let B: string;

beforeEach(async () => {
  repo = createMemoryRepository();
  A = (await repo.createUserWithPhone({ phone: '77011111111', displayName: 'Айгерим' })).id;
  B = (await repo.createUserWithPhone({ phone: '77022222222', displayName: 'Дана' })).id;
  expect(A).not.toBe(B); // the fake really does mint distinct accounts

  app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      // Whichever mother the request says she is. One server, two sessions —
      // which is what a shared backend is.
      authUser: async (req) => {
        const id = req.headers['x-test-user'];
        return typeof id === 'string' && id ? { userId: id } : null;
      },
      authAdmin: async () => null,
    },
    { logger: false },
  );
});

const as = (userId: string) => ({ 'x-test-user': userId });

async function post(userId: string, url: string, payload: unknown) {
  const res = await app.inject({ method: 'POST', url, payload, headers: as(userId) });
  // The write is asserted, not assumed: a 400 from a schema change would
  // otherwise leave both reads empty and the isolation check vacuously green.
  expect(res.statusCode, `POST ${url}: ${res.body}`).toBe(201);
  return res;
}

async function put(userId: string, url: string, payload: unknown) {
  const res = await app.inject({ method: 'PUT', url, payload, headers: as(userId) });
  expect(res.statusCode, `PUT ${url}: ${res.body}`).toBe(200);
  return res;
}

async function get(userId: string, url: string) {
  const res = await app.inject({ method: 'GET', url, headers: as(userId) });
  expect(res.statusCode, `GET ${url}: ${res.body}`).toBe(200);
  return res.json();
}

const NIGHT = '2026-07-15T00:00:00.000Z';
const DATE = '2026-07-15';
const AT = '2026-07-15T08:00:00.000Z';

describe('two mothers, the same date — each reads back her own', () => {
  it('POST/GET /sleep — the second night does not overwrite the first', async () => {
    await post(A, '/sleep', { night: NIGHT, deepMin: 60, remMin: 50, lightMin: 240, awakeMin: 10 });
    await post(B, '/sleep', { night: NIGHT, deepMin: 11, remMin: 12, lightMin: 13, awakeMin: 14 });

    const a = (await get(A, '/sleep')).nights;
    const b = (await get(B, '/sleep')).nights;
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    expect(a[0].deepMin).toBe(60);
    expect(b[0].deepMin).toBe(11);
    // The row the interface promises, and not a field it does not.
    expect(a[0]).not.toHaveProperty('userId');
  });

  it('POST/GET /weight — the same date, two women, two weights', async () => {
    await post(A, '/weight', { date: DATE, kg: 68.4 });
    await post(B, '/weight', { date: DATE, kg: 55.1 });

    expect((await get(A, '/weight')).entries).toEqual([{ date: DATE, kg: 68.4 }]);
    expect((await get(B, '/weight')).entries).toEqual([{ date: DATE, kg: 55.1 }]);
  });

  it('POST/GET /kick-sessions — the same instant, two counts', async () => {
    await post(A, '/kick-sessions', { endedAt: AT, count: 10, durationSec: 600 });
    await post(B, '/kick-sessions', { endedAt: AT, count: 3, durationSec: 120 });

    expect((await get(A, '/kick-sessions')).sessions)
      .toEqual([{ endedAt: AT, count: 10, durationSec: 600 }]);
    expect((await get(B, '/kick-sessions')).sessions)
      .toEqual([{ endedAt: AT, count: 3, durationSec: 120 }]);
  });

  it('POST/GET /contraction-sessions — one woman in labour is not the other', async () => {
    await post(A, '/contraction-sessions',
      { endedAt: AT, count: 12, avgDurationSec: 55, avgIntervalSec: 300 });
    await post(B, '/contraction-sessions',
      { endedAt: AT, count: 2, avgDurationSec: 20, avgIntervalSec: 900 });

    expect((await get(A, '/contraction-sessions')).sessions)
      .toEqual([{ endedAt: AT, count: 12, avgDurationSec: 55, avgIntervalSec: 300 }]);
    expect((await get(B, '/contraction-sessions')).sessions)
      .toEqual([{ endedAt: AT, count: 2, avgDurationSec: 20, avgIntervalSec: 900 }]);
  });

  it('PUT/GET /cycle/days — the destructive one: her diary survives the other woman saving hers', async () => {
    await put(A, '/cycle/days',
      { date: DATE, mood: 'calm', symptoms: ['cramps'], kicks: 4, flow: 'light', note: 'Айгерим' });
    await put(B, '/cycle/days',
      { date: DATE, mood: 'sad', symptoms: ['nausea'], kicks: 0, flow: 'heavy', note: 'Дана' });

    const window = `?from=${DATE}&to=${DATE}`;
    const a = (await get(A, `/cycle/days${window}`)).days;
    const b = (await get(B, `/cycle/days${window}`)).days;
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    expect(a[0].note).toBe('Айгерим');
    expect(a[0].mood).toBe('calm');
    expect(a[0].symptoms).toEqual(['cramps']);
    expect(b[0].note).toBe('Дана');
    expect(b[0].mood).toBe('sad');
    expect(a[0]).not.toHaveProperty('userId');
  });

  it('POST/GET /alerts — one family does not see the other family’s SOS', async () => {
    await post(A, '/alerts', { childId: 'child-a', kind: 'sos', zoneName: '', at: AT });
    await post(B, '/alerts', { childId: 'child-b', kind: 'sos', zoneName: '', at: AT });

    const a = (await get(A, '/alerts')).alerts;
    const b = (await get(B, '/alerts')).alerts;
    expect(a).toHaveLength(1);
    expect(b).toHaveLength(1);
    expect(a[0].childId).toBe('child-a');
    expect(b[0].childId).toBe('child-b');
    expect(a[0]).not.toHaveProperty('userId');
  });

  it('the filters that sit beside the user check still apply to her own rows', async () => {
    // Scoping by user must not have replaced the range filter next to it.
    await put(A, '/cycle/days',
      { date: '2026-06-01', mood: 'calm', symptoms: [], kicks: 0, flow: null, note: 'июнь' });
    await put(A, '/cycle/days',
      { date: DATE, mood: 'calm', symptoms: [], kicks: 0, flow: null, note: 'июль' });

    const july = (await get(A, `/cycle/days?from=2026-07-01&to=2026-07-31`)).days;
    expect(july).toHaveLength(1);
    expect(july[0].note).toBe('июль');
  });
});

describe('setAlertOutcome is scoped to the mother, not just the child', () => {
  // Not over HTTP: POST /children/:id/day/outcome resolves the owner with
  // repo.childOwner and passes THAT id, so the route can only ever call this
  // with the alert's own user. The cross-user attempt the fix defends against
  // is reachable at the repository — which is where the next caller of this
  // method will reach it too.
  it('one family cannot close another family’s alarm', async () => {
    await repo.recordAlert(A, { childId: 'child-a', kind: 'sos', zoneName: '', at: AT });
    await repo.recordAlert(B, { childId: 'child-a', kind: 'sos', zoneName: '', at: AT });

    // Dana closes hers. Aigerim's, at the same instant and even under the same
    // child id, must be untouched and still open.
    expect(await repo.setAlertOutcome(B, 'child-a', AT, 'false_press')).toBe(true);
    expect((await repo.listAlerts(A, 10))[0].outcome ?? null).toBeNull();
    expect((await repo.listAlerts(B, 10))[0].outcome).toBe('false_press');

    // And a mother with no such alarm gets a miss, not a silent success — the
    // route turns `false` into a 404 rather than a tick over nothing.
    const C = (await repo.createUserWithPhone({ phone: '77033333333', displayName: 'Сауле' })).id;
    expect(await repo.setAlertOutcome(C, 'child-a', AT, 'false_press')).toBe(false);
  });
});

describe('erasing one account does not erase the other', () => {
  it('deleteAccount takes her rows and leaves everybody else’s', async () => {
    // These stores hold every account's rows now, so the truncating erasure
    // that was correct while they held one account's would wipe the others —
    // a fake that deletes MORE than ON DELETE CASCADE does.
    await repo.recordWeight(DEMO_USER, { date: DATE, kg: 70 });
    await repo.recordSleep(DEMO_USER, { night: NIGHT, deepMin: 1, remMin: 1, lightMin: 1, awakeMin: 1 });
    await repo.recordKickSession(DEMO_USER, { endedAt: AT, count: 1, durationSec: 60 });
    await repo.upsertDayLog(DEMO_USER,
      { date: DATE, mood: 'tired', symptoms: [], kicks: 0, flow: null, note: 'demo' });
    await repo.recordAlert(DEMO_USER, { childId: 'child-d', kind: 'sos', zoneName: '', at: AT });

    await repo.recordWeight(A, { date: DATE, kg: 68.4 });
    await repo.recordSleep(A, { night: NIGHT, deepMin: 60, remMin: 50, lightMin: 240, awakeMin: 10 });
    await repo.recordKickSession(A, { endedAt: AT, count: 10, durationSec: 600 });
    await repo.upsertDayLog(A,
      { date: DATE, mood: 'calm', symptoms: [], kicks: 0, flow: null, note: 'Айгерим' });
    await repo.recordAlert(A, { childId: 'child-a', kind: 'sos', zoneName: '', at: AT });

    expect(await repo.deleteAccount(DEMO_USER)).toBe(true);

    expect(await repo.listWeight(DEMO_USER, 10)).toEqual([]);
    expect(await repo.listSleep(DEMO_USER, 10)).toEqual([]);
    expect(await repo.listKickSessions(DEMO_USER, 10)).toEqual([]);
    expect(await repo.listDayLogs(DEMO_USER, DATE, DATE)).toEqual([]);
    expect(await repo.listAlerts(DEMO_USER, 10)).toEqual([]);

    expect(await repo.listWeight(A, 10)).toEqual([{ date: DATE, kg: 68.4 }]);
    expect(await repo.listSleep(A, 10)).toHaveLength(1);
    expect(await repo.listKickSessions(A, 10)).toHaveLength(1);
    expect((await repo.listDayLogs(A, DATE, DATE))[0].note).toBe('Айгерим');
    expect(await repo.listAlerts(A, 10)).toHaveLength(1);
  });
});
