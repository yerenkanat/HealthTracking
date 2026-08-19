/**
 * Кадр 02 «Заказы» and кадр 03 «Карточка заказа», over HTTP.
 *
 * Two gaps this covers, both of the shape this repository keeps producing.
 *
 * The list had no total and no offset, so a footer saying «Показано 25 из 284»
 * could not be written truthfully — the panel knew only how many rows it had
 * asked for. Everything here is read BACK out of the repository or out of a
 * second request, never asserted from the 200 alone.
 *
 * The card had no route at all: an order's composition was in the list, its
 * serials were behind a route nothing called, and its history did not exist
 * anywhere because the only record of a status change was an audit row that
 * says THAT the status moved and never to what.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository, ShopOrderStatus } from '../db/repository';
import { buildOrderTimeline } from '../admin/orders';
import { hashToken, readSessionCookie } from '../http/staffAuth';

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

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const patch = (url: string, payload: unknown) =>
  app.inject({ method: 'PATCH', url, payload: payload as never, headers: { cookie } });

/** Put [qty] of a product's first colour on the shelf and return that variant. */
async function stocked(productId: string, qty = 40): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const v = p.variants[0].id;
  await repo.moveStock({ variantId: v, delta: qty, reason: 'receipt' });
  return v;
}

/** Place [n] orders through the real route, oldest first. */
async function placeOrders(n: number, variantId: string): Promise<string[]> {
  const ids: string[] = [];
  for (let i = 0; i < n; i++) {
    const res = await app.inject({
      method: 'POST', url: '/admin/shop/orders', headers: { cookie },
      payload: {
        customerName: `Клиент ${i + 1}`,
        phone: `+7 70${i} 000 00 0${i}`,
        city: 'Алматы',
        address: `ул. Абая ${i + 1}`,
        items: [{ variantId, qty: 1 }],
      },
    });
    expect(res.statusCode, res.body).toBe(201);
    ids.push(res.json().id);
  }
  return ids;
}

describe('кадр 02 — the list can state «Показано N из M»', () => {
  it('returns a page, the total behind it, and the offset it used', async () => {
    const v = await stocked('watch');
    await placeOrders(7, v);

    const page = (await get('/admin/shop/orders?limit=3&offset=0')).json();
    expect(page.orders).toHaveLength(3);
    // The number the footer prints. Without it the panel can only say "3".
    expect(page.total, 'no total — «Показано 3 из ?» cannot be written').toBe(7);
    expect(page.offset).toBe(0);
    expect(page.limit).toBe(3);

    const second = (await get('/admin/shop/orders?limit=3&offset=3')).json();
    expect(second.orders).toHaveLength(3);
    expect(second.total).toBe(7);
    expect(second.offset).toBe(3);

    // Paging must not repeat or skip an order — the failure that makes an
    // operator work the same order twice and never see another.
    const first = page.orders.map((o: { id: string }) => o.id);
    const rest = second.orders.map((o: { id: string }) => o.id);
    expect(new Set([...first, ...rest]).size).toBe(6);

    const last = (await get('/admin/shop/orders?limit=3&offset=6')).json();
    expect(last.orders).toHaveLength(1);
    expect(last.total).toBe(7);
  });

  it('past the end is an empty page with the real total, not an empty table', async () => {
    const v = await stocked('watch');
    await placeOrders(2, v);
    const page = (await get('/admin/shop/orders?limit=25&offset=90')).json();
    expect(page.orders).toEqual([]);
    // «Показано 0 из 0» on a shop with two orders would read as "we sold
    // nothing", which is the one thing this footer must never say.
    expect(page.total).toBe(2);
  });

  it('counts every status for the filter chips, over the whole table', async () => {
    const v = await stocked('watch');
    const ids = await placeOrders(4, v);
    expect((await patch(`/admin/shop/orders/${ids[0]}`, { status: 'shipped' })).statusCode).toBe(200);
    expect((await patch(`/admin/shop/orders/${ids[1]}`, { status: 'cancelled' })).statusCode).toBe(200);

    const page = (await get('/admin/shop/orders?limit=25')).json();
    expect(page.counts).toEqual({ new: 2, confirmed: 0, shipped: 1, delivered: 0, cancelled: 1 });
  });

  it('filters by status — and the chip counters do NOT follow the filter', async () => {
    const v = await stocked('watch');
    const ids = await placeOrders(3, v);
    await patch(`/admin/shop/orders/${ids[0]}`, { status: 'shipped' });

    const page = (await get('/admin/shop/orders?limit=25&status=shipped')).json();
    expect(page.orders).toHaveLength(1);
    expect(page.orders[0].id).toBe(ids[0]);
    expect(page.status).toBe('shipped');
    // total follows the filter…
    expect(page.total, '«из N» must count what matches the filter').toBe(1);
    // …counts do not. A counter that changed the moment you clicked it could
    // not be used to decide what to click.
    expect(page.counts.new).toBe(2);
    expect(page.counts.shipped).toBe(1);
  });

  it('ignores a status it does not know instead of refusing the screen', async () => {
    const v = await stocked('watch');
    await placeOrders(2, v);
    const res = await get('/admin/shop/orders?status=банан');
    expect(res.statusCode).toBe(200);
    expect(res.json().orders).toHaveLength(2);
    expect(res.json().status).toBeNull();
  });
});

