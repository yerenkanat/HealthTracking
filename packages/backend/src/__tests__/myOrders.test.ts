/**
 * Screen 42 — «Мой заказ».
 *
 * A woman pays 39 000 ₸ through the app and the app never mentions it again:
 * POST /shop/orders existed and nothing could read one back. The tests that
 * matter are the two ways this can be worse than useless — showing her an
 * empty screen when she HAS ordered, and offering to cancel something that is
 * already on a van.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { orderProgress, ORDER_STEPS, visibleOrders } from '../shop/orderProgress';
import type { Repository, ShopOrder } from '../db/repository';

const NOW = new Date('2026-08-08T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

const order = (o: Partial<ShopOrder> = {}): ShopOrder => ({
  id: 'o1', customerName: 'Айгерім', phone: '+7 (707) 345-22-44',
  city: 'Алматы', address: 'ул. 1', note: null,
  totalMinor: 3_900_000, discountMinor: 0, status: 'new',
  createdAt: daysAgo(1),
  items: [{ productName: 'Комплект', color: 'rose', qty: 1, unitPriceMinor: 3_900_000 }],
  ...o,
});

describe('the timeline', () => {
  it('has four steps and marks where the parcel is', () => {
    const p = orderProgress(order({ status: 'shipped' }));
    expect(p.steps.map((s) => s.step)).toEqual([...ORDER_STEPS]);
    expect(p.steps.filter((s) => s.done).map((s) => s.step))
      .toEqual(['new', 'confirmed', 'shipped']);
    expect(p.steps.find((s) => s.current)?.step).toBe('shipped');
  });

  it('does not draw cancellation as a later stage of delivery', () => {
    // A fourth step after «доставлен» would imply the parcel is still coming.
    expect(ORDER_STEPS).not.toContain('cancelled');
    const p = orderProgress(order({ status: 'cancelled' }));
    expect(p.cancelled).toBe(true);
    expect(p.steps.every((s) => !s.done && !s.current)).toBe(true);
  });
});

describe('cancelling', () => {
  it('is offered before it ships', () => {
    expect(orderProgress(order({ status: 'new' })).cancellable).toBe(true);
    expect(orderProgress(order({ status: 'confirmed' })).cancellable).toBe(true);
  });

  it('is not offered once a courier has it', () => {
    // Cancelling in an app does not stop a van. Offering the button is a
    // promise the system cannot keep, and she finds out on the doorstep.
    expect(orderProgress(order({ status: 'shipped' })).cancellable).toBe(false);
    expect(orderProgress(order({ status: 'delivered' })).cancellable).toBe(false);
  });
});

describe('which orders to show', () => {
  it('keeps a delivered one around, because «что было в заказе» is asked later', () => {
    const out = visibleOrders([order({ status: 'delivered', createdAt: daysAgo(10) })], NOW);
    expect(out).toHaveLength(1);
  });

  it('drops a long-finished one', () => {
    const out = visibleOrders([order({ status: 'delivered', createdAt: daysAgo(200) })], NOW);
    expect(out).toEqual([]);
  });

  it('never drops one that is still moving, however old', () => {
    // An order stuck in `new` for three months is exactly what she needs to
    // see, and exactly what a naive age cutoff would hide.
    const out = visibleOrders([order({ status: 'new', createdAt: daysAgo(200) })], NOW);
    expect(out).toHaveLength(1);
  });

  it('newest first', () => {
    const out = visibleOrders([
      order({ id: 'old', createdAt: daysAgo(9) }),
      order({ id: 'new', createdAt: daysAgo(1) }),
    ], NOW);
    expect(out[0].id).toBe('new');
  });
});

// ---------------------------------------------------------------------------

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

/** Give the signed-in profile a number, and place an order against it. */
async function orderAs(profilePhone: string, orderedPhone: string) {
  await app.inject({
    method: 'PUT', url: '/profile',
    payload: { displayName: 'Айгерім', phone: profilePhone },
  });
  // A variant that is actually in stock: the seeded catalogue has some at
  // zero, and placing against one of those answers 409 rather than creating
  // the order the rest of the test is about.
  // The seeded catalogue ships at zero stock, so receive some first — the
  // same path a warehouse hand uses. Ordering against an empty shelf answers
  // 409 and never creates the order the rest of the test is about.
  const variants = await repo.adminShopVariants();
  const v = variants[0];
  await repo.moveStock({ variantId: v.id, delta: 5, reason: 'receipt' });
  return app.inject({
    method: 'POST', url: '/shop/orders',
    payload: {
      customerName: 'Айгерім', phone: orderedPhone, city: 'Алматы',
      address: 'ул. Абая 1', items: [{ variantId: v.id, qty: 1 }],
    },
  });
}

