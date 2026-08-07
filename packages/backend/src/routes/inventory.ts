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
  async function requireAdmin(req: FastifyRequest, reply: FastifyReply) {
    const s = await authAdmin(req);
    if (!s) { reply.code(401).send({ error: 'unauthorized' }); return null; }
    if (s.role !== 'admin') { reply.code(403).send({ error: 'forbidden' }); return null; }
    return s;
  }

  // ---- The warehouse view ---------------------------------------------------
  // ---- Which devices are ours (migration 028) -----------------------------
  //
  // Serials are recorded when a shipment is received — the same moment stock
  // goes onto the ledger. That is the only new warehouse work, and it is what
  // decides whether the pairing check protects anything or refuses customers.
  app.get('/admin/device-registry', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const limit = Math.min(1000, Math.max(1, Number((req.query as { limit?: string }).limit) || 200));
    // Audited, like the entitlement list and for the same reason: every sold
    // row carries the phone number of the customer who activated it. This is a
    // read of personal data, not an aggregate.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_device_registry' });
    return reply.send({ devices: await repo.listDeviceRegistry(limit) });
  });

  app.post('/admin/device-registry', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const parsed = serialsBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    // Pasted from a packing list, one per line: nobody types forty MACs into
    // forty separate fields, and a UI that made them would simply not be used.
    const rows = parsed.data.serials
      .split(/[\s,;]+/)
      .map((x) => x.trim())
      .filter(Boolean)
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
    const s = await requireAdmin(req, reply);
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
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const products = await repo.adminProducts();
    // Bundle composition travels with the product, so the panel can show what a
    // combo is made of without a request per product.
    const withParts = await Promise.all(products.map(async (p) => ({
      ...p,
      parts: p.kind === 'bundle' ? await repo.bundleParts(p.id) : [],
    })));
    return reply.send({
      products: withParts,
      lowStock: withParts.filter((p) => p.lowStock).map((p) => p.id),
    });
  });

  app.put('/admin/inventory/products', async (req, reply) => {
    const s = await requireAdmin(req, reply);
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
    const s = await requireAdmin(req, reply);
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
    const s = await requireAdmin(req, reply);
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

  app.get('/admin/inventory/moves', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const q = req.query as { variantId?: string; limit?: string };
    const limit = Math.min(500, Math.max(1, Number(q.limit) || 100));
    return reply.send({ moves: await repo.stockMoves(limit, q.variantId) });
  });
}
