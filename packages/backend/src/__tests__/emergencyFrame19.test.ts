/**
 * Frame 19 «Экстренные», over HTTP against a real memory repository.
 *
 * Two things the feed could not say before, on the screen a duty operator uses
 * to decide whom to ring first:
 *
 *  1. WHY an emergency fired. Both repositories answered `code: 'EMERGENCY'` —
 *     a literal — so every row of the feed read «EMERGENCY», severe-range blood
 *     pressure and a sleeping SpO2 of 89 alike.
 *  2. HOW an SOS ended. `safety_alerts.outcome` has existed since migration 032
 *     and no query selected it, so every closed SOS came back looking open and
 *     the share of false presses could not be computed from the feed at all.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const STAFF = { staffId: 's1', role: 'admin' as const };
const CHILD = 'child-1';

let repo: Repository;
beforeEach(() => {
  repo = createMemoryRepository();
});

function app(): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => STAFF,
    },
    { logger: false },
  );
}

describe('GET /admin/emergencies — the reason, not a placeholder', () => {
  it('names the triage finding and the reading that crossed', async () => {
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: 'u1', recordedAt: '2026-07-15T08:00:00.000Z',
      systolicMmHg: 162, diastolicMmHg: 108, triageSeverity: 'emergency',
    } as never);
    const a = app();
    const feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;

    expect(feed).toHaveLength(1);
    expect(feed[0].code).toBe('PREECLAMPSIA_BP_SEVERE');
    expect(feed[0].code).not.toBe('EMERGENCY');
    // The reading, so the row can print «162/108 · порог 160» rather than a
    // severity word the operator already knows from the colour.
    expect(feed[0].metric).toBe('systolicMmHg');
    expect(feed[0].value).toBe(162);
    expect(feed[0].threshold).toBe(160);
    expect(feed[0].systolic).toBe(162);
    expect(feed[0].diastolic).toBe(108);
    await a.close();
  });

  it('distinguishes the findings — fever, hypoxia and tachycardia are not one word', async () => {
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: 'u1', recordedAt: '2026-07-15T08:00:00.000Z',
      coreTempC: 38.9, triageSeverity: 'emergency',
    } as never);
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: 'u2', recordedAt: '2026-07-15T08:10:00.000Z',
      spo2Pct: 88, duringSleep: true, triageSeverity: 'emergency',
    } as never);
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: 'u3', recordedAt: '2026-07-15T08:20:00.000Z',
      heartRateBpm: 148, triageSeverity: 'emergency',
    } as never);
    const a = app();
    const feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;

    const byUser = Object.fromEntries(
      feed.map((e: { userId: string; code: string }) => [e.userId, e.code]));
    expect(byUser.u2).toBe('HYPOXIA_SEVERE');
    expect(byUser.u3).toBe('TACHYCARDIA_SEVERE');
    // The temperature row is asserted by SHAPE rather than by code. Which code
    // a temperature produces is the clinical owner's to change — it is
    // `DEVICE_TEMP_HIGH` today, because provenance is not a stored column
    // (schema.sql keeps core_temp_c and nothing about how it was taken) so the
    // re-derivation always takes the device branch, in BOTH repositories. What
    // this frame guarantees is that the row names its own metric and is not the
    // literal it used to be.
    expect(byUser.u1).not.toBe('EMERGENCY');
    expect(byUser.u1).toBeTruthy();
    const temp = feed.find((e: { userId: string }) => e.userId === 'u1');
    expect(temp.metric).toBe('coreTempC');
    expect(temp.value).toBeCloseTo(38.9, 5);
    // Three readings, three different reasons — the whole point of the frame.
    expect(new Set(Object.values(byUser)).size).toBe(3);
    // The sleep flag travels: sub-95 asleep and awake are different findings.
    expect(feed.find((e: { userId: string }) => e.userId === 'u2').duringSleep).toBe(true);
    await a.close();
  });

  it('says nothing rather than something when the stored reading explains nothing', async () => {
    // An emergency severity with no vitals behind it — a row from a path that
    // predates a threshold, or one whose columns are empty. Inventing a cause
    // here is worse than admitting there is none.
    await repo.insertHealthMetric({
      deviceId: 'd1', userId: 'u1', recordedAt: '2026-07-15T08:00:00.000Z',
      triageSeverity: 'emergency',
    } as never);
    const a = app();
    const feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;
    expect(feed[0].code).toBe('');
    expect(feed[0].metric).toBeNull();
    expect(feed[0].value).toBeNull();
    await a.close();
  });
});

// The alerts below belong to DEMO_USER, not to a made-up 'demo-user'.
// safety_alerts.user_id is a UUID foreign key to users(id) and
// pgRepository.adminSafetyEvents INNER JOINs users, so an alert owned by an
// account that does not exist cannot be inserted, let alone appear in the feed.
// While the fake ignored the user id it happily served one, attached to the
// demo profile's name and phone — so this file asserted a number the real
// query could never have produced for that row.
describe('GET /admin/safety — how the SOS ended, and who to call', () => {
  it('reads the outcome back after the mother closes it', async () => {
    const at = '2026-07-15T08:00:00.000Z';
    await repo.recordAlert(DEMO_USER, { childId: CHILD, kind: 'sos', zoneName: '', at });
    const a = app();

    let events = (await a.inject({ method: 'GET', url: '/admin/safety' })).json().events;
    expect(events).toHaveLength(1);
    // Open: null, which the panel renders as «мама ещё не закрыла» — NOT as an
    // outcome and not as a false press.
    expect(events[0].outcome).toBeNull();

    expect(await repo.setAlertOutcome(DEMO_USER, CHILD, at, 'false_press')).toBe(true);

    events = (await a.inject({ method: 'GET', url: '/admin/safety' })).json().events;
    expect(events[0].outcome).toBe('false_press');
    await a.close();
  });

  it('carries the mother’s number so «Позвонить маме» has one, and never an outcome on a crossing', async () => {
    await repo.recordAlert(DEMO_USER, {
      childId: CHILD, kind: 'entered', zoneName: 'Школа', at: '2026-07-15T09:00:00.000Z',
    });
    const a = app();
    const events = (await a.inject({ method: 'GET', url: '/admin/safety' })).json().events;
    expect(events[0].kind).toBe('entered');
    expect(events[0].outcome).toBeNull();
    expect(typeof events[0].phone).toBe('string');
    expect(events[0].phone.length).toBeGreaterThan(5);
    await a.close();
  });
});