beforeEach(() => { app = makeApp(); });

describe('GET /shop/my-orders', () => {
  it('finds the order she placed', async () => {
    const placed = await orderAs('+7 707 345 22 44', '+7 707 345 22 44');
    expect(placed.statusCode, placed.body).toBe(201);
    const b = (await app.inject({ method: 'GET', url: '/shop/my-orders' })).json();
    expect(b.orders).toHaveLength(1);
    expect(b.orders[0].items[0].productName).toBeTruthy();
    expect(b.orders[0].cancellable).toBe(true);
    await app.close();
  });

  it('finds it however the number was written', async () => {
    // She signed in as «+7 707…» and the order was taken over the phone as
    // «8 (707)…». Matching the raw strings shows an empty screen to a woman
    // with a charge on her card — the class of bug src/phone.ts exists to end.
    await orderAs('+7 707 345 22 44', '8 (707) 345-22-44');
    const b = (await app.inject({ method: 'GET', url: '/shop/my-orders' })).json();
    expect(b.orders).toHaveLength(1);
    await app.close();
  });

  it('shows somebody else nothing of hers', async () => {
    await orderAs('+7 707 345 22 44', '+7 707 345 22 44');
    await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Другая', phone: '+7 701 000 00 00' },
    });
    const b = (await app.inject({ method: 'GET', url: '/shop/my-orders' })).json();
    expect(b.orders).toEqual([]);
    await app.close();
  });

  it('says WHY it is empty when there is no number on the profile', async () => {
    // «Заказов нет» to somebody who has ordered but never filled in her phone
    // is wrong in a way she cannot act on. A null phone lets the screen ask
    // her to add one.
    await app.inject({
      method: 'PUT', url: '/profile', payload: { displayName: 'Айгерім' },
    });
    const b = (await app.inject({ method: 'GET', url: '/shop/my-orders' })).json();
    expect(b.orders).toEqual([]);
    expect(b.phone).toBeNull();
    await app.close();
  });
});

describe('POST /shop/my-orders/:id/cancel', () => {
  it('cancels one that has not shipped', async () => {
    await orderAs('+7 707 345 22 44', '+7 707 345 22 44');
    const id = (await app.inject({ method: 'GET', url: '/shop/my-orders' }))
      .json().orders[0].orderId;

    expect((await app.inject({
      method: 'POST', url: `/shop/my-orders/${id}/cancel`,
    })).statusCode).toBe(200);

    const after = (await app.inject({ method: 'GET', url: '/shop/my-orders' })).json();
    expect(after.orders[0].cancelled).toBe(true);
    await app.close();
  });

  it('refuses once it is with a courier', async () => {
    await orderAs('+7 707 345 22 44', '+7 707 345 22 44');
    const id = (await app.inject({ method: 'GET', url: '/shop/my-orders' }))
      .json().orders[0].orderId;
    await repo.setShopOrderStatus(id, 'shipped');

    const r = await app.inject({ method: 'POST', url: `/shop/my-orders/${id}/cancel` });
    expect(r.statusCode).toBe(409);
    expect(r.json().error).toBe('too_late');
    await app.close();
  });

  it('will not cancel a stranger\'s delivery', async () => {
    // The id is guessable enough to matter, and the check is the ownership
    // one — not the client having hidden the button.
    await orderAs('+7 707 345 22 44', '+7 707 345 22 44');
    const id = (await app.inject({ method: 'GET', url: '/shop/my-orders' }))
      .json().orders[0].orderId;

    await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Другая', phone: '+7 701 000 00 00' },
    });
    const r = await app.inject({ method: 'POST', url: `/shop/my-orders/${id}/cancel` });
    expect(r.statusCode).toBe(404);

    // And it is genuinely still live.
    await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Айгерім', phone: '+7 707 345 22 44' },
    });
    expect((await app.inject({ method: 'GET', url: '/shop/my-orders' }))
      .json().orders[0].cancelled).toBe(false);
    await app.close();
  });
});
