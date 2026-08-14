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
import type { Repository, StaffRole, PurchaseOrder } from '../db/repository';
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

/**
 * A shipment arriving.
 *
 * «Приёмка принимает факт, а не накладную.» [qty] is what is in the box, and it
 * is what goes on the shelf. [invoiceQty] is what the supplier says they sent,
 * and the gap between them is a CLAIM against the supplier rather than a reason
 * to refuse the delivery — a warehouse hand who cannot book a short shipment
 * types the invoice number instead, and from then on the shelf and the ledger
 * disagree with nothing to explain why.
 */
const receiptBody = z.object({
  variantId: z.string().trim().min(1),
  /**
   * Which purchase order this box belongs to, when it belongs to one.
   *
   * Optional, and it must stay optional: «приход без заказа» is a real and
   * common event — a courier turns up with something nobody raised an order
   * for — and a receipt form that demanded a PO would push that delivery back
   * onto the old path where the shelf and the ledger disagree with nothing to
   * explain why.
   *
   * When it IS present, the ORDERED quantity becomes the comparison basis for
   * the shortfall claim in place of the packing list: what we are owed is what
   * we ordered, and a supplier who bills for what they shipped is not thereby
   * relieved of the twenty units missing from it.
   */
  poId: z.string().trim().min(1).optional(),
  /// Units actually in the box, defective ones included. They arrived.
  qty: z.number().int().min(1).max(100000),
  /// What the packing list claims. Absent when nobody is checking against one.
  invoiceQty: z.number().int().min(0).max(100000).optional(),
  /// Of [qty], how many are unsellable. They are counted, and not stocked.
  defective: z.number().int().min(0).max(100000).optional(),
  /**
   * What the whole batch cost, in tiyn. «Себестоимость партии пересчитывается с
   * учётом брака»: paying for thirty and being able to sell twenty-eight makes
   * each sellable unit cost more, and a cost that ignores that reports a margin
   * the business is not earning.
   */
  batchCostMinor: z.number().int().min(0).optional(),
  /// Optional. A shipment of straps has no serials; a shipment of watches does.
  serials: z.string().max(20000).optional(),
  kind: z.enum(['band', 'tag']).optional(),
  note: z.string().trim().max(300).optional(),
});

/**
 * Кто нам возит — кадр 07g.
 *
 * [leadTimeDays] is what the supplier DECLARED. It is not derived from
 * history, and it must not be: nothing in this database has a placed→received
 * pair yet, so an average would be computed from nothing and printed beside a
 * number a buyer plans money against. The panel labels it «заявленный».
 */
const supplierBody = z.object({
  id: z.string().trim().min(1).optional(),
  name: z.string().trim().min(1).max(120),
  contact: z.string().trim().max(200).nullable().optional(),
  leadTimeDays: z.number().int().min(0).max(365).nullable().optional(),
  active: z.boolean().optional(),
});

