/**
 * Приёмка and инвентаризация — the two warehouse jobs the panel could not do.
 *
 * Receiving a shipment WAS two actions in two places with nothing tying them
 * together: type +10 against a colour, then paste forty MACs into a different
 * box further down the page. Whichever half somebody forgot stayed invisible
 * until it mattered — a shelf that disagrees with the ledger, or a customer
 * whose brand-new watch the pairing check does not recognise as ours.
 *
 * A stocktake could not be done at all. The panel could only say "set this to
 * 12", which loses the fact the whole exercise exists to record: that it used
 * to say 15, and three are gone.
 *
 * Driven over HTTP, and the assertions are mostly about the LEDGER rather than
 * the level — a warehouse whose numbers are right and whose history is empty
 * cannot answer any question worth asking.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let app: FastifyInstance;
let repo: Repository;

beforeEach(() => {
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
      authAdmin: async () => ({ staffId: 's1', role: 'warehouse' as const }),
    },
    { logger: false },
  );
});

const post = (url: string, payload: unknown) =>
  app.inject({ method: 'POST', url, payload: payload as never });
const moves = async () =>
  (await app.inject({ method: 'GET', url: '/admin/inventory/moves?limit=100' })).json().moves;
const registry = async () =>
  (await app.inject({ method: 'GET', url: '/admin/device-registry' })).json().devices;

/** The first colour of the first real product — whatever the catalogue seeds. */
async function aVariant() {
  const p = (await repo.adminProducts()).find((x) => x.kind !== 'bundle' && x.variants.length)!;
  return { productId: p.id, variantId: p.variants[0].id, stock: p.variants[0].stock };
}
const stockOf = async (variantId: string) => {
  for (const p of await repo.adminProducts()) {
    const v = p.variants.find((x) => x.id === variantId);
    if (v) return v.stock;
  }
  throw new Error('no such variant');
};

