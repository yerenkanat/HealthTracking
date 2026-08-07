/**
 * The operator's dashboard: what is waiting, and how long it has waited.
 *
 * «Дашбордов два. Владельцу — деньги … Оператору — очереди задач. Не
 * смешивать.» There was one, and it was the owner's. An operator opening the
 * panel got revenue, margin and stock value — questions that are not hers — and
 * no answer to the only one that is: what do I do next. Once `finance` became a
 * capability she got that same screen with the numbers blanked, which is worse
 * than the wrong screen.
 *
 * The thing worth testing hardest is the ORDER and the AGE. Every feed in this
 * system is newest-first, which is right for a log and exactly wrong for a
 * queue: it puts what has waited longest at the bottom. And a count alone
 * cannot tell three four-day-old callbacks from twelve fresh ones, which is the
 * difference between a bad morning and a normal one.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildQueues, overdue, SLA_HOURS } from '../admin/queues';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { StaffRole } from '../auth/capabilities';

const NOW = Date.parse('2026-08-07T12:00:00.000Z');
const hoursAgo = (h: number) => new Date(NOW - h * 3_600_000).toISOString();

const lead = (id: string, h: number, status = 'new') => ({
  id, customerName: `Клиент ${id}`, phone: '+77001112233', package: 'Комплект',
  status, createdAt: hoursAgo(h),
});
const order = (id: string, h: number, status = 'new') => ({
  id, customerName: `Заказчик ${id}`, city: 'Астана', status, totalMinor: 3900000,
  createdAt: hoursAgo(h),
});
const sos = (id: string, h: number, ackedAt: string | null = null) => ({
  id, displayName: `Айгерім ${id}`, code: 'sos', severity: 'critical',
  at: hoursAgo(h), acknowledgedAt: ackedAt,
});

describe('a queue is ordered by how long it has waited', () => {
  it('oldest first — not the newest-first order every feed arrives in', () => {
    const q = buildQueues({
      leads: [lead('fresh', 1), lead('old', 30), lead('middling', 6)],
      orders: [], emergencies: [],
    }, NOW);
    expect(q.leads.next.map((i) => i.id)).toEqual(['old', 'middling', 'fresh']);
    expect(q.leads.oldestHours).toBe(30);
    expect(q.leads.waiting).toBe(3);
  });

  it('shows only the front of it — this is a screen, not an export', () => {
    const many = Array.from({ length: 20 }, (_, i) => lead(`l${i}`, i + 1));
    const q = buildQueues({ leads: many, orders: [], emergencies: [] }, NOW);
    expect(q.leads.waiting).toBe(20);
    expect(q.leads.next.length).toBe(5);
    expect(q.leads.next[0].id).toBe('l19'); // 20 hours old, the oldest
  });

  it('an empty queue has no age at all, rather than an age of zero', () => {
    // Zero hours reads as "something arrived just now". Null is "nothing is
    // waiting", and the two must not render the same.
    const q = buildQueues({ leads: [], orders: [], emergencies: [] }, NOW);
    expect(q.leads).toEqual({ waiting: 0, oldestHours: null, next: [] });
  });

  it('a clock skew does not produce a negative wait', () => {
    const q = buildQueues({ leads: [lead('future', -5)], orders: [], emergencies: [] }, NOW);
    expect(q.leads.oldestHours).toBe(0);
  });
});

describe('what counts as waiting', () => {
  it('a lead that has been rung is finished, whatever came of it', () => {
    // A queue that never empties stops being read. Called-and-declined is done
    // work; leaving it in would keep the number above zero forever.
    const q = buildQueues({
      leads: [lead('called', 40, 'called'), lead('dropped', 50, 'dropped'), lead('waiting', 2)],
      orders: [], emergencies: [],
    }, NOW);
    expect(q.leads.waiting).toBe(1);
    expect(q.leads.next[0].id).toBe('waiting');
  });

  it('an order queues until it leaves the building, and not after', () => {
    const q = buildQueues({
      leads: [],
      orders: [
        order('n', 5), order('c', 9, 'confirmed'),
        order('s', 60, 'shipped'), order('d', 90, 'delivered'), order('x', 99, 'cancelled'),
      ],
      emergencies: [],
    }, NOW);
    // Shipped is the courier's problem now — a queue nobody here can shorten.
    expect(q.orders.next.map((i) => i.id)).toEqual(['c', 'n']);
    expect(q.orders.oldestHours).toBe(9);
  });

  it('an acknowledged emergency is out of the queue', () => {
    const q = buildQueues({
      leads: [], orders: [],
      emergencies: [sos('acked', 20, hoursAgo(19)), sos('open', 2)],
    }, NOW);
    expect(q.emergencies.waiting).toBe(1);
    expect(q.emergencies.next[0].id).toBe('open');
  });
});

describe('what is actually late', () => {
  it('measures each queue against its own clock', () => {
    // An SOS is measured in minutes, a callback in hours, an order in days.
    // One shared "overdue" threshold would either shout about every order or
    // stay silent on an unacknowledged alarm.
    const q = buildQueues({
      leads: [lead('l', 2)],           // under the 4h rule
      orders: [order('o', 50)],        // over the 48h rule
      emergencies: [sos('e', 3)],      // well over the 1h rule
    }, NOW);
    expect(overdue(q)).toEqual(['emergencies', 'orders']);
  });

  it('worst first: an alarm outranks a stale callback', () => {
    const q = buildQueues({
      leads: [lead('l', 100)], orders: [order('o', 100)], emergencies: [sos('e', 2)],
    }, NOW);
    expect(overdue(q)[0]).toBe('emergencies');
  });

  it('an empty queue is never late', () => {
    const q = buildQueues({ leads: [], orders: [], emergencies: [] }, NOW);
    expect(overdue(q)).toEqual([]);
  });

  it('the thresholds are the ones the business works to', () => {
    expect(SLA_HOURS).toEqual({ emergencies: 1, leads: 4, orders: 48 });
  });
});

// ---------------------------------------------------------------------------

let app: FastifyInstance;

function makeApp(role: StaffRole) {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

const queuesAs = async (role: StaffRole) => {
  const a = makeApp(role);
  try {
    return (await a.inject({ method: 'GET', url: '/admin/queues' })).json();
  } finally {
    await a.close();
  }
};

beforeEach(() => { app = makeApp('operator'); });

describe('who gets which queues', () => {
  it('an operator gets all three', async () => {
    const body = await queuesAs('operator');
    expect(body.available.sort()).toEqual(['emergencies', 'leads', 'orders']);
    expect(Object.keys(body.queues).sort()).toEqual(['emergencies', 'leads', 'orders']);
  });

  it('a seller gets her orders and no alarms', async () => {
    // She has `orders` and not `emergencies`. The honest answer to "what is
    // waiting for me" is her two queues, not a 403 on the whole screen.
    const body = await queuesAs('seller');
    expect(body.available.sort()).toEqual(['leads', 'orders']);
    expect(body.queues.emergencies).toBeUndefined();
  });

  it('a clinician gets alarms and no orders', async () => {
    const body = await queuesAs('clinician');
    expect(body.available).toEqual(['emergencies']);
    expect(body.queues.orders).toBeUndefined();
  });

  it('nothing queues for a warehouse hand', async () => {
    // Her work arrives as a shipment, not as a list of people waiting. An
    // empty board is the right answer, and it is not the same as a refusal.
    const body = await queuesAs('warehouse');
    expect(body.available).toEqual([]);
    expect(body.queues).toBeNull();
  });

  it('an unavailable queue and an empty one do not look alike', async () => {
    // Without `available`, a seller and an operator with no alarms would read
    // identically — one is "you cannot see this", the other "nothing is wrong".
    const seller = await queuesAs('seller');
    const operator = await queuesAs('operator');
    expect(seller.available).not.toContain('emergencies');
    expect(operator.available).toContain('emergencies');
    expect(operator.queues.emergencies.waiting).toBe(0);
  });

  it('is never told something is late that it cannot look at', async () => {
    const seller = await queuesAs('seller');
    expect(seller.overdue.every((k: string) => seller.available.includes(k))).toBe(true);
  });

  it('signed out is 401', async () => {
    const anon = buildServer(
      {
        repo: createMemoryRepository(),
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
    expect((await anon.inject({ method: 'GET', url: '/admin/queues' })).statusCode).toBe(401);
    await anon.close();
  });
});

describe('a real lead reaches the queue', () => {
  it('a callback from the landing shows up as work for somebody', async () => {
    // The whole chain: the storefront's form, the repository, the queue.
    const posted = await app.inject({
      method: 'POST', url: '/shop/leads',
      payload: { customerName: 'Мадина', phone: '+7 700 111 22 33', package: 'Комплект', locale: 'ru' },
    });
    expect(posted.statusCode, posted.body).toBeLessThan(300);

    const body = (await app.inject({ method: 'GET', url: '/admin/queues' })).json();
    expect(body.queues.leads.waiting).toBe(1);
    expect(body.queues.leads.next[0].who).toBe('Мадина');
    // Just arrived, so it is not late — the board must not open red on the
    // first callback of the morning.
    expect(body.overdue).not.toContain('leads');
    await app.close();
  });
});
