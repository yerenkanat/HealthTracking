/**
 * Stock control from the back office.
 *
 * The panel had one control: type a number into a colour and it was saved. That
 * is a stock LEVEL, not stock control — it cannot say what arrived, what was
 * sold, what broke, or who changed it, so a disagreement between the shelf and
 * the screen had nowhere to be resolved.
 *
 * These routes are the ledger's edge. Receiving and writing off are separate
 * verbs because they mean different things to whoever reads the history later;
 * a correction exists for when a stocktake simply disagrees.
 *
 * Admin-only. A stock movement is a financial record — it changes what the
 * business believes it owns — and unlike a lead status it cannot be undone by
 * setting it back.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository, StaffRole } from '../db/repository';
import { can, type Capability } from '../auth/capabilities';
import { needsReorder, runwayOf } from '../inventory/runway';

/**
 * How far back to look when measuring how fast something sells, and how long a
 * resupply takes.
 *
 * 30 days because this catalogue is six products and a week's window on a
 * business this size is mostly noise; 14 because the shipments come from
 * abroad. Both travel to the panel in the response, so the sentence it writes
 * («хватит на 9 дней») can say which numbers it was computed from.
 */
const SALES_WINDOW_DAYS = 30;
const LEAD_TIME_DAYS = 14;

export type AuthAdmin = (
  req: FastifyRequest,
) => Promise<{ staffId: string; role: StaffRole } | null>;

const productBody = z.object({
  id: z.string().trim().min(1).max(40).regex(/^[a-z0-9-]+$/, 'lowercase letters, digits and dashes'),
  name: z.string().trim().min(1).max(120),
  priceMinor: z.number().int().min(0),
  costMinor: z.number().int().min(0).nullable().optional(),
  sku: z.string().trim().max(60).nullable().optional(),
  kind: z.enum(['simple', 'bundle']).optional(),
  lowStockThreshold: z.number().int().min(0).max(10000).optional(),
  active: z.boolean().optional(),
  sort: z.number().int().min(0).max(1000).optional(),
});

const partsBody = z.object({
  parts: z.array(z.object({
    partId: z.string().trim().min(1).max(40),
    qty: z.number().int().min(1).max(100),
  })).max(20),
});

/// Serials pasted from a packing list: one per line, or comma separated.
const serialsBody = z.object({
  serials: z.string().min(1).max(20000),
  kind: z.enum(['band', 'tag']).optional(),
  note: z.string().trim().max(200).optional(),
});

const statusBody = z.object({
  status: z.enum(['stock', 'sold', 'blocked']),
});

/// A shipment arriving: how many, of what, and which physical units.
const receiptBody = z.object({
  variantId: z.string().trim().min(1),
  qty: z.number().int().min(1).max(100000),
  /// Optional. A shipment of straps has no serials; a shipment of watches does.
  serials: z.string().max(20000).optional(),
  kind: z.enum(['band', 'tag']).optional(),
  note: z.string().trim().max(300).optional(),
});

/// A counted shelf. The cap is the whole catalogue several times over.
const stocktakeBody = z.object({
  counts: z.array(z.object({
    variantId: z.string().trim().min(1),
    counted: z.number().int().min(0).max(100000),
  })).min(1).max(500),
  note: z.string().trim().max(300).optional(),
});

/// Serials as they are pasted: one per line, or comma separated, or both.
/// Nobody types forty MACs into forty fields, and a UI that made them would
/// simply not be used.
function splitSerials(raw: string): string[] {
  return raw.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean);
}

const moveBody = z.object({
  variantId: z.string().trim().min(1),
  // Signed, and non-zero: "changed by nothing" is not an event.
  delta: z.number().int().refine((n) => n !== 0, 'delta must not be zero'),
  reason: z.enum(['receipt', 'sale', 'return', 'writeoff', 'correction']),
  note: z.string().trim().max(300).optional(),
});