describe('кадр 03 — the order card', () => {
  it('serves the composition, the customer and the money for one order', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);

    const res = await get(`/admin/shop/orders/${id}`);
    expect(res.statusCode).toBe(200);
    const card = res.json();
    expect(card.order.id).toBe(id);
    expect(card.order.items.length).toBeGreaterThan(0);
    expect(card.order.items[0].qty).toBe(1);
    expect(card.order.city).toBe('Алматы');
    // The reference the operator reads out. Derived from the real id, never a
    // counter invented for the screen.
    expect(id.startsWith(card.ref)).toBe(true);
  });

  it('says the payment is not recorded, because no column records it', async () => {
    // There is no payment method, no paid flag and no transaction id anywhere
    // in the schema; orders are cash on delivery. A blank field would be read
    // as «не оплачено», so the card carries the absence in words.
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    const card = (await get(`/admin/shop/orders/${id}`)).json();
    expect(card.payment.recorded).toBe(false);
    expect(card.payment.note).toMatch(/не хранятся/i);
    expect(card.payment.totalMinor).toBe(card.order.totalMinor);
  });

  it('builds a WhatsApp link carrying the order reference', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    const card = (await get(`/admin/shop/orders/${id}`)).json();
    expect(card.whatsapp).toContain('https://wa.me/');
    expect(decodeURIComponent(card.whatsapp)).toContain(card.ref);
  });

  it('returns null for a number nobody can write to, rather than a dead link', async () => {
    // Real case: an order taken over the phone with a landline, or with the
    // number left as a fragment. Offering «Написать в WhatsApp» there opens a
    // chat with nobody.
    const v = await stocked('watch');
    const res = await app.inject({
      method: 'POST', url: '/admin/shop/orders', headers: { cookie },
      payload: {
        customerName: 'Без номера', phone: '12345', city: 'Алматы',
        address: 'ул. Абая 1', items: [{ variantId: v, qty: 1 }],
      },
    });
    expect(res.statusCode).toBe(201);
    const card = (await get(`/admin/shop/orders/${res.json().id}`)).json();
    expect(card.whatsapp).toBeNull();
  });

  it('is a 404 for an order that is not there, not a 500', async () => {
    expect((await get('/admin/shop/orders/not-an-order')).statusCode).toBe(404);
  });

  it('records who moved the status, and shows it on the timeline', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);

    expect((await patch(`/admin/shop/orders/${id}`, { status: 'confirmed' })).statusCode).toBe(200);
    expect((await patch(`/admin/shop/orders/${id}`, { status: 'shipped' })).statusCode).toBe(200);

    const card = (await get(`/admin/shop/orders/${id}`)).json();
    const kinds = card.timeline.map((e: { kind: string }) => e.kind);
    expect(kinds[0], 'the card must open on the moment the order was created').toBe('created');
    expect(card.timeline).toHaveLength(3);
    expect(card.timeline[1].status).toBe('confirmed');
    expect(card.timeline[1].from).toBe('new');
    expect(card.timeline[2].status).toBe('shipped');
    // The name, not a UUID: «кто отменил заказ Айгуль» has to have a readable
    // answer, which is the whole reason the id is resolved here.
    expect(card.timeline[2].by).toBeTruthy();
    expect(card.timeline[2].by).not.toMatch(/^[0-9a-f-]{20,}$/);

    // Nothing is missing, so the card must NOT print the "history is
    // incomplete" warning — a warning that is always on is a warning nobody
    // reads.
    expect(card.historyGap).toBe(false);
  });

  it('re-selecting the same status does not add a step to the history', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    await patch(`/admin/shop/orders/${id}`, { status: 'shipped' });
    await patch(`/admin/shop/orders/${id}`, { status: 'shipped' });

    const card = (await get(`/admin/shop/orders/${id}`)).json();
    expect(card.timeline.filter((e: { kind: string }) => e.kind === 'status')).toHaveLength(1);
  });

  it('a card built with no events under a moved order admits the gap', () => {
    // Every order placed before migration 039 is in this state, and there is no
    // way to reach it through the routes any more — the repository writes an
    // event with every move — so the rule is asserted where it lives.
    //
    // An empty timeline under a delivered order reads as "nothing ever happened
    // to it", which is the one thing a history must never say.
    const moved = buildOrderTimeline(
      { createdAt: '2026-07-01T09:00:00.000Z', status: 'delivered' }, [],
    );
    expect(moved.gap, 'a delivered order with no recorded steps must say so').toBe(true);
    expect(moved.entries).toHaveLength(1); // its creation, which the row does know

    // Untouched since it was placed: nothing is missing, so nothing is claimed.
    const fresh = buildOrderTimeline(
      { createdAt: '2026-07-01T09:00:00.000Z', status: 'new' }, [],
    );
    expect(fresh.gap).toBe(false);

    // Half a history is still a gap: the first recorded step does not start
    // from «Новый», so the steps before it were never written down.
    const partial = buildOrderTimeline(
      { createdAt: '2026-07-01T09:00:00.000Z', status: 'delivered' },
      [{
        id: 1, orderId: 'o', fromStatus: 'shipped', toStatus: 'delivered',
        staffId: 's1', staffName: 'Нуржан', at: '2026-07-03T10:00:00.000Z',
      }],
    );
    expect(partial.gap).toBe(true);
  });

  it('the cancellation shown on the timeline is the one the shelf saw', async () => {
    // The two must agree: cancelling returns the stock, and the history is
    // written inside the same call. A timeline that disagrees with the ledger
    // is worse than no timeline.
    const v = await stocked('watch', 3);
    const [id] = await placeOrders(1, v);
    const afterSale = (await repo.adminShopVariants()).find((x) => x.id === v)!.stock;
    expect(afterSale).toBe(2);

    await patch(`/admin/shop/orders/${id}`, { status: 'cancelled' });
    expect((await repo.adminShopVariants()).find((x) => x.id === v)!.stock).toBe(3);

    const card = (await get(`/admin/shop/orders/${id}`)).json();
    const last = card.timeline[card.timeline.length - 1];
    expect(last.status).toBe('cancelled');
    expect(last.from).toBe('new');
  });

  it('is audited — the card names one customer, her address and her number', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    await get(`/admin/shop/orders/${id}`);

    const rows = (await repo.listAudit(50)).entries;
    const entry = rows.find((r) => r.action === 'view_shop_order' && r.target === id);
    expect(entry, 'opening a customer card left no trace').toBeTruthy();
  });
});

