/**
 * Кадр 05a «Возвраты и брак» — the write side, over HTTP.
 *
 * The defect: an operator who took a delivered комплект back from a mother had
 * NOWHERE to record it. The only writer of a reason='return' stock move was
 * order cancellation, and `moveStock()` in the panel had two callers — receipt
 * and write-off — neither of which passes 'return'. So a returned unit was
 * written off, which destroys stock and inflates «Списано на сумму», or nothing
 * was recorded at all and the refunded money stayed in «Заработано» for ever.
 *
 * Everything here is read BACK: off the ledger, off the shelf, off a second
 * request. A 201 proves the route answered, never that the stock moved.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository, StockMove } from '../db/repository';
import { buildFinanceReport } from '../admin/finance';
import { hashPassword, hashToken, readSessionCookie } from '../http/staffAuth';

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

beforeEach(async () => {
  repo = createMemoryRepository();
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
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(res.statusCode, 'the seeded staff account could not sign in').toBe(200);
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const get = (url: string, as = cookie) =>
  app.inject({ method: 'GET', url, headers: { cookie: as } });
const post = (url: string, payload: unknown, as = cookie) =>
  app.inject({ method: 'POST', url, payload: payload as never, headers: { cookie: as } });

/** Sign in as somebody with a narrower role, to test the guard for real. */
async function signInAs(role: 'warehouse' | 'operator' | 'content'): Promise<string> {
  const phone = `7700000000${role.length}`;
  await repo.upsertStaffAccount({
    phone, passwordHash: await hashPassword('other-password'),
    role, displayName: role,
  });
  const res = await app.inject({
    method: 'POST', url: '/admin/login', payload: { phone, password: 'other-password' },
  });
  expect(res.statusCode, `${role} could not sign in`).toBe(200);
  return String(res.headers['set-cookie'] ?? '').split(';')[0];
}

/** Put units of a product's first colour on the shelf, and return that variant. */
async function stocked(productId: string, qty = 10): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const v = p.variants[0].id;
  await repo.moveStock({ variantId: v, delta: qty, reason: 'receipt' });
  return v;
}

const stockOf = async (variantId: string): Promise<number> => {
  for (const p of await repo.adminProducts()) {
    const v = p.variants.find((x) => x.id === variantId);
    if (v) return v.stock;
  }
  throw new Error(`no such variant: ${variantId}`);
};

/** Place one order through the real route and return its id. */
async function placeOrder(variantId: string, qty = 1): Promise<string> {
  const res = await post('/admin/shop/orders', {
    customerName: 'Айгерім', phone: '+7 707 345 22 44', city: 'Алматы',
    address: 'ул. Абая 1', items: [{ variantId, qty }],
  });
  expect(res.statusCode, res.body).toBe(201);
  return res.json().id as string;
}

const movesFor = async (orderId: string): Promise<StockMove[]> =>
  (await repo.stockMoves(500)).filter((m) => m.orderId === orderId);

describe('booking a refund', () => {
  it('writes the refund AND puts the restocked unit back on the shelf', async () => {
    const v = await stocked('watch', 10);
    const orderId = await placeOrder(v, 1);
    expect(await stockOf(v), 'the sale never took the unit off the shelf').toBe(9);

    const res = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 390_000, reason: 'not_suitable', note: 'мала по размеру',
      restock: [{ variantId: v, qty: 1 }],
    });
    expect(res.statusCode, res.body).toBe(201);

    // The shelf, not the response.
    expect(await stockOf(v), 'the money came back and the unit did not').toBe(10);

    // The ledger row, with the discriminator the finance report needs.
    const back = (await movesFor(orderId)).filter((m) => m.reason === 'return');
    expect(back, 'no return move was written').toHaveLength(1);
    expect(back[0].delta).toBe(1);
    expect(back[0].orderId).toBe(orderId);
    expect(back[0].refundId, 'the move is indistinguishable from a cancellation')
      .toBe(res.json().refund.id);
  });

  it('reads back off the order card, with who booked it', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 100_000, reason: 'defect', note: 'не заряжается',
      restock: [{ variantId: v, qty: 1 }],
    });

    const card = (await get(`/admin/shop/orders/${orderId}`)).json();
    expect(card.refunds, 'the card cannot show a refund it is not sent').toHaveLength(1);
    expect(card.refunds[0].amountMinor).toBe(100_000);
    expect(card.refunds[0].reason).toBe('defect');
    expect(card.refunds[0].note).toBe('не заряжается');
    expect(card.refunds[0].restockedUnits).toBe(1);
    // The author is named, not left as a UUID for the panel to print raw.
    expect(card.refunds[0].staffName).toBeTruthy();
    expect(card.payment.refundedMinor).toBe(100_000);
    expect(card.payment.refundableMinor).toBe(card.order.totalMinor - 100_000);
  });

  it('a refund with no restock moves no stock — a broken unit is not resold', async () => {
    const v = await stocked('watch', 10);
    const orderId = await placeOrder(v, 1);
    const res = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 50_000, reason: 'defect', restock: [],
    });
    expect(res.statusCode, res.body).toBe(201);
    expect(await stockOf(v), 'a defective unit went back on the shelf').toBe(9);
    expect((await movesFor(orderId)).filter((m) => m.reason === 'return')).toEqual([]);
    expect(res.json().refund.restockedUnits).toBe(0);
  });

  it('records it in the audit log with the amount and the reason', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 390_000, reason: 'changed_mind',
    });
    const rows = (await get('/admin/audit?limit=50')).json().audit;
    const row = rows.find((r: { action: string }) => r.action === 'order_refund');
    expect(row, 'handing 3 900 ₸ back left no trace').toBeTruthy();
    expect(row.target).toBe(orderId);
    expect(row.reason).toContain('changed_mind');
  });
});