export function registerInventoryRoutes(
  app: FastifyInstance,
  repo: Repository,
  authAdmin: AuthAdmin,
): void {
  /**
   * The warehouse. Guarded on `stock`, so the hand who receives shipments and
   * counts shelves can do the job without also being an owner — which is what
   * `role !== 'admin'` forced, and why in practice one person did everything.
   */
  async function requireCap(req: FastifyRequest, reply: FastifyReply, cap: Capability) {
    const s = await authAdmin(req);
    if (!s) { reply.code(401).send({ error: 'unauthorized' }); return null; }
    if (!can(s.role, cap)) { reply.code(403).send({ error: 'forbidden', need: cap }); return null; }
    return s;
  }

  // ---- The warehouse view ---------------------------------------------------
  // ---- Which devices are ours (migration 028) -----------------------------
  //
  // Serials are recorded when a shipment is received — the same moment stock
  // goes onto the ledger. That is the only new warehouse work, and it is what
  // decides whether the pairing check protects anything or refuses customers.
  app.get('/admin/device-registry', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const limit = Math.min(1000, Math.max(1, Number((req.query as { limit?: string }).limit) || 200));
    // Audited, like the entitlement list and for the same reason: every sold
    // row carries the phone number of the customer who activated it. This is a
    // read of personal data, not an aggregate.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_device_registry' });
    return reply.send({ devices: await repo.listDeviceRegistry(limit) });
  });

  app.post('/admin/device-registry', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = serialsBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    // Pasted from a packing list. Same parser as Приёмка uses, so a list that
    // splits one way here cannot split another way there.
    const rows = splitSerials(parsed.data.serials)
      .map((serial) => ({
        serial,
        kind: parsed.data.kind ?? null,
        note: parsed.data.note ?? null,
        addedBy: s.staffId,
      }));
    if (rows.length === 0) return reply.code(400).send({ error: 'no_serials' });

    const result = await repo.addDeviceSerials(rows);
    await repo.writeAudit({ staffId: s.staffId, action: 'device_serials_add', target: `${result.added}` });
    return reply.send({ ok: true, ...result });
  });

  app.post('/admin/device-registry/:serial/status', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { serial } = req.params as { serial: string };
    const parsed = statusBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });
    await repo.setDeviceRegistryStatus(serial, parsed.data.status);
    // Blocking a unit is how a stolen or warranty-swapped device stops working,
    // so it is a named action in the log rather than an anonymous edit.
    await repo.writeAudit({
      staffId: s.staffId, action: `device_${parsed.data.status}`, target: serial,
    });
    return reply.send({ ok: true });
  });

  app.get('/admin/inventory', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const products = await repo.adminProducts();
    // Bundle composition travels with the product, so the panel can show what a
    // combo is made of without a request per product.
    // How fast the shelf is emptying, so a level can be read as a date.
    //
    // The panel's only reorder signal was a threshold somebody typed in once:
    // one number, right for one sales rate and wrong for every other, and
    // silent about whether what is left survives the two weeks a shipment
    // takes. Absent on an unmigrated database rather than fatal — a missing
    // ledger should cost the runway column, not the whole warehouse screen.
    const since = new Date(Date.now() - SALES_WINDOW_DAYS * 86400_000).toISOString();
    const sold = await repo.soldUnitsSince(since).catch(() => ({} as Record<string, number>));

    const withParts = await Promise.all(products.map(async (p) => {
      const runway = runwayOf(p.stock, sold[p.id] ?? 0, SALES_WINDOW_DAYS);
      return {
        ...p,
        parts: p.kind === 'bundle' ? await repo.bundleParts(p.id) : [],
        soldInWindow: sold[p.id] ?? 0,
        // JSON has no Infinity — it serialises as null, which would be
        // indistinguishable from "not computed". `noSales` carries that case.
        daysOfCover: runway && Number.isFinite(runway.days) ? runway.days : null,
        perDay: runway ? Number(runway.perDay.toFixed(2)) : null,
        noSales: runway ? runway.noSales : true,
        reorder: needsReorder(runway),
      };
    }));

    return reply.send({
      products: withParts,
      windowDays: SALES_WINDOW_DAYS,
      leadTimeDays: LEAD_TIME_DAYS,
      // The threshold list stays: it is what a warehouse hand set by hand for
      // the things they know about. `reorder` is the computed opinion, and the
      // two disagreeing is information rather than a bug.
      lowStock: withParts.filter((p) => p.lowStock).map((p) => p.id),
      reorder: withParts.filter((p) => p.reorder).map((p) => p.id),
    });
  });

  app.put('/admin/inventory/products', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = productBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    await repo.upsertProduct(parsed.data);
    await repo.writeAudit({ staffId: s.staffId, action: 'product_upsert', target: parsed.data.id });
    return reply.send({ ok: true });
  });

  app.put('/admin/inventory/products/:id/parts', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = partsBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });
    // A bundle containing itself makes its own stock unanswerable.
    if (parsed.data.parts.some((p) => p.partId === id)) {
      return reply.code(400).send({ error: 'bundle_contains_itself' });
    }
    await repo.setBundleParts(id, parsed.data.parts);
    await repo.writeAudit({ staffId: s.staffId, action: 'bundle_parts', target: id });
    return reply.send({ ok: true });
  });

  // ---- Moving stock ---------------------------------------------------------
  app.post('/admin/inventory/moves', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = moveBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const res = await repo.moveStock({ ...parsed.data, staffId: s.staffId });
    if (!res.ok) {
      // 409 rather than 400: the request was well formed and the world refused
      // it. "You cannot write off five of a thing you have two of" is not the
      // same mistake as sending a malformed body, and the panel says so.
      return reply.code(409).send({ error: res.error });
    }
    await repo.writeAudit({ staffId: s.staffId, action: 'stock_move', target: parsed.data.variantId });
    return reply.send({ ok: true, stock: res.stock });
  });

  /**
   * Приёмка — a shipment arriving, as ONE action.
   *
   * It was two, done in different places, and nothing tied them together: you
   * typed +10 against a colour on the Склад tab, then pasted forty MACs into
   * the device registry box further down. Whichever half somebody forgot was
   * invisible until it mattered — a shelf count that disagrees with the ledger,
   * or a customer whose brand-new watch the pairing check does not recognise.
   *
   * The quantity and the serials are now the same request. When both are given
   * they must AGREE: forty serials against a quantity of thirty means the
   * packing list and the box disagree, and the right answer is to stop and look
   * rather than to book whichever number was typed second.
   */
  app.post('/admin/inventory/receipt', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = receiptBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    const { variantId, qty, kind, note } = parsed.data;
    const serials = splitSerials(parsed.data.serials ?? '');

    if (serials.length && serials.length !== qty) {
      return reply.code(409).send({
        error: 'serial_count_mismatch',
        qty,
        serials: serials.length,
        message: `В поставке ${qty} шт., а серийных номеров ${serials.length}. ` +
          'Проверьте упаковочный лист — расхождение здесь означает, что на полке ' +
          'и в журнале будут разные числа.',
      });
    }

    // Stock first. If the serial write fails afterwards the shelf is right and
    // the registry is short, which a second Приёмка fixes because
    // addDeviceSerials is idempotent per serial. The other order would book
    // serials for units that never went onto the shelf.
    const moved = await repo.moveStock({
      variantId, delta: qty, reason: 'receipt', staffId: s.staffId,
      note: note ?? 'приёмка',
    });
    if (!moved.ok) return reply.code(409).send({ error: moved.error });

    let added = 0;
    let skipped = 0;
    if (serials.length) {
      const res = await repo.addDeviceSerials(serials.map((serial) => ({
        serial, kind: kind ?? null, note: note ?? null, addedBy: s.staffId,
      })));
      added = res.added;
      skipped = res.skipped;
    }

    await repo.writeAudit({ staffId: s.staffId, action: 'stock_receipt', target: variantId });
    return reply.send({
      ok: true,
      stock: moved.stock,
      serialsAdded: added,
      // Not an error. Receiving the same packing list twice is a normal thing
      // to do when somebody is unsure whether the first attempt went through,
      // and reporting the number is how they find out.
      serialsSkipped: skipped,
    });
  });

  /**
   * Инвентаризация — count the shelf, book the difference.
   *
   * The panel could only say "set this to 12", which loses the one fact a
   * stocktake exists to record: that it USED to say 15 and three are gone. The
   * difference is written as a `correction` row with the counted number in its
   * note, so the history answers "when did we last count, and what did we
   * find" rather than showing an unexplained edit.
   *
   * Variants that match are reported and NOT written. A ledger row saying
   * "changed by nothing" is noise in the one place noise is expensive.
   */
  app.post('/admin/inventory/stocktake', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = stocktakeBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }

    // One snapshot of the shelf, read before anything is written.
    const before = new Map<string, number>();
    for (const p of await repo.adminProducts()) {
      for (const v of p.variants) before.set(v.id, v.stock);
    }

    const unknown = parsed.data.counts.filter((c) => !before.has(c.variantId)).map((c) => c.variantId);
    if (unknown.length) {
      // All-or-nothing: half a stocktake is worse than none, because the half
      // that applied looks like a completed count.
      return reply.code(400).send({ error: 'unknown_variant', variants: unknown });
    }

    const lines: Array<{
      variantId: string; before: number; counted: number; delta: number; applied: boolean;
    }> = [];
    const refused: string[] = [];
    for (const { variantId, counted } of parsed.data.counts) {
      const was = before.get(variantId)!;
      const delta = counted - was;
      // A row saying "changed by nothing" is noise in the one place noise is
      // expensive. (The repository refuses a zero delta too — this is here so
      // the skip is a decision rather than a swallowed error.)
      if (delta === 0) {
        lines.push({ variantId, before: was, counted, delta, applied: false });
        continue;
      }
      const moved = await repo.moveStock({
        variantId, delta, reason: 'correction', staffId: s.staffId,
        note: `инвентаризация: было ${was}, посчитано ${counted}` +
          (parsed.data.note ? ` — ${parsed.data.note}` : ''),
      });
      // Not assumed. A correction the ledger rejected — a variant deleted
      // between the snapshot and the write — would otherwise be reported back
      // as a completed count of a shelf nothing was written for.
      if (!moved.ok) refused.push(variantId);
      lines.push({ variantId, before: was, counted, delta, applied: moved.ok });
    }

    await repo.writeAudit({
      staffId: s.staffId, action: 'stocktake',
      target: `${lines.filter((l) => l.delta !== 0).length}/${lines.length}`,
    });
    return reply.send({
      // False when any correction was rejected. The panel says so rather than
      // reporting a count that did not fully happen as done.
      ok: refused.length === 0,
      refused,
      lines,
      // The two numbers somebody actually reads afterwards: how much of the
      // shelf disagreed, and by how much in total. Counted over what was
      // APPLIED, so a rejected line cannot inflate either.
      changed: lines.filter((l) => l.applied).length,
      netDelta: lines.reduce((n, l) => n + (l.applied ? l.delta : 0), 0),
    });
  });

  app.get('/admin/inventory/moves', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const q = req.query as { variantId?: string; limit?: string };
    const limit = Math.min(500, Math.max(1, Number(q.limit) || 100));
    return reply.send({ moves: await repo.stockMoves(limit, q.variantId) });
  });
}