/**
 * The route the panel never called.
 *
 * GET /admin/shop/orders/:id/devices was finished, audited and wired to
 * nothing: the panel only ever POSTed serials. A packer could bind a unit and
 * had no way to see what was already on the order, so every re-bind was blind
 * and a doubled unit only surfaced as a warranty case nobody could trace.
 */
describe('the serials bound to an order are readable', () => {
  it('returns what was bound, through the route the card calls', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    const received = await app.inject({
      method: 'POST', url: '/admin/device-registry', headers: { cookie },
      payload: { serials: 'AA:BB:CC:DD:EE:01\nAA:BB:CC:DD:EE:02', kind: 'band' },
    });
    expect(received.statusCode, received.body).toBe(200);

    const bind = await app.inject({
      method: 'POST', url: `/admin/shop/orders/${id}/devices`, headers: { cookie },
      payload: { serials: 'AA:BB:CC:DD:EE:01' },
    });
    expect(bind.statusCode).toBe(200);

    const res = await get(`/admin/shop/orders/${id}/devices`);
    expect(res.statusCode).toBe(200);
    const serials = res.json().devices.map((d: { serial: string }) => d.serial);
    expect(serials).toHaveLength(1);
    expect(serials[0].replace(/[^0-9a-z]/gi, '').toUpperCase()).toContain('AABBCCDDEE01');
  });
});

describe('the status vocabulary is one list', () => {
  it('refuses a status outside it and leaves the order alone', async () => {
    const v = await stocked('watch');
    const [id] = await placeOrders(1, v);
    const res = await patch(`/admin/shop/orders/${id}`, { status: 'оплачен' as ShopOrderStatus });
    expect(res.statusCode).toBe(400);
    expect((await repo.shopOrderById(id))!.status).toBe('new');
    // And nothing was written to the history either.
    expect(await repo.shopOrderEvents(id)).toEqual([]);
  });
});