describe('Приёмка: the shelf and the registry move together', () => {
  it('one request books the stock AND records the serials', async () => {
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', {
      variantId, qty: 3, kind: 'band',
      serials: 'AA:BB:CC:00:00:01\nAA:BB:CC:00:00:02\nAA:BB:CC:00:00:03',
      note: 'накладная 77',
    });
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().serialsAdded).toBe(3);
    expect(await stockOf(variantId)).toBe(stock + 3);
    expect((await registry()).length).toBe(3);
  });

  it('writes it to the ledger as a receipt, with the note', async () => {
    // The level without the history is a number nobody can argue with or
    // explain. The row is what makes a disagreement resolvable.
    const { variantId } = await aVariant();
    await post('/admin/inventory/receipt', { variantId, qty: 5, note: 'накладная 77' });
    const row = (await moves())[0];
    expect(row.reason).toBe('receipt');
    expect(row.delta).toBe(5);
    expect(row.note).toContain('накладная 77');
    expect(row.staffId).toBe('s1');
  });

  it('a shipment with no serials is fine — straps have none', async () => {
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', { variantId, qty: 12 });
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().serialsAdded).toBe(0);
    expect(await stockOf(variantId)).toBe(stock + 12);
  });

  it('accepts a short shipment and records the claim', async () => {
    // «Приёмка принимает факт, а не накладную.» This route used to refuse any
    // mismatch, which made the honest answer the impossible one: a warehouse
    // hand who cannot book a short delivery types the invoice number instead,
    // and from then on the shelf and the ledger disagree with no explanation.
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', { variantId, qty: 28, invoiceQty: 30 });

    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().shortfall).toBe(2);
    expect(res.json().stocked).toBe(28);
    // What arrived is on the shelf — the fact, not the invoice.
    expect(await stockOf(variantId)).toBe(stock + 28);
    expect((await moves())[0].note).toContain('недостача 2 шт.');
  });

  it('an over-shipment is recorded too, and is not a refusal either', async () => {
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', { variantId, qty: 32, invoiceQty: 30 });
    expect(res.json().shortfall).toBe(-2);
    expect(await stockOf(variantId)).toBe(stock + 32);
    expect((await moves())[0].note).toContain('излишек 2 шт.');
  });

  it('defective units are counted and not stocked', async () => {
    // They arrived — that is a fact — but shelving them sells one to somebody.
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', { variantId, qty: 30, defective: 2 });
    expect(res.json()).toMatchObject({ received: 30, stocked: 28, defective: 2 });
    expect(await stockOf(variantId)).toBe(stock + 28);
    expect((await moves())[0].note).toContain('брак 2 шт.');
  });

  it('recomputes unit cost over what can be SOLD, not what arrived', async () => {
    // «Себестоимость партии пересчитывается с учётом брака.» 280 000 ₸ over 28
    // sellable units is 10 000 each; dividing by the 30 that turned up would
    // report a margin the business is not earning — and margin is what the
    // owner's dashboard is built on.
    const { variantId, productId } = await aVariant();
    const res = await post('/admin/inventory/receipt', {
      variantId, qty: 30, defective: 2, batchCostMinor: 28_000_000,
    });
    expect(res.json().unitCostMinor).toBe(1_000_000);
    const product = (await repo.adminProducts()).find((p) => p.id === productId)!;
    expect(product.costMinor, 'the recomputed cost never reached the product').toBe(1_000_000);
  });

  it('a wholly defective delivery has nothing to stock, and says so', async () => {
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', { variantId, qty: 4, defective: 4 });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('nothing_usable');
    expect(res.json().message).toContain('претензию');
    expect(await stockOf(variantId)).toBe(stock);
  });

  it('refuses when the count and the SERIALS disagree — a serial is a unit', async () => {
    // Not the same thing as an invoice discrepancy, and not a claim against
    // anybody: it is two watches on our own shelf that the pairing check will
    // not recognise as ours.
    const { variantId, stock } = await aVariant();
    const res = await post('/admin/inventory/receipt', {
      variantId, qty: 5, serials: 'AA:BB:CC:00:00:01\nAA:BB:CC:00:00:02',
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('serial_count_mismatch');
    expect(res.json().message).toContain('Серийник — это единица товара');
    // And nothing was written — not the stock, not the serials.
    expect(await stockOf(variantId)).toBe(stock);
    expect(await registry()).toEqual([]);
  });

  it('receiving the same packing list twice reports it instead of duplicating', async () => {
    // A normal thing to do when somebody is unsure the first attempt went
    // through. The serials are idempotent; the number is how they find out.
    const { variantId } = await aVariant();
    const body = { variantId, qty: 2, kind: 'tag', serials: 'AABBCC000001, AABBCC000002' };
    await post('/admin/inventory/receipt', body);
    const second = await post('/admin/inventory/receipt', body);
    expect(second.json().serialsAdded).toBe(0);
    expect(second.json().serialsSkipped).toBe(2);
    expect((await registry()).length).toBe(2);
  });

  it('a warehouse hand can do it — that is the whole job', async () => {
    // The account this suite runs as is `warehouse`, which before the
    // capability model could not touch any of this without being an admin.
    const { variantId } = await aVariant();
    expect((await post('/admin/inventory/receipt', { variantId, qty: 1 })).statusCode).toBe(200);
  });
});

