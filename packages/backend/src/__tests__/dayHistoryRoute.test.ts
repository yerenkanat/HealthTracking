/**
 * GET /children/:id/day, over HTTP against a real repository.
 *
 * dayHistory.test.ts proves the arithmetic. This proves the chain: a fix
 * ingested, a trail stored, a day asked for and the same points coming back.
 * Every part of this feature existed except the join — the trail was written
 * and pruned and could not be read — so the join is the part worth testing.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEMO_CHILD } from '../db/memoryRepository';
import { ROUTE_RETENTION_DAYS } from '../privacy/retention';
import type { Repository } from '../db/repository';

const DAY = '2026-08-08';
const at = (h: number, m = 0) =>
  `${DAY}T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00.000Z`;

let app: FastifyInstance;
let repo: Repository;

function makeApp() {
  repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => null,
    },
    { logger: false },
  );
}

/** A fix straight into the repository — the same call the ingest path makes. */
async function seedFix(h: number, m: number, lat: number, lng: number) {
  await repo.insertLocation({
    childId: DEMO_CHILD,
    observedAt: at(h, m),
    source: 'gps',
    coords: { lat, lng },
  });
}

beforeEach(() => { app = makeApp(); });

describe('GET /children/:id/day', () => {
  it('returns the trail that was stored, oldest first', async () => {
    await seedFix(8, 0, 43.238, 76.889);
    await seedFix(8, 30, 43.248, 76.889);
    await seedFix(9, 0, 43.258, 76.889);

    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();

    expect(b.day).toBe(DAY);
    expect(b.points).toHaveLength(3);
    expect(b.points[0].observedAt).toBe(at(8, 0));
    expect(b.distanceM).toBeGreaterThan(2000);
    expect(b.pointCount).toBe(3);
    await app.close();
  });

  it('keeps other days out of it', async () => {
    await seedFix(8, 0, 43.238, 76.889);
    await repo.insertLocation({
      childId: DEMO_CHILD, observedAt: '2026-08-07T08:00:00.000Z',
      source: 'gps', coords: { lat: 43.1, lng: 76.1 },
    });
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    expect(b.points).toHaveLength(1);
    await app.close();
  });

  it('is an empty day rather than an error when nothing was recorded', async () => {
    // A tracker that was off all day is not a failure, and the screen has to be
    // able to tell the two apart.
    const r = await app.inject({ method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}` });
    expect(r.statusCode).toBe(200);
    expect(r.json().points).toEqual([]);
    expect(r.json().distanceM).toBe(0);
    await app.close();
  });

  it('quotes the retention promise from where the sweep reads it', async () => {
    // «маршруты хранятся 90 дней» is printed on this screen. Re-typing 90 in
    // the app is how the promise drifts from what the job does.
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    expect(b.retentionDays).toBe(ROUTE_RETENTION_DAYS);
    await app.close();
  });

  it('defaults to today rather than refusing a missing day', async () => {
    const b = (await app.inject({ method: 'GET', url: `/children/${DEMO_CHILD}/day` })).json();
    expect(b.day).toBe(new Date().toISOString().slice(0, 10));
    await app.close();
  });

  it('ignores a malformed day instead of building a broken range', async () => {
    const r = await app.inject({ method: 'GET', url: `/children/${DEMO_CHILD}/day?day=lastweek` });
    expect(r.statusCode).toBe(200);
    expect(r.json().day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    await app.close();
  });

  it('shows an SOS on the timeline', async () => {
    // The kind that could not be stored at all until migration 030 widened the
    // CHECK — the table had an index and two counters over rows it refused.
    await repo.recordAlert(DEMO_USER, {
      childId: DEMO_CHILD, kind: 'sos', zoneName: '', at: at(16, 41),
    });
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    expect(b.events).toHaveLength(1);
    expect(b.events[0].kind).toBe('sos');
    expect(b.events[0].at).toBe(at(16, 41));
    await app.close();
  });

  it('does not show a sibling\'s SOS on this child\'s day', async () => {
    // Alerts are stored per user, so the list carries every child on the
    // account. Showing them all would put one child's alarm on another's map.
    await repo.recordAlert(DEMO_USER, {
      childId: 'some-other-child', kind: 'sos', zoneName: '', at: at(16, 41),
    });
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    expect(b.events).toEqual([]);
    await app.close();
  });

  it('accepts every alert kind the app can send', async () => {
    // The app's AlertKind has five and its screen offers a filter for each.
    // The POST schema, the row type and the table's CHECK each admitted two,
    // so three of the five were rejected with a 400 the app never surfaced.
    for (const kind of ['entered', 'left', 'checkIn', 'sos', 'lowBattery']) {
      const r = await app.inject({
        method: 'POST', url: '/alerts',
        payload: { childId: DEMO_CHILD, kind, zoneName: 'Дом', at: at(10) },
      });
      expect(r.statusCode, `${kind} was refused`).toBeLessThan(300);
    }
    await app.close();
  });

  it('accepts an SOS with no zone name', async () => {
    // An SOS happens wherever she is. min(1) on zoneName refused every one.
    const r = await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'sos', at: at(16, 41) },
    });
    expect(r.statusCode).toBeLessThan(300);
    await app.close();
  });

  it('refuses a child that is not yours', async () => {
    const r = await app.inject({ method: 'GET', url: '/children/not-mine/day' });
    expect([403, 404]).toContain(r.statusCode);
    await app.close();
  });
});
