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

/**
 * The 200-row window, and the day it stopped reaching.
 *
 * The route used to ask for the newest 200 crossings of ALL time and then keep
 * this day's out of them in JavaScript. That works until a child has crossed a
 * boundary 200 times in her life; after that the window ends inside recent
 * history, and every older day comes back with no crossings.
 *
 * What made it worse than an empty screen: the trail is a different query with
 * its own day bound, so the route still drew. The day rendered complete — she
 * went here, here and here, and crossed no boundary — on a day she may have
 * left the school zone three times.
 *
 * So these seed a REAL history. Three rows would pass against the shipped bug.
 */
describe('GET /children/:id/day — a day older than the crossing window', () => {
  const from = `${DAY}T00:00:00.000Z`;
  const to = '2026-08-09T00:00:00.000Z';
  /** Later than DAY, so a newest-first window of all time lands on these. */
  const LATER_CROSSINGS = 250;

  async function seedCrossing(atIso: string, transition: 'enter' | 'exit', zone: string) {
    await repo.insertGeofenceEvent({
      childId: DEMO_CHILD,
      geofenceId: 'zone-school',
      geofenceName: zone,
      transition,
      at: atIso,
      source: 'gps',
    });
  }

  /** A lifetime of crossings, all AFTER the day under test. */
  async function seedLaterHistory(n = LATER_CROSSINGS) {
    // Every three hours from the following morning — real instants, so the
    // fixture would still be valid rows against a real database.
    const start = Date.parse('2026-08-09T06:00:00.000Z');
    for (let i = 0; i < n; i++) {
      await seedCrossing(
        new Date(start + i * 3 * 3_600_000).toISOString(),
        i % 2 === 0 ? 'exit' : 'enter',
        'Школа',
      );
    }
  }

  it('still reports the crossings of that day', async () => {
    await seedLaterHistory();
    await seedCrossing(at(7, 40), 'exit', 'Дом');
    await seedCrossing(at(8, 5), 'enter', 'Школа');

    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();

    expect(b.events.map((e: { kind: string }) => e.kind)).toEqual(['exit', 'enter']);
    expect(b.events[0].at).toBe(at(7, 40));
    expect(b.events[0].zoneName).toBe('Дом');
    expect(b.events[1].zoneName).toBe('Школа');
    await app.close();
  });

  it('does not draw a route beside a silently emptied timeline', async () => {
    // The shape of the shipped bug, stated as one assertion: a day that has
    // both a trail and a crossing must not come back with the trail alone.
    await seedLaterHistory();
    await seedCrossing(at(7, 40), 'exit', 'Школа');
    await seedFix(7, 30, 43.238, 76.889);
    await seedFix(8, 0, 43.248, 76.889);

    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();

    expect(b.points.length).toBeGreaterThan(0);
    expect(b.events, 'route drawn, crossings dropped — the day reads complete and is not')
      .not.toEqual([]);
    await app.close();
  });

  it('spends the limit inside the day, not on recent history', async () => {
    // Straight at the repository: the parameter has to reach the query, not be
    // re-filtered afterwards. Filtering after slicing is the whole defect.
    await seedLaterHistory();
    await seedCrossing(at(7, 40), 'exit', 'Дом');

    const rows = await repo.listGeofenceEvents(DEMO_CHILD, 200, from, to);
    expect(rows).toHaveLength(1);
    expect(rows[0].at).toBe(at(7, 40));
    await app.close();
  });

  it('drops the OLDEST rows when one day overflows the limit', async () => {
    // The cap has not gone away, it has moved inside the day — and when it
    // bites it must keep the newest, like ORDER BY occurred_at DESC LIMIT n.
    const tick = (i: number) => at(Math.floor(i / 60), i % 60);
    for (let i = 0; i < 205; i++) {
      await seedCrossing(tick(i), i % 2 === 0 ? 'enter' : 'exit', 'Школа');
    }
    const rows = await repo.listGeofenceEvents(DEMO_CHILD, 200, from, to);
    expect(rows).toHaveLength(200);
    expect(rows[0].at).toBe(tick(204));
    expect(rows[199].at).toBe(tick(5));
    await app.close();
  });

  it('leaves the all-time zone history alone', async () => {
    // GET /children/:id/events answers "the last crossings", not "a day", and
    // must keep answering across all time — the bound is optional for it.
    await seedLaterHistory(10);
    await seedCrossing(at(7, 40), 'exit', 'Дом');
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/events?limit=50`,
    })).json();
    expect(b.events).toHaveLength(11);
    await app.close();
  });

  it('keeps a neighbouring day out even when it is the newest thing there is', async () => {
    await seedCrossing('2026-08-09T00:00:00.000Z', 'enter', 'Дом');
    await seedCrossing(at(23, 59), 'exit', 'Дом');
    const b = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    // Half-open: midnight belongs to the day that is starting, and to one day.
    expect(b.events).toHaveLength(1);
    expect(b.events[0].at).toBe(at(23, 59));
    await app.close();
  });

  it('still reports an SOS on a day older than the alert window', async () => {
    // The same defect, one line down, and it bites SOONER: alerts are stored
    // per USER, so every crossing of every child on the account writes one, and
    // the day's SOS was picked out of the newest 500 of all time afterwards.
    // A red mark vanishing off an older timeline is the worst version of this —
    // it is the thing a parent came back to the screen to look at.
    for (let i = 0; i < 600; i++) {
      await repo.recordAlert(DEMO_USER, {
        childId: DEMO_CHILD, kind: i % 2 === 0 ? 'left' : 'entered', zoneName: 'Школа',
        at: new Date(Date.parse('2026-08-09T06:00:00.000Z') + i * 3_600_000).toISOString(),
      });
    }
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

  it('answers a shaped but impossible date instead of failing', async () => {
    // '2026-13-45' passes the YYYY-MM-DD pattern and parses to NaN. The range
    // built from it threw RangeError out of toISOString — a 500 on a screen
    // about a child, from a query string.
    const r = await app.inject({ method: 'GET', url: `/children/${DEMO_CHILD}/day?day=2026-13-45` });
    expect(r.statusCode).toBe(200);
    expect(r.json().day).toBe(new Date().toISOString().slice(0, 10));
    await app.close();
  });
});

/**
 * Frame 48 — «Чем закончилось».
 *
 * The four outcome keys and the four chips both existed from the day they were
 * written, and there was nothing between them: no column, no route, and the
 * screen was never handed a saver, so the section could not appear at all.
 * These test the join, which is the part that was missing.
 */
describe('POST /children/:id/day/outcome', () => {
  const SOS_AT = at(16, 41);

  async function seedSos() {
    const r = await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'sos', at: SOS_AT },
    });
    expect(r.statusCode).toBeLessThan(300);
  }

  it('records the verdict, and the day reads it back', async () => {
    await seedSos();

    const save = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/day/outcome`,
      payload: { at: SOS_AT, outcome: 'false_press' },
    });
    expect(save.statusCode).toBe(200);

    // The read side: reopening the alarm must show the chip already chosen,
    // otherwise a parent answers twice and the second answer overwrites.
    const day = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    const sos = day.events.find((e: { kind: string }) => e.kind === 'sos');
    expect(sos.outcome).toBe('false_press');
    await app.close();
  });

  it('is null until somebody closes it', async () => {
    await seedSos();
    const day = (await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day?day=${DAY}`,
    })).json();
    // Not 'unknown' — «не удалось выяснить» is an answer, and nobody gave it.
    expect(day.events.find((e: { kind: string }) => e.kind === 'sos').outcome).toBeNull();
    await app.close();
  });

  it('404s when no SOS happened at that instant', async () => {
    await seedSos();
    const r = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/day/outcome`,
      payload: { at: at(9, 15), outcome: 'scared' },
    });
    // Not 200. The screen prints the result of this request, and a tick over an
    // update that matched nothing is how an open alarm looks closed.
    expect(r.statusCode).toBe(404);
    await app.close();
  });

  it('refuses an outcome it does not know', async () => {
    await seedSos();
    const r = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/day/outcome`,
      payload: { at: SOS_AT, outcome: 'she_was_fine' },
    });
    expect(r.statusCode).toBe(400);
    await app.close();
  });

  it('refuses a child that is not yours', async () => {
    const r = await app.inject({
      method: 'POST', url: '/children/not-mine/day/outcome',
      payload: { at: SOS_AT, outcome: 'scared' },
    });
    expect([403, 404]).toContain(r.statusCode);
    await app.close();
  });

  it('will not close a zone crossing', async () => {
    // Only an SOS has an outcome. A crossing that could be marked «нужна была
    // помощь» would feed the false-alarm rate the back office reads.
    await app.inject({
      method: 'POST', url: '/alerts',
      payload: { childId: DEMO_CHILD, kind: 'left', zoneName: 'Дом', at: at(7, 30) },
    });
    const r = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/day/outcome`,
      payload: { at: at(7, 30), outcome: 'scared' },
    });
    expect(r.statusCode).toBe(404);
    await app.close();
  });
});
