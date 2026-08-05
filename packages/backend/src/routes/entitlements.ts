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

const lessonBody = z.object({
  id: z.string().uuid().optional(),
  titleRu: z.string().trim().min(1).max(200),
  titleKk: z.string().trim().max(200).nullable().optional(),
  // Only a YouTube link. The owner has YouTube; accepting anything else would
  // let a broken paste through and fail in the app, where nobody can fix it.
  youtubeUrl: z.string().trim().url().max(500)
    .refine((u) => /(?:youtube\.com|youtu\.be)/i.test(u), 'нужна ссылка на YouTube'),
  summaryRu: z.string().trim().max(1000).nullable().optional(),
  summaryKk: z.string().trim().max(1000).nullable().optional(),
  sort: z.number().int().min(0).max(100000).optional(),
  published: z.boolean().optional(),
});

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

  // ---- The course itself ---------------------------------------------------
  //
  // Gated on the entitlement, not merely hidden in the app. A paywall the client
  // enforces is a paywall anyone can read the JSON around.
  app.get('/course/lessons', async (req, reply) => {
    const u = await authUser(req);
    if (!u) return reply.code(401).send({ error: 'unauthorized' });

    const profile = await repo.getProfile(u.userId).catch(() => null);
    const phone = normalizePhone(profile?.phone ?? '');
    const entitled = phone ? await repo.hasEntitlement(phone, MAMA_COURSE) : false;

    // 200 with entitled:false rather than 403. The app needs to SAY what this
    // is and how to get it — a locked door with a sign on it sells the combo;
    // a locked door with no sign looks broken.
    if (!entitled) return reply.send({ entitled: false, lessons: [] });

    return reply.send({
      entitled: true,
      lessons: await repo.courseLessons('mama', true),
    });
  });

  app.get('/admin/course/lessons', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    // Everything, including drafts: this is where they are written.
    return reply.send({ lessons: await repo.courseLessons('mama', false) });
  });

  app.put('/admin/course/lessons', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const parsed = lessonBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'bad_request', detail: parsed.error.issues[0]?.message });
    }
    const { id } = await repo.upsertCourseLesson({ course: 'mama', ...parsed.data });
    await repo.writeAudit({ staffId: s.staffId, action: 'course_lesson_save', target: id });
    return reply.send({ ok: true, id });
  });

  app.delete('/admin/course/lessons/:id', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const { id } = req.params as { id: string };
    await repo.deleteCourseLesson(id);
    await repo.writeAudit({ staffId: s.staffId, action: 'course_lesson_delete', target: id });
    return reply.send({ ok: true });
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