describe('what a refund refuses', () => {
  it('409s rather than hand back more than the order was worth', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    const total = (await repo.shopOrderById(orderId))!.totalMinor;

    const res = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: total + 1, reason: 'other',
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('refund_exceeds_order');
    expect(await repo.orderRefunds(orderId), 'a refused refund was still written').toEqual([]);
  });

  it('counts the refunds already booked, not just this one', async () => {
    // Two halves and then a third: the read-modify-write that a per-request
    // check alone would wave through.
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    const total = (await repo.shopOrderById(orderId))!.totalMinor;

    const half = Math.floor(total / 2);
    expect((await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: half, reason: 'other',
    })).statusCode).toBe(201);
    expect((await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: half, reason: 'other',
    })).statusCode).toBe(201);

    const third = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: half, reason: 'other',
    });
    expect(third.statusCode, 'the order was refunded one and a half times').toBe(409);
    expect(third.json().error).toBe('refund_exceeds_order');
  });

  it('refuses to restock more units than went out on that line', async () => {
    const v = await stocked('watch', 10);
    const orderId = await placeOrder(v, 1);
    const res = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 1000, reason: 'other', restock: [{ variantId: v, qty: 2 }],
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('restock_exceeds_order');
    expect(res.json().variantId).toBe(v);
    // And nothing was written: not the refund, not the stock.
    expect(await stockOf(v)).toBe(9);
    expect(await repo.orderRefunds(orderId)).toEqual([]);
  });

  it('refuses a variant that is not on the order at all', async () => {
    const v = await stocked('watch');
    const other = await stocked('tracker');
    const orderId = await placeOrder(v);
    const res = await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 1000, reason: 'other', restock: [{ variantId: other, qty: 1 }],
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('unknown_line');
  });

  it('404s for an order that does not exist, rather than 500ing on the id', async () => {
    const res = await post('/admin/shop/orders/not-a-uuid/refund', {
      amountMinor: 1000, reason: 'other',
    });
    expect(res.statusCode).toBe(404);
    expect(res.json().error).toBe('not_found');
  });
});

describe('what a refund deliberately does NOT do', () => {
  it('leaves the order where it was — a refunded order was still delivered', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    await app.inject({
      method: 'PATCH', url: `/admin/shop/orders/${orderId}`,
      payload: { status: 'delivered' } as never, headers: { cookie },
    });
    await post(`/admin/shop/orders/${orderId}/refund`, { amountMinor: 1000, reason: 'defect' });

    // Marking it cancelled would move real revenue into «Потеряно на отменах»
    // AND return the stock a second time.
    expect((await repo.shopOrderById(orderId))!.status).toBe('delivered');
  });

  it('does not revoke the course — that stays a decision a person makes', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    await repo.grantEntitlement({ phone: '77073452244', feature: 'mama_course', orderId });

    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 1000, reason: 'changed_mind', restock: [{ variantId: v, qty: 1 }],
    });

    // A mother losing her course because a box came back is not a decision a
    // refund gets to make; the panel offers the link to «Кому открыт курс».
    expect(await repo.hasEntitlement('77073452244', 'mama_course')).toBe(true);
  });

  it('does not change the serial in the device registry', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    await repo.addDeviceSerials([{ serial: 'AABBCCDDEE01', kind: 'band' }]);
    await repo.assignDevicesToOrder(orderId, ['AABBCCDDEE01']);
    await repo.markDeviceActivated('AABBCCDDEE01', '77073452244');
    const before = await repo.deviceRegistryEntry('AABBCCDDEE01');

    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 1000, reason: 'defect', restock: [{ variantId: v, qty: 1 }],
    });

    // The registry has three states — stock / sold / blocked — and none of them
    // means «вернули», so the unit keeps saying what it said. The modal states
    // this rather than implying the serial was freed.
    const after = await repo.deviceRegistryEntry('AABBCCDDEE01');
    expect(after).toEqual(before);
    expect(after!.activatedByPhone).toBe('77073452244');
  });
});

