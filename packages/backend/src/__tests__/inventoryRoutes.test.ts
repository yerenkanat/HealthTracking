/**
 * The back office's edge onto the stock ledger.
 *
 * A stock movement is a financial record: it changes what the business believes
 * it owns, and unlike a lead status it cannot be undone by setting it back. So
 * these are admin-only, and a refusal has to be told apart from a mistake.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
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
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const send = (method: 'POST' | 'PUT', url: string, payload: unknown) =>
  app.inject({ method, url, payload: payload as never, headers: { cookie } });

const firstVariant = async () => {
  const products = (await get('/admin/inventory')).json().products;
  return products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
};

describe('the warehouse view', () => {
  it('lists every product with its price, stock and composition', async () => {
    const res = await get('/admin/inventory');
    expect(res.statusCode).toBe(200);
    const { products } = res.json();

    const watch = products.find((p: { id: string }) => p.id === 'watch');
    expect(watch.priceMinor).toBeGreaterThan(0);
    expect(watch.variants.length).toBeGreaterThan(0);

    // The combo has to appear here even though it is not on the storefront —
    // this is the screen where its price and availability are managed.
    const combo = products.find((p: { id: string }) => p.id === 'combo');
    expect(combo, 'the bundle is invisible in the back office').toBeTruthy();
    expect(combo.kind).toBe('bundle');
    expect(combo.parts.map((x: { partId: string }) => x.partId).sort()).toEqual(['tracker', 'watch']);
  });

  it('flags what is running out', async () => {
    const { lowStock } = (await get('/admin/inventory')).json();
    expect(lowStock, 'nothing in stock and nothing flagged').toContain('watch');
  });
});

describe('moving stock', () => {
  it('records a receipt against the person who entered it', async () => {
    const v = await firstVariant();
    const res = await send('POST', '/admin/inventory/moves', {
      variantId: v, delta: 40, reason: 'receipt', note: 'накладная 118',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().stock).toBe(40);

    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves[0].reason).toBe('receipt');
    expect(moves[0].staffId, 'a movement nobody is accountable for').toBeTruthy();
  });

  it('refuses to write off more than exists, and says which kind of refusal', async () => {
    // 409, not 400: the request was well formed and the world refused it. "You
    // cannot write off five of a thing you have two of" is not a malformed body.
    const v = await firstVariant();
    await send('POST', '/admin/inventory/moves', { variantId: v, delta: 2, reason: 'receipt' });

    const res = await send('POST', '/admin/inventory/moves', { variantId: v, delta: -5, reason: 'writeoff' });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('insufficient_stock');

    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves, 'a refused move was recorded as if it happened').toHaveLength(1);
  });

  it('refuses a zero movement — that is not an event', async () => {
    const v = await firstVariant();
    expect((await send('POST', '/admin/inventory/moves', { variantId: v, delta: 0, reason: 'correction' })).statusCode).toBe(400);
  });
});

describe('products', () => {
  it('can be created and priced', async () => {
    const res = await send('PUT', '/admin/inventory/products', {
      id: 'strap', name: 'Ремешок', priceMinor: 350000, costMinor: 120000, lowStockThreshold: 5,
    });
    expect(res.statusCode).toBe(200);

    const { products } = (await get('/admin/inventory')).json();
    const strap = products.find((p: { id: string }) => p.id === 'strap');
    expect(strap.priceMinor).toBe(350000);
    expect(strap.costMinor).toBe(120000);
  });

  /// The article code.
  ///
  /// The column has existed since migration 021, uniquely indexed and
  /// documented as "what goes on a box, an invoice and a courier's manifest".
  /// The API has accepted it the whole time and the panel had nowhere to type
  /// one, so every manifest was written from the product name.
  it('keeps the article code it was given', async () => {
    await send('PUT', '/admin/inventory/products', {
      id: 'strap', name: 'Ремешок', priceMinor: 350000, sku: 'AB-STRAP-01',
    });
    const { products } = (await get('/admin/inventory')).json();
    expect(products.find((p: { id: string }) => p.id === 'strap').sku).toBe('AB-STRAP-01');
  });

  it('takes null for a product that has no code, rather than an empty one', async () => {
    // The index is UNIQUE. Two products saved with '' would collide on a code
    // neither of them has, and the second save would be refused for a reason
    // nobody could see.
    for (const id of ['strap', 'strap-2']) {
      const res = await send('PUT', '/admin/inventory/products', {
        id, name: 'Ремешок', priceMinor: 350000, sku: null,
      });
      expect(res.statusCode, id).toBe(200);
    }
    const { products } = (await get('/admin/inventory')).json();
    expect(products.find((p: { id: string }) => p.id === 'strap-2').sku).toBeNull();
  });

  it('refuses an id that would not survive a URL', async () => {
    const res = await send('PUT', '/admin/inventory/products', {
      id: 'Ремешок 2!', name: 'x', priceMinor: 1,
    });
    expect(res.statusCode).toBe(400);
  });

  it('refuses a bundle that contains itself', async () => {
    // Its available stock would be defined in terms of itself.
    const res = await send('PUT', '/admin/inventory/products/combo/parts', {
      parts: [{ partId: 'combo', qty: 1 }],
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bundle_contains_itself');
  });
});

/**
 * Поставки — кадры 07a «Поставки» и 07g «Поставщики».
 *
 * The warehouse could answer "what is on the shelf" and "how long does it
 * last". It could not answer the third question, which is the one that decides
 * whether to order today: "what is already coming". So the screen printed
 * «пора заказывать» beside goods ordered a fortnight ago, and a buyer either
 * ordered them twice or stopped believing the banner.
 *
 * Driven over HTTP against the real memory repository, because the failure
 * these routes exist to prevent is a chain that breaks between its links.
 */