/// Заказ поставщику — кадр 07b. Lines are colours, because that is what is
/// ordered: «часы чёрные 40», never «часы 40».
const purchaseOrderBody = z.object({
  supplierId: z.string().trim().min(1).nullable().optional(),
  /// The day it is expected. A date, not a timestamp — nobody promises 14:20.
  expectedAt: z.string().trim().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD').nullable().optional(),
  note: z.string().trim().max(300).nullable().optional(),
  /**
   * Place it at once, rather than leaving a draft.
   *
   * Defaults to true, and that default is the point: a draft counts as nothing
   * in transit, so an order saved and never placed would leave the warehouse
   * screen still saying «пора заказывать» about goods somebody has just
   * ordered. Drafts exist for the buyer who is still assembling a list.
   */
  place: z.boolean().optional(),
  items: z.array(z.object({
    variantId: z.string().trim().min(1),
    qtyOrdered: z.number().int().min(1).max(100000),
    /// Null until somebody names a price. Never computed — see the migration.
    unitCostMinor: z.number().int().min(0).nullable().optional(),
  })).min(1).max(200),
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
    /**
     * What is already on the water, per variant (migration 045).
     *
     * NOT added to `stock`, and NOT fed into runwayOf: cover is what can be
     * shipped today, and a forecast that counts a box in Almaty customs
     * promises stock nobody can send. It changes one thing only — whether the
     * screen says «пора заказывать» or «заказ уже размещён», which are two
     * different sentences about the same shelf.
     *
     * Absent on an unmigrated database rather than fatal, like the ledger read
     * above: a missing supply table should cost the in-transit column, not the
     * whole warehouse screen.
     */
    const inTransit = await repo.inTransitByVariant().catch(() => ({} as Record<string, number>));
    /**
     * Which photos exist — WITHOUT the bytes (see `listProductPhotos`).
     *
     * The warehouse screen drew a coloured dot per colour while the storefront
     * showed the real picture of the same thing, and per-colour upload was
     * built precisely so the two agree. The index travels with the shelf so the
     * panel can draw a photo where there is one and an honest placeholder where
     * there is not — rather than firing an <img> at every row and letting most
     * of them 404 into a broken-image icon.
     *
     * Absent on an unmigrated database rather than fatal, like the two reads
     * above: a missing photo table should cost the thumbnails, not the shelf.
     */
    const photos = await repo.listProductPhotos().catch(() => [] as Array<{ productId: string; color: string; uploadedAt: string }>);
    const photoAt = new Map<string, string>();
    for (const ph of photos) photoAt.set(`${ph.productId}|${ph.color}`, ph.uploadedAt);
    /**
     * The same URL the storefront and the app already use, so there is one
     * photo endpoint and not a second admin-only one to keep in step.
     * `uploadedAt` rides alongside instead of being baked into the URL: the
     * response is cached for a day, and the caller that needs a fresh copy
     * after a replacement is the one that should say so.
     */
    const photoOf = (productId: string, color: string) => {
      const at = photoAt.get(`${productId}|${color}`);
      if (!at) return {};
      const base = `/shop/products/${encodeURIComponent(productId)}/photo`;
      return {
        // Absent rather than null when there is none, matching /shop/products:
        // a client testing `if (photoUrl)` and one testing `'photoUrl' in v`
        // then agree.
        photoUrl: color ? `${base}?color=${encodeURIComponent(color)}` : base,
        photoUpdatedAt: at,
      };
    };

    const withParts = await Promise.all(products.map(async (p) => {
      const runway = runwayOf(p.stock, sold[p.id] ?? 0, SALES_WINDOW_DAYS);
      const variants = p.variants.map((v) => ({
        ...v, inTransit: inTransit[v.id] ?? 0, ...photoOf(p.id, v.color),
      }));
      // A bundle has no shelf of its own, so nothing is ordered against it —
      // its parts are. Summing its variants would be summing an empty list
      // anyway; saying so explicitly stops a future reader adding one.
      const productInTransit = variants.reduce((n, v) => n + v.inTransit, 0);
      const raw = needsReorder(runway, LEAD_TIME_DAYS);
      /**
       * How many units short of surviving the lead time this product is. The
       * same arithmetic `needsReorder` does, made explicit so «уже заказано»
       * can be a judgement about a QUANTITY rather than about whether any
       * order at all exists — one strap on the water must not silence a
       * warning about forty watches.
       */
      const gap = runway && !runway.noSales
        ? Math.max(0, Math.ceil(runway.perDay * LEAD_TIME_DAYS) - p.stock)
        : 0;
      const covered = raw && productInTransit > 0 && productInTransit >= gap;
      return {
        ...p,
        variants,
        // The product's own photo (`color === ''`), for the row that names the
        // product and for a bundle, which has colours nowhere to carry one.
        ...photoOf(p.id, ''),
        parts: p.kind === 'bundle' ? await repo.bundleParts(p.id) : [],
        soldInWindow: sold[p.id] ?? 0,
        // JSON has no Infinity — it serialises as null, which would be
        // indistinguishable from "not computed". `noSales` carries that case.
        daysOfCover: runway && Number.isFinite(runway.days) ? runway.days : null,
        perDay: runway ? Number(runway.perDay.toFixed(2)) : null,
        noSales: runway ? runway.noSales : true,
        /// Units ordered and not yet received. Never part of `stock`.
        inTransit: productInTransit,
        reorder: raw && !covered,
        /**
         * True when this product WOULD be flagged and an open order already
         * covers it. A distinct flag rather than a silent suppression: the
         * shelf is still short, and a buyer who cannot see that the answer is
         * "already ordered" learns to distrust the screen.
         */
        reorderCovered: covered,
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
      /// Would have been flagged, and is already on order. Listed rather than
      /// silently dropped — see `reorderCovered`.
      reorderCovered: withParts.filter((p) => p.reorderCovered).map((p) => p.id),
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
   * «Приёмка принимает факт, а не накладную.» What is in the box goes on the
   * shelf. What the supplier billed is recorded beside it, and a shortfall is a
   * CLAIM against them rather than a reason to refuse the delivery — a
   * warehouse hand who cannot book a short shipment types the invoice number
   * instead, and from then on the shelf and the ledger disagree with nothing
   * anywhere to explain why. That is the failure this route used to cause: it
   * refused any mismatch, which made the honest answer the impossible one.
   *
   * Serials are the exception, and not for the same reason. A serial IS a unit,
   * so twenty-eight of them against a quantity of thirty is not a discrepancy
   * with a supplier — it is two units nobody has identified yet, and booking it
   * would leave two watches on the shelf that the pairing check will not
   * recognise. That one is still refused.
   */
  app.post('/admin/inventory/receipt', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = receiptBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    const { variantId, qty, invoiceQty, batchCostMinor, kind, note, poId } = parsed.data;
    const defective = Math.min(parsed.data.defective ?? 0, qty);
    const serials = splitSerials(parsed.data.serials ?? '');

    /**
     * The order this box was raised against, when it was raised against one.
     *
     * Read BEFORE anything is written, and refused loudly: booking a receipt
     * against an order that does not contain this colour would leave the line
     * open for ever and the units showing as «в пути» while they sit on the
     * shelf. Receiving with no `poId` at all skips this entirely — «приход без
     * заказа» is a real event and still works exactly as before.
     */
    let ordered: number | null = null;
    let orderedTotal: number | null = null;
    let alreadyReceived = 0;
    if (poId) {
      const po = await repo.purchaseOrderById(poId);
      if (!po) return reply.code(404).send({ error: 'unknown_purchase_order' });
      if (po.status === 'cancelled') {
        return reply.code(409).send({
          error: 'purchase_order_cancelled',
          message: 'Заказ отменён. Примите поставку без заказа или снимите отмену.',
        });
      }
      const line = po.items.find((i) => i.variantId === variantId);
      if (!line) {
        return reply.code(409).send({
          error: 'variant_not_ordered',
          message: 'В этом заказе такого цвета нет. Проверьте заказ или примите поставку без заказа.',
        });
      }
      /**
       * The OUTSTANDING quantity, not the whole line.
       *
       * A delivery split across two boxes is normal, and the second box is
       * owed only what the first one did not bring. Comparing it against the
       * full ordered quantity again raises a fresh claim for units already on
       * the shelf: order twenty, receive twelve then eight, and the ledger
       * ends up carrying claims for twenty missing units against an order that
       * arrived complete.
       */
      orderedTotal = line.qtyOrdered;
      alreadyReceived = Math.max(0, line.qtyReceived);
      ordered = Math.max(0, orderedTotal - alreadyReceived);
    }

    if (serials.length && serials.length !== qty) {
      return reply.code(409).send({
        error: 'serial_count_mismatch',
        qty,
        serials: serials.length,
        message: `В коробке ${qty} шт., а серийных номеров ${serials.length}. ` +
          'Серийник — это единица товара, а не строка накладной: без него устройство ' +
          'не отличить от чужого. Допишите недостающие или укажите фактическое количество.',
      });
    }

    // What can be sold. Defective units arrived — they are a fact, and they are
    // counted — but putting them on the shelf sells one to somebody.
    const usable = qty - defective;
    if (usable <= 0) {
      return reply.code(409).send({
        error: 'nothing_usable',
        message: `Вся поставка (${qty} шт.) в браке — принимать на склад нечего. ` +
          'Оформите претензию поставщику.',
      });
    }

    /**
     * The claim against the supplier. Recorded, never a refusal.
     *
     * Against the ORDER when there is one, and against the packing list
     * otherwise. What we are owed is what we ordered: a supplier who bills
     * accurately for a short shipment has not thereby stopped owing the
     * twenty units missing from it, and a claim measured against their own
     * invoice can never see that.
     */
    const basisQty = ordered ?? invoiceQty ?? null;
    const basisKind: 'order' | 'invoice' | null =
      ordered != null ? 'order' : invoiceQty != null ? 'invoice' : null;
    const shortfall = basisQty != null ? basisQty - qty : 0;

    const parts = [note ?? 'приёмка'];
    if (basisQty != null && shortfall !== 0) {
      // Against the REMAINDER when part of the line has already landed, and the
      // ledger says so: «против заказа (20)» beside a second box would read as
      // a claim for the whole order to whoever finds it later.
      const against = basisKind === 'order'
        ? (alreadyReceived > 0
            ? `остатка заказа (${basisQty} из ${orderedTotal}, принято ${alreadyReceived})`
            : `заказа (${basisQty})`)
        : `накладной (${basisQty})`;
      parts.push(shortfall > 0
        ? `недостача ${shortfall} шт. против ${against}`
        : `излишек ${-shortfall} шт. против ${against}`);
    }
    // Both numbers when both were given: the invoice and the order can
    // disagree with each other as well as with the box, and that is the
    // conversation with the supplier rather than something to hide.
    if (basisKind === 'order' && invoiceQty != null && invoiceQty !== qty) {
      parts.push(`по накладной ${invoiceQty} шт.`);
    }
    if (defective) parts.push(`брак ${defective} шт., на склад не поставлен`);

    // Stock first. If the serial write fails afterwards the shelf is right and
    // the registry is short, which a second Приёмка fixes because
    // addDeviceSerials is idempotent per serial. The other order would book
    // serials for units that never went onto the shelf.
    const moved = await repo.moveStock({
      variantId, delta: usable, reason: 'receipt', staffId: s.staffId,
      note: parts.join(' · '),
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

    // «Себестоимость партии пересчитывается с учётом брака.» Paying for thirty
    // and being able to sell twenty-eight makes each sellable unit cost more.
    // Dividing by what arrived instead reports a margin the business is not
    // earning, and margin is what the owner's dashboard is built on.
    let unitCostMinor: number | null = null;
    if (batchCostMinor != null) {
      unitCostMinor = Math.round(batchCostMinor / usable);
      const product = (await repo.adminProducts().catch(() => []))
        .find((p) => p.variants.some((v) => v.id === variantId));
      if (product) {
        // Checked, not assumed: a cost that silently failed to save would leave
        // the dashboard quoting the old one with no sign anything went wrong.
        await repo.upsertProduct({ ...product, costMinor: unitCostMinor });
      }
    }

    /**
     * Close the order line, and let the order close itself when that was the
     * last one open.
     *
     * After the shelf, deliberately. If this write failed the units would be
     * on the shelf and still counted as in transit — a screen that overstates
     * what is coming — which a second receipt fixes. The other order would
     * close an order for a delivery that was never booked.
     *
     * A short delivery still closes the line: the shortfall above is already a
     * recorded claim, and holding the order open over two missing units would
     * show them as «в пути» for ever.
     */
    let poStatus: PurchaseOrder['status'] | null = null;
    let poClosed = false;
    if (poId) {
      const res = await repo.receivePurchaseOrderLine(poId, variantId, qty);
      poStatus = res.status;
      poClosed = res.ok;
    }

    await repo.writeAudit({ staffId: s.staffId, action: 'stock_receipt', target: variantId });
    return reply.send({
      ok: true,
      stock: moved.stock,
      /// Which order this was booked against, and what became of it.
      poId: poId ?? null,
      poStatus,
      /**
       * False when the order line could not be closed. The panel says so: a
       * receipt reported as complete while the units stay «в пути» is how the
       * screen starts lying about what is coming.
       */
      poLineClosed: poClosed,
      /**
       * What the order still had OUTSTANDING when this box was booked, which is
       * what the claim was measured against — not the whole line. On a first
       * receipt the two are the same number.
       */
      orderedQty: ordered,
      /// The whole line, and what had already arrived before this box.
      orderedTotalQty: orderedTotal,
      alreadyReceivedQty: poId ? alreadyReceived : null,
      /// 'order' | 'invoice' | null — what `shortfall` was measured against.
      shortfallBasis: basisKind,
      /// What went on the shelf, which is not what arrived when some was broken.
      received: qty,
      stocked: usable,
      defective,
      /**
       * Positive: the supplier billed for more than turned up. Negative: they
       * sent more. Zero or absent: nothing to claim.
       *
       * Returned rather than raised as an error, because the delivery is a fact
       * and the claim is a separate conversation with somebody else.
       */
      shortfall,
      unitCostMinor,
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

  // ---- Поставщики и поставки в пути (кадры 07a, 07b, 07g) -------------------
  //
  // The warehouse could say what is on the shelf and how long it lasts. It
  // could not say what is already coming, which is the question that decides
  // whether to order today — so the screen printed «пора заказывать» beside
  // goods ordered a fortnight ago, and a buyer either ordered them twice or
  // stopped believing the banner.
  //
  // Guarded on `stock` like the rest of the warehouse, and audited: a purchase
  // order commits the business's money.

  app.get('/admin/suppliers', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    return reply.send({
      suppliers: await repo.listSuppliers(),
      /// What the warehouse falls back to for a supplier who declared no term.
      /// Sent so the panel can label it as the standing figure rather than
      /// print it as though this supplier promised it.
      defaultLeadTimeDays: LEAD_TIME_DAYS,
    });
  });

  app.post('/admin/suppliers', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = supplierBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    const res = await repo.upsertSupplier(parsed.data);
    if (!res.ok) {
      // 409, not 500: `lower(name)` is UNIQUE, and «этим именем уже кто-то
      // зовётся» is the world refusing a well formed request. The old code let
      // the constraint violation escape, so the operator saw a server error
      // and never learned that the name was the problem.
      return reply.code(409).send({
        error: 'supplier_name_taken',
        message: `Поставщик «${parsed.data.name}» уже есть в списке. ` +
          'Откройте его карточку или выберите другое имя.',
      });
    }
    await repo.writeAudit({
      staffId: s.staffId,
      action: parsed.data.id ? 'supplier_update' : 'supplier_add',
      target: parsed.data.name,
    });
    return reply.send({ ok: true, id: res.id });
  });

  app.get('/admin/purchase-orders', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const limit = Math.min(200, Math.max(1, Number((req.query as { limit?: string }).limit) || 50));
    return reply.send({
      orders: await repo.listPurchaseOrders(limit),
      leadTimeDays: LEAD_TIME_DAYS,
    });
  });

  app.post('/admin/purchase-orders', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = purchaseOrderBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    const created = await repo.createPurchaseOrder({
      supplierId: parsed.data.supplierId ?? null,
      expectedAt: parsed.data.expectedAt ?? null,
      note: parsed.data.note ?? null,
      createdBy: s.staffId,
      items: parsed.data.items,
    });
    if (!created.ok) {
      // 409, not 400: «этого цвета не существует» is the world refusing a well
      // formed request, and the panel says which of the two it was.
      return reply.code(409).send({ error: created.error });
    }
    // Placed unless the buyer explicitly asked for a draft. A draft counts as
    // nothing in transit, so an order saved and never placed would leave the
    // shelf still shouting «пора заказывать» about goods just ordered.
    const place = parsed.data.place !== false;
    let status: PurchaseOrder['status'] = 'draft';
    if (place) {
      // Checked. A "placed" order the write silently left as a draft is an
      // order nobody sends and nothing counts.
      const ok = await repo.setPurchaseOrderStatus(created.id, 'placed');
      if (!ok) return reply.code(409).send({ error: 'not_placed', id: created.id });
      status = 'placed';
    }
    await repo.writeAudit({
      staffId: s.staffId, action: place ? 'po_place' : 'po_draft', target: created.id,
    });
    return reply.send({ ok: true, id: created.id, status });
  });

  app.post('/admin/purchase-orders/:id/place', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { id } = req.params as { id: string };
    const po = await repo.purchaseOrderById(id);
    if (!po) return reply.code(404).send({ error: 'unknown_purchase_order' });
    // Only a draft can be placed. Re-placing a received order would reopen
    // stock that has already landed and count it twice.
    if (po.status !== 'draft') {
      return reply.code(409).send({ error: 'not_a_draft', status: po.status });
    }
    const ok = await repo.setPurchaseOrderStatus(id, 'placed');
    if (!ok) return reply.code(409).send({ error: 'not_placed' });
    await repo.writeAudit({ staffId: s.staffId, action: 'po_place', target: id });
    return reply.send({ ok: true, status: 'placed' });
  });

  app.post('/admin/purchase-orders/:id/cancel', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { id } = req.params as { id: string };
    const po = await repo.purchaseOrderById(id);
    if (!po) return reply.code(404).send({ error: 'unknown_purchase_order' });
    // A received order is a delivery that happened. Cancelling it would claim
    // stock on the shelf was never bought.
    if (po.status === 'received') {
      return reply.code(409).send({
        error: 'already_received',
        message: 'Заказ уже принят на склад — отменить его нельзя. Оформите возврат поставщику.',
      });
    }
    const ok = await repo.setPurchaseOrderStatus(id, 'cancelled');
    if (!ok) return reply.code(409).send({ error: 'not_cancelled' });
    await repo.writeAudit({ staffId: s.staffId, action: 'po_cancel', target: id });
    return reply.send({ ok: true, status: 'cancelled' });
  });

  app.get('/admin/inventory/moves', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const q = req.query as { variantId?: string; limit?: string; since?: string };
    const limit = Math.min(500, Math.max(1, Number(q.limit) || 100));
    /**
     * «Движения за день» (frame 07) asks for one day, and the day starts where
     * the operator is — so the instant comes from the caller and is normalised
     * here rather than guessed from the server's timezone.
     *
     * An unparsable value is REFUSED, not ignored. Ignoring it would answer a
     * question about today with the whole ledger, and the panel would add those
     * rows up and print somebody's month as their shift.
     */
    let since: string | undefined;
    if (q.since != null && q.since !== '') {
      const t = new Date(q.since);
      if (Number.isNaN(t.getTime())) {
        return reply.code(400).send({ error: 'bad_since', detail: 'since must be an ISO instant' });
      }
      since = t.toISOString();
    }
    const moves = await repo.stockMoves(limit, q.variantId, since);
    return reply.send({
      moves,
      limit,
      since: since ?? null,
      /**
       * False when the window was full: the caller asked for a period, got a
       * truncated slice of it, and any total computed from it is short. The
       * panel hides its day totals in that case rather than printing a number
       * the response cannot support.
       */
      exact: moves.length < limit,
    });
  });
}