describe('Инвентаризация: count the shelf, book the difference', () => {
  async function seed(qty: number) {
    const { variantId } = await aVariant();
    await post('/admin/inventory/receipt', { variantId, qty });
    return variantId;
  }

  it('a short count is written as a correction naming both numbers', async () => {
    const variantId = await seed(15);
    const before = await stockOf(variantId);

    const res = await post('/admin/inventory/stocktake', {
      counts: [{ variantId, counted: before - 3 }], note: 'считала Айгерім',
    });
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().changed).toBe(1);
    expect(res.json().netDelta).toBe(-3);
    expect(await stockOf(variantId)).toBe(before - 3);

    const row = (await moves())[0];
    expect(row.reason).toBe('correction');
    expect(row.delta).toBe(-3);
    // Both numbers in the note. "Corrected by −3" cannot answer "from what?"
    // a month later, which is exactly when somebody asks.
    expect(row.note).toContain(`было ${before}`);
    expect(row.note).toContain(`посчитано ${before - 3}`);
    expect(row.note).toContain('считала Айгерім');
  });

  it('a count that matches writes nothing', async () => {
    // "Changed by nothing" is noise in the one place noise is expensive.
    // Both layers refuse a zero delta, so this asserts the outcome rather than
    // which layer produced it: the row is reported as counted-and-unchanged
    // and the ledger is exactly as long as it was.
    const variantId = await seed(9);
    const before = await stockOf(variantId);
    const countBefore = (await moves()).length;

    const res = await post('/admin/inventory/stocktake', { counts: [{ variantId, counted: before }] });
    expect(res.json().changed).toBe(0);
    expect(res.json().lines[0]).toMatchObject({ before, counted: before, delta: 0, applied: false });
    expect((await moves()).length).toBe(countBefore);
  });

  it('a correction the ledger rejects is reported, not counted as done', async () => {
    // The defect this exists for is repo-wide: a write whose result is never
    // read, reported back as success. Here it would mean a shelf somebody
    // believes was counted and corrected when nothing was written.
    const variantId = await seed(5);
    const before = await stockOf(variantId);
    const realMove = repo.moveStock.bind(repo);
    repo.moveStock = async (m) =>
      m.reason === 'correction'
        ? { ok: false as const, error: 'unknown_variant' as const }
        : realMove(m);

    const res = await post('/admin/inventory/stocktake', { counts: [{ variantId, counted: before - 2 }] });
    const body = res.json();
    expect(body.ok, 'a rejected correction was reported as a completed count').toBe(false);
    expect(body.refused).toEqual([variantId]);
    expect(body.changed).toBe(0);
    expect(body.netDelta).toBe(0);
    expect(body.lines[0].applied).toBe(false);
  });

  it('a surplus is a correction too, not something to hide', async () => {
    const variantId = await seed(4);
    const before = await stockOf(variantId);
    await post('/admin/inventory/stocktake', { counts: [{ variantId, counted: before + 2 }] });
    expect(await stockOf(variantId)).toBe(before + 2);
    expect((await moves())[0].delta).toBe(2);
  });

  it('reports every line, including the ones that agreed', async () => {
    // A stocktake that only reports discrepancies cannot show that the rest of
    // the shelf was actually counted.
    const { variantId } = await aVariant();
    const all = (await repo.adminProducts()).flatMap((p) => p.kind === 'bundle' ? [] : p.variants);
    const counts = all.map((v) => ({ variantId: v.id, counted: v.id === variantId ? v.stock + 1 : v.stock }));
    const res = await post('/admin/inventory/stocktake', { counts });
    expect(res.json().lines.length).toBe(all.length);
    expect(res.json().changed).toBe(1);
  });

  it('an unknown variant rejects the WHOLE count', async () => {
    // Half a stocktake is worse than none: the half that applied looks like a
    // completed count of the whole shelf.
    const variantId = await seed(7);
    const before = await stockOf(variantId);
    const res = await post('/admin/inventory/stocktake', {
      counts: [{ variantId, counted: 0 }, { variantId: 'no-such-variant', counted: 5 }],
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('unknown_variant');
    expect(await stockOf(variantId), 'the valid line was applied anyway').toBe(before);
  });

  it('an empty count is a bad request, not a silent no-op', async () => {
    expect((await post('/admin/inventory/stocktake', { counts: [] })).statusCode).toBe(400);
  });

  it('is audited, so the log says a count happened and how much moved', async () => {
    const variantId = await seed(6);
    const before = await stockOf(variantId);
    await post('/admin/inventory/stocktake', { counts: [{ variantId, counted: before - 1 }] });

    // Read through the repository, not /admin/audit: this suite is signed in
    // as `warehouse`, and the log is the `staff` capability. That it is
    // refused over HTTP is roleAccess.test.ts's job; what matters here is that
    // the row was written.
    const audit = await repo.listAudit(50);
    const row = audit.find((a) => a.action === 'stocktake');
    expect(row, 'a stocktake left no trace in the audit log').toBeDefined();
    expect(row!.target).toBe('1/1'); // one line changed of one counted
  });
});