describe('поставки в пути', () => {
  /**
   * A shelf that IS running out: ten units left, one sold a day, and a
   * shipment takes fourteen. `needsReorder` is true here, and every assertion
   * below is about what happens to that flag.
   */
  async function runningOut() {
    const v = await firstVariant();
    expect((await send('POST', '/admin/inventory/moves', {
      variantId: v, delta: 40, reason: 'receipt',
    })).statusCode).toBe(200);
    expect((await send('POST', '/admin/inventory/moves', {
      variantId: v, delta: -30, reason: 'sale',
    })).statusCode).toBe(200);
    return v;
  }

  const watchOf = async () =>
    (await get('/admin/inventory')).json().products.find((p: { id: string }) => p.id === 'watch');

  const placeOrder = async (variantId: string, qtyOrdered: number, supplierId?: string) => {
    const res = await send('POST', '/admin/purchase-orders', {
      supplierId: supplierId ?? null, items: [{ variantId, qtyOrdered }],
    });
    expect(res.statusCode, JSON.stringify(res.json())).toBe(200);
    return res.json() as { id: string; status: string };
  };

  it('the shelf without an order says «пора заказывать»', async () => {
    // The baseline every other test here is a change to. Without it, a
    // suppressed flag would prove nothing — it could simply never have been on.
    await runningOut();
    const watch = await watchOf();
    expect(watch.stock).toBe(10);
    expect(watch.reorder, 'ten units at one a day against a 14-day lead time').toBe(true);
    expect(watch.reorderCovered).toBe(false);
    expect(watch.inTransit).toBe(0);
  });

  it('a placed order shows as in transit, and is NOT added to stock', async () => {
    // The trap this whole feature is built around: a box in customs is not a
    // shelf. A forecast that counts it promises stock nobody can ship today.
    const v = await runningOut();
    await placeOrder(v, 20);

    const watch = await watchOf();
    expect(watch.inTransit).toBe(20);
    expect(watch.stock, 'units on the water were added to the shelf').toBe(10);
    expect(watch.daysOfCover, 'the runway counted goods that have not arrived').toBe(10);
    expect(watch.variants.find((x: { id: string }) => x.id === v).inTransit).toBe(20);
  });

  it('suppresses «пора заказывать» while the order is open, and says why', async () => {
    const v = await runningOut();
    await placeOrder(v, 20);

    const watch = await watchOf();
    expect(watch.reorder, 'the buyer is told to order what is already ordered').toBe(false);
    // Not silently dropped: the shelf is still short, and a buyer who cannot
    // see that the answer is "already ordered" learns to distrust the screen.
    expect(watch.reorderCovered).toBe(true);
    const { reorder, reorderCovered } = (await get('/admin/inventory')).json();
    expect(reorder).not.toContain('watch');
    expect(reorderCovered).toContain('watch');
  });

  it('an order too small to cover the gap does NOT suppress it', async () => {
    // «Уже заказано» is a judgement about a QUANTITY. One strap on the water
    // must not silence a warning about forty watches.
    const v = await runningOut();
    await placeOrder(v, 1);

    const watch = await watchOf();
    expect(watch.inTransit).toBe(1);
    expect(watch.reorder, 'one unit on order silenced the whole warning').toBe(true);
    expect(watch.reorderCovered).toBe(false);
  });

  it('a draft is not in transit — nothing is coming until somebody sends it', async () => {
    const v = await runningOut();
    const res = await send('POST', '/admin/purchase-orders', {
      items: [{ variantId: v, qtyOrdered: 20 }], place: false,
    });
    expect(res.json().status).toBe('draft');

    const watch = await watchOf();
    expect(watch.inTransit).toBe(0);
    expect(watch.reorder).toBe(true);

    // …and placing it changes exactly that.
    expect((await send('POST', `/admin/purchase-orders/${res.json().id}/place`, {})).statusCode).toBe(200);
    expect((await watchOf()).inTransit).toBe(20);
  });

  it('a cancelled order stops being in transit', async () => {
    const v = await runningOut();
    const po = await placeOrder(v, 20);
    expect((await send('POST', `/admin/purchase-orders/${po.id}/cancel`, {})).statusCode).toBe(200);

    const watch = await watchOf();
    expect(watch.inTransit).toBe(0);
    expect(watch.reorder, 'a cancelled order kept silencing the warning').toBe(true);
  });

  it('a receipt short of what was ORDERED records the claim and closes the order', async () => {
    const v = await runningOut();
    const po = await placeOrder(v, 20);

    const res = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 18 });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    // The claim is measured against the ORDER, not the supplier's own invoice:
    // what we are owed is what we ordered.
    expect(body.shortfall).toBe(2);
    expect(body.shortfallBasis).toBe('order');
    expect(body.orderedQty).toBe(20);
    // A short delivery still closes the line — the shortfall is already
    // recorded — or those two units stay «в пути» for ever.
    expect(body.poLineClosed).toBe(true);
    expect(body.poStatus).toBe('received');

    const { orders } = (await get('/admin/purchase-orders')).json();
    expect(orders[0].status).toBe('received');
    expect(orders[0].items[0].qtyReceived).toBe(18);

    // And what actually arrived is on the shelf, with nothing left in transit.
    const watch = await watchOf();
    expect(watch.stock).toBe(28);
    expect(watch.inTransit).toBe(0);

    // The claim is in the ledger, where a person looking for it will find it.
    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves[0].note).toContain('недостача 2');
    expect(moves[0].note).toContain('заказа (20)');
  });

  it('a second box against the same order is claimed against the REMAINDER', async () => {
    // Order twenty, twelve turn up, then the other eight. The claim on the
    // first box is eight; on the second it is nothing. Measuring the second box
    // against the full twenty again — which is what the route used to do —
    // records the whole order as missing while every unit sits on the shelf.
    const v = await runningOut();
    const po = await placeOrder(v, 20);

    const first = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 12 });
    expect(first.statusCode).toBe(200);
    expect(first.json().shortfall).toBe(8);
    expect(first.json().orderedQty).toBe(20);

    const second = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 8 });
    expect(second.statusCode).toBe(200);
    const body = second.json();
    expect(body.shortfall, 'the units of the first box were claimed for a second time').toBe(0);
    expect(body.orderedQty, 'the basis was the whole line, not what was still owed').toBe(8);
    expect(body.orderedTotalQty).toBe(20);
    expect(body.alreadyReceivedQty).toBe(12);

    // The order itself is whole, and so is the shelf.
    const { orders } = (await get('/admin/purchase-orders')).json();
    expect(orders[0].items[0].qtyReceived).toBe(20);
    expect((await watchOf()).stock).toBe(30);

    // And the ledger carries ONE claim for eight units, not two claims for
    // twenty against an order that arrived complete.
    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    const claims = moves.filter((m: { note: string | null }) => (m.note ?? '').includes('недостача'));
    expect(claims).toHaveLength(1);
    expect(claims[0].note).toContain('недостача 8');
  });

  it('a third box beyond the order is an EXCESS, measured against what was left', async () => {
    const v = await runningOut();
    const po = await placeOrder(v, 20);
    await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 20 });

    const extra = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 3 });
    expect(extra.statusCode).toBe(200);
    // Nothing was outstanding, so three more units are three too many — not a
    // claim for seventeen missing ones.
    expect(extra.json().orderedQty).toBe(0);
    expect(extra.json().shortfall).toBe(-3);
    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves[0].note).toContain('излишек 3');
    expect(moves[0].note).toContain('принято 20');
  });

  it('refuses a receipt booked against a CANCELLED order', async () => {
    // The line would close and a cancelled order would quietly absorb a
    // delivery nobody can reconcile against anything.
    const v = await runningOut();
    const po = await placeOrder(v, 20);
    expect((await send('POST', `/admin/purchase-orders/${po.id}/cancel`, {})).statusCode).toBe(200);

    const res = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 20 });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('purchase_order_cancelled');
    // Nothing moved: not the shelf, and not the order's lines.
    expect((await watchOf()).stock).toBe(10);
    const { orders } = (await get('/admin/purchase-orders')).json();
    expect(orders[0].status).toBe('cancelled');
    expect(orders[0].items[0].qtyReceived).toBe(0);
    // …and the delivery is still bookable the honest way.
    expect((await send('POST', '/admin/inventory/receipt', { variantId: v, qty: 20 })).statusCode).toBe(200);
  });

  it('will not re-place an order that is not a draft', async () => {
    const v = await runningOut();
    const po = await placeOrder(v, 20);
    expect((await send('POST', `/admin/purchase-orders/${po.id}/cancel`, {})).statusCode).toBe(200);

    // Placing a cancelled order would resurrect it as «В пути» on the Поставки
    // table and silence «пора заказывать» over goods nobody is sending.
    const res = await send('POST', `/admin/purchase-orders/${po.id}/place`, {});
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('not_a_draft');
    expect(res.json().status).toBe('cancelled');
    const { orders } = (await get('/admin/purchase-orders')).json();
    expect(orders[0].status).toBe('cancelled');
    expect((await watchOf()).inTransit).toBe(0);
  });

  it('will not re-place an order that has already been received', async () => {
    // The other half of the same guard: re-placing a received order puts stock
    // that has already landed back on the water and counts it twice.
    const v = await runningOut();
    const po = await placeOrder(v, 20);
    await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 20 });

    const res = await send('POST', `/admin/purchase-orders/${po.id}/place`, {});
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('not_a_draft');
    expect((await watchOf()).inTransit).toBe(0);
  });

  it('receiving without an order works exactly as before', async () => {
    // «Приход без заказа» is a real event — a courier turns up with something
    // nobody raised an order for — and a form that demanded a PO would push
    // that delivery back onto the path where the shelf and the ledger disagree.
    const v = await firstVariant();
    const res = await send('POST', '/admin/inventory/receipt', { variantId: v, qty: 10, invoiceQty: 12 });
    expect(res.statusCode).toBe(200);
    expect(res.json().shortfall).toBe(2);
    expect(res.json().shortfallBasis).toBe('invoice');
    expect(res.json().poId).toBeNull();
    expect(res.json().stock).toBe(10);
  });

  it('refuses to book a receipt against an order that does not contain the colour', async () => {
    const v = await firstVariant();
    const other = (await get('/admin/inventory')).json()
      .products.find((p: { id: string }) => p.id === 'watch').variants[1].id;
    const po = await placeOrder(v, 20);

    const res = await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: other, qty: 5 });
    // 409, not 400: the request is well formed and the world refuses it.
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('variant_not_ordered');
    // Nothing was booked — a refused receipt must not move the shelf.
    const watch = await watchOf();
    expect(watch.stock).toBe(0);
  });

  it('refuses an order for a colour that does not exist', async () => {
    const res = await send('POST', '/admin/purchase-orders', {
      items: [{ variantId: 'no-such-variant', qtyOrdered: 5 }],
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('unknown_variant');
    expect((await get('/admin/purchase-orders')).json().orders).toHaveLength(0);
  });

  it('will not cancel a delivery that already happened', async () => {
    const v = await firstVariant();
    const po = await placeOrder(v, 5);
    await send('POST', '/admin/inventory/receipt', { poId: po.id, variantId: v, qty: 5 });

    const res = await send('POST', `/admin/purchase-orders/${po.id}/cancel`, {});
    // Cancelling it would claim stock on the shelf was never bought.
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('already_received');
  });
});