describe('who may hand money back', () => {
  it('an operator may: it is the person at the door who takes the box', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    const operator = await signInAs('operator');
    const res = await post(
      `/admin/shop/orders/${orderId}/refund`,
      { amountMinor: 1000, reason: 'defect' },
      operator,
    );
    // `finance` — the read of the books — is held by owners and admins only, so
    // guarding this with it is how a refund goes on being booked as a write-off.
    expect(res.statusCode, res.body).toBe(201);
  });

  it('a warehouse hand may not: stock must not declare that money was returned', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    const warehouse = await signInAs('warehouse');
    const res = await post(
      `/admin/shop/orders/${orderId}/refund`,
      { amountMinor: 1000, reason: 'defect', restock: [{ variantId: v, qty: 1 }] },
      warehouse,
    );
    expect(res.statusCode).toBe(403);
    expect(await repo.orderRefunds(orderId)).toEqual([]);
  });

  it('and neither may a content editor', async () => {
    const v = await stocked('watch');
    const orderId = await placeOrder(v);
    const editor = await signInAs('content');
    expect((await post(
      `/admin/shop/orders/${orderId}/refund`,
      { amountMinor: 1000, reason: 'defect' },
      editor,
    )).statusCode).toBe(403);
  });
});

describe('the finance report can finally tell the two apart', () => {
  /** The window every case below reports on. */
  const today = new Date().toISOString().slice(0, 10);

  const report = async () => {
    const [orders, products, moves, refunds] = await Promise.all([
      repo.adminShopOrders(1000), repo.adminProducts(), repo.stockMoves(2000),
      repo.refundsBetween(today, today),
    ]);
    return buildFinanceReport({
      orders, products, moves, refunds, planMinor: null, from: today, to: today,
    });
  };

  it('counts a refund as a return and a cancellation as a cancellation', async () => {
    const v = await stocked('watch', 20);
    const refunded = await placeOrder(v, 1);
    const cancelled = await placeOrder(v, 1);
    await placeOrder(v, 2); // sold and kept

    await post(`/admin/shop/orders/${refunded}/refund`, {
      amountMinor: 390_000, reason: 'defect', restock: [{ variantId: v, qty: 1 }],
    });
    await app.inject({
      method: 'PATCH', url: `/admin/shop/orders/${cancelled}`,
      payload: { status: 'cancelled' } as never, headers: { cookie },
    });

    const r = await report();
    expect(r.returns.soldUnits).toBe(4);
    // One customer sent one unit back. The other order was never in revenue.
    expect(r.returns.returnedUnits, 'a cancellation is being counted as a return').toBe(1);
    expect(r.returns.cancelledUnits).toBe(1);
    expect(r.returns.otherReturnUnits).toBe(0);
    // 1 ÷ 4, not 2 ÷ 4.
    expect(r.returns.returnRate).toBeCloseTo(0.25);
    expect(r.money.refundedMinor).toBe(390_000);
    expect(r.returns.reasonCounts.defect).toBe(1);
    expect(r.returns.reasonCounts.other).toBe(0);
  });

  it('takes the refund off the revenue as well as off the count', async () => {
    const v = await stocked('watch', 20);
    const orderId = await placeOrder(v, 1);
    await app.inject({
      method: 'PATCH', url: `/admin/shop/orders/${orderId}`,
      payload: { status: 'delivered' } as never, headers: { cookie },
    });
    const total = (await repo.shopOrderById(orderId))!.totalMinor;
    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 100_000, reason: 'not_suitable',
    });

    const r = await report();
    expect(r.money.earnedMinor).toBe(total);
    expect(r.money.refundedMinor).toBe(100_000);
    expect(r.money.earnedNetMinor).toBe(total - 100_000);
  });

  it('reaches the finance route itself, not only the pure function', async () => {
    const v = await stocked('watch', 20);
    const orderId = await placeOrder(v, 1);
    await post(`/admin/shop/orders/${orderId}/refund`, {
      amountMinor: 70_000, reason: 'not_delivered', restock: [{ variantId: v, qty: 1 }],
    });

    const body = (await get(`/admin/finance?from=${today}&to=${today}`)).json();
    expect(body.money.refundedMinor, 'the route never asked the repository for refunds')
      .toBe(70_000);
    expect(body.returns.returnedUnits).toBe(1);
    expect(body.returns.refundCount).toBe(1);
    expect(body.returns.reasonCounts.not_delivered).toBe(1);
    expect(body.slice.refundsComplete).toBe(true);
    // And the events row says WHICH of the three kinds it is.
    const ret = body.returns.events.find((e: { kind: string }) => e.kind === 'refund');
    expect(ret, 'the refund is not in the events table').toBeTruthy();
    expect(ret.refundReason).toBe('not_delivered');
  });

  it('says «неизвестно» rather than «0 ₸» when the refunds cannot be read', async () => {
    // A caught error left refundedMinor at 0, which is indistinguishable from a
    // month with no refunds — false, and false in the flattering direction.
    const r = buildFinanceReport({
      orders: [], products: [], moves: [], planMinor: null,
      from: today, to: today, refundsUnavailable: true,
    });
    expect(r.slice.refundsComplete).toBe(false);
    expect(r.caveats.join(' ')).toContain('НЕ прочитались');
  });
});
