/**
 * What a purchase unlocks in the app.
 *
 * The landing sells «Комплект «Мама и ребёнок»» at 39 000 ₸ — two devices plus
 * the Ма!Ма! course, which the page values at 40 000 ₸. The course is what the
 * 9 200 ₸ above the hardware price buys, so owning the combo is what opens the
 * lessons.
 *
 * An order and an account are joined by the PHONE. The order captures it at
 * checkout and the app signs in with it, so the same eleven digits identify the
 * same person on both sides — nothing for the customer to do, and no identifier
 * she would have to know.
 *
 * Granting is also a staff action on purpose. Orders arrive by WhatsApp and are
 * paid on delivery; somebody will always need to say "she has it" without a row
 * in shop_orders to point at. That is recorded with its author rather than done
 * quietly in the database.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository, StaffRole } from '../db/repository';
import { normalizePhone } from '../http/staffAuth';

/** The only feature today. Named rather than free text so a typo cannot grant
 *  something nobody will ever check for. */
export const MAMA_COURSE = 'mama_course';
const FEATURES = [MAMA_COURSE] as const;

export type AuthAdmin = (
  req: FastifyRequest,
) => Promise<{ staffId: string; role: StaffRole } | null>;
export type AuthUser = (req: FastifyRequest) => Promise<{ userId: string } | null>;

const grantBody = z.object({
  phone: z.string().min(4).max(32),
  feature: z.enum(FEATURES),
  note: z.string().trim().max(300).optional(),
});

export function registerEntitlementRoutes(
  app: FastifyInstance,
  repo: Repository,
  authAdmin: AuthAdmin,
  authUser: AuthUser,
): void {
  async function requireAdmin(req: FastifyRequest, reply: FastifyReply) {
    const s = await authAdmin(req);
    if (!s) { reply.code(401).send({ error: 'unauthorized' }); return null; }
    if (s.role !== 'admin') { reply.code(403).send({ error: 'forbidden' }); return null; }
    return s;
  }

  // ---- What the app asks about itself --------------------------------------
  //
  // Returns the caller's own entitlements and nothing else. The app decides
  // what to show from this; the server decides what is true.
  app.get('/account/entitlements', async (req, reply) => {
    const u = await authUser(req);
    if (!u) return reply.code(401).send({ error: 'unauthorized' });

    // The account's phone is the key. A session with no phone on it — a legacy
    // dev token — owns nothing, which is the safe direction to fail.
    const profile = await repo.getProfile(u.userId).catch(() => null);
    const phone = normalizePhone(profile?.phone ?? '');
    if (!phone) return reply.send({ features: [] });

    const features: string[] = [];
    for (const f of FEATURES) {
      if (await repo.hasEntitlement(phone, f)) features.push(f);
    }
    return reply.send({ features });
  });

  // ---- Staff grant and revoke ----------------------------------------------
  app.get('/admin/entitlements', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const q = req.query as { feature?: string; limit?: string };
    const feature = (FEATURES as readonly string[]).includes(q.feature ?? '')
      ? (q.feature as string) : MAMA_COURSE;
    const limit = Math.min(500, Math.max(1, Number(q.limit) || 100));
    // Audited: this is a list of customers' phone numbers, which is exactly the
    // kind of read the log exists for. Not an aggregate.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_entitlements' });
    return reply.send({ entitlements: await repo.listEntitlements(feature, limit) });
  });

  app.post('/admin/entitlements', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const parsed = grantBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const phone = normalizePhone(parsed.data.phone);
    if (phone.length < 10) return reply.code(400).send({ error: 'bad_phone' });

    await repo.grantEntitlement({
      phone, feature: parsed.data.feature,
      grantedBy: s.staffId, note: parsed.data.note,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'entitlement_grant', target: phone });
    return reply.send({ ok: true, phone });
  });

  app.delete('/admin/entitlements/:feature/:phone', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const { feature, phone } = req.params as { feature: string; phone: string };
    if (!(FEATURES as readonly string[]).includes(feature)) {
      return reply.code(400).send({ error: 'unknown_feature' });
    }
    const normalized = normalizePhone(phone);
    await repo.revokeEntitlement(normalized, feature);
    await repo.writeAudit({ staffId: s.staffId, action: 'entitlement_revoke', target: normalized });
    return reply.send({ ok: true });
  });
}