describe('поставщики', () => {
  it('are saved with the term they DECLARED, and read back', async () => {
    const res = await send('POST', '/admin/suppliers', {
      name: 'Shenzhen Watch Co', contact: '+86 755 000 00 00', leadTimeDays: 21,
    });
    expect(res.statusCode).toBe(200);

    const { suppliers, defaultLeadTimeDays } = (await get('/admin/suppliers')).json();
    expect(suppliers).toHaveLength(1);
    expect(suppliers[0].name).toBe('Shenzhen Watch Co');
    expect(suppliers[0].leadTimeDays).toBe(21);
    expect(suppliers[0].active).toBe(true);
    // The standing warehouse figure travels too, so the panel can label a
    // supplier who declared nothing as falling back to it rather than printing
    // it as though they had promised it.
    expect(defaultLeadTimeDays).toBe(14);
  });

  it('leaves the term null when nobody declared one, rather than inventing 14', async () => {
    // Nothing in this database has a placed→received pair yet, so a measured
    // lead time cannot exist. A confident wrong number is worse than none: a
    // buyer plans money against it.
    await send('POST', '/admin/suppliers', { name: 'Местный склад' });
    const { suppliers } = (await get('/admin/suppliers')).json();
    expect(suppliers[0].leadTimeDays).toBeNull();
  });

  it('names the supplier on the order, so a claim has somebody to go to', async () => {
    const { id } = (await send('POST', '/admin/suppliers', {
      name: 'Shenzhen Watch Co', leadTimeDays: 21,
    })).json();
    const v = await firstVariant();
    await send('POST', '/admin/purchase-orders', {
      supplierId: id, items: [{ variantId: v, qtyOrdered: 20 }],
    });

    const { orders } = (await get('/admin/purchase-orders')).json();
    expect(orders[0].supplierName).toBe('Shenzhen Watch Co');
    expect(orders[0].supplierLeadTimeDays).toBe(21);
    expect(orders[0].placedAt, 'a placed order with no placement time').toBeTruthy();
    // Never guessed. Nothing knows what a unit cost until a receipt carries a
    // batch cost, and printing a computed guess on a purchase order is how a
    // margin nobody is earning reaches the owner's dashboard.
    expect(orders[0].items[0].unitCostMinor).toBeNull();
  });

  it('is archived rather than deleted — the orders placed with them are history', async () => {
    const { id } = (await send('POST', '/admin/suppliers', { name: 'Старый поставщик' })).json();
    await send('POST', '/admin/suppliers', { id, name: 'Старый поставщик', active: false });
    const { suppliers } = (await get('/admin/suppliers')).json();
    expect(suppliers).toHaveLength(1);
    expect(suppliers[0].active).toBe(false);
  });

  it('stays archived when the same name is typed into the add form again', async () => {
    // The add form sends no `active` at all. Treating that as «active: true» —
    // which the pg ON CONFLICT used to do — puts a supplier the buyer
    // deliberately retired back into the «Заказ поставщику» dropdown.
    const { id } = (await send('POST', '/admin/suppliers', { name: 'Shenzhen Ltd' })).json();
    await send('POST', '/admin/suppliers', { id, name: 'Shenzhen Ltd', active: false });

    const again = await send('POST', '/admin/suppliers', { name: 'Shenzhen Ltd', contact: '+86 000' });
    expect(again.statusCode).toBe(200);
    expect(again.json().id, 'a second row with a name the unique index forbids').toBe(id);

    const { suppliers } = (await get('/admin/suppliers')).json();
    expect(suppliers).toHaveLength(1);
    expect(suppliers[0].active, 'an archived supplier was silently un-archived').toBe(false);
    // The fields that WERE sent still saved — this is an edit, not a refusal.
    expect(suppliers[0].contact).toBe('+86 000');
  });

  it('refuses to rename one onto another\'s name, and says which', async () => {
    // lower(name) is UNIQUE in Postgres. Two rows called «Beta» is a state
    // production cannot hold, and letting the constraint escape gave the
    // operator a 500 and the panel a generic «не удалось».
    const alpha = (await send('POST', '/admin/suppliers', { name: 'Alpha' })).json().id;
    await send('POST', '/admin/suppliers', { name: 'Beta' });

    const res = await send('POST', '/admin/suppliers', { id: alpha, name: 'Beta' });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('supplier_name_taken');
    expect(res.json().message).toContain('Beta');

    const { suppliers } = (await get('/admin/suppliers')).json();
    expect(suppliers.map((x: { name: string }) => x.name).sort()).toEqual(['Alpha', 'Beta']);
  });

  it('mints a new id when the one sent matches nothing, as Postgres would', async () => {
    // pg's UPDATE ... WHERE id = $1 affects no rows and the INSERT mints its
    // own uuid. A memory repo that honoured the caller's id would let a test
    // pass against a state production never produces.
    const res = await send('POST', '/admin/suppliers', { id: 'not-a-real-id', name: 'Новый' });
    expect(res.statusCode).toBe(200);
    expect(res.json().id).not.toBe('not-a-real-id');
    const { suppliers } = (await get('/admin/suppliers')).json();
    expect(suppliers).toHaveLength(1);
    expect(suppliers[0].id).toBe(res.json().id);
  });
});

/**
 * The half of the supplier upsert no test above can reach.
 *
 * Everything else here runs against the memory repository, and that is exactly
 * how this divergence survived: the memory repo left `active` alone when the
 * field was absent while the pg `ON CONFLICT` set it from `EXCLUDED.active`,
 * which the route defaulted to true. Behaviour "verified" in every test was the
 * opposite of production. Read from source rather than executed, because there
 * is no Postgres in this suite — and an assertion nobody can run is worth less
 * than a cheap one that fails the moment the statement drifts back.
 */
describe('архив поставщика — то же самое в pg', () => {
  const pgSource = readFileSync(
    fileURLToPath(new URL('../db/pgRepository.ts', import.meta.url)), 'utf8');
  const upsert = pgSource.slice(
    pgSource.indexOf('INSERT INTO suppliers'),
    pgSource.indexOf('async listPurchaseOrders'));

  it('does not resurrect an archived supplier when the form sends no `active`', () => {
    expect(upsert, 'the add form sends no `active`, and this made it true').not.toMatch(/active\s*=\s*EXCLUDED\.active/);
    expect(upsert).toMatch(/active\s*=\s*COALESCE\(\$4::boolean,\s*suppliers\.active\)/);
    // …and a brand-new supplier is still active, since "did not say" on an
    // insert is not the same question as "did not say" on an edit.
    expect(upsert).toMatch(/COALESCE\(\$4::boolean,\s*true\)/);
  });

  it('turns the unique-name violation into a refusal instead of a 500', () => {
    const method = pgSource.slice(
      pgSource.indexOf('async upsertSupplier'),
      pgSource.indexOf('async listPurchaseOrders'));
    expect(method, 'the constraint escapes as a 500 the panel cannot explain').toContain('23505');
    expect(method).toContain("error: 'name_taken'");
  });
});

describe('who may touch stock', () => {
  it('nobody, without a session', async () => {
    expect((await app.inject({ method: 'GET', url: '/admin/inventory' })).statusCode).toBe(401);
    expect((await app.inject({
      method: 'POST', url: '/admin/inventory/moves',
      payload: { variantId: 'x', delta: 1, reason: 'receipt' },
    })).statusCode).toBe(401);
  });

  it('and not a support account', async () => {
    await send('POST', '/admin/staff', {
      phone: '77011112233', displayName: 'Айгерім', role: 'support', password: 'nurse-password',
    });
    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: '77011112233', password: 'nurse-password' },
    });
    const theirs = String(login.headers['set-cookie'] ?? '').split(';')[0];

    const res = await app.inject({
      method: 'POST', url: '/admin/inventory/moves',
      payload: { variantId: await firstVariant(), delta: -1, reason: 'writeoff' },
      headers: { cookie: theirs },
    });
    expect(res.statusCode, 'support can write off stock').toBe(403);
  });
});
