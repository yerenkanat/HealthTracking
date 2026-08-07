/**
 * Managing the people who can sign in to the back office.
 *
 * Until this existed, adding a colleague meant an SSH session and a seeding
 * script — so in practice it meant one shared account, which is the thing the
 * sign-in work was for. The roster, the roles and the lockouts belong in the
 * panel next to everything else the owner administers.
 *
 * Everything here is admin-only except changing your own password, which any
 * signed-in staff member must be able to do without asking permission.
 *
 * Two guards carry most of the weight, and both exist because the failure is
 * unrecoverable from inside the product:
 *
 *   - You cannot disable yourself or demote yourself. It reads as an obvious
 *     mistake to make and an obvious one to catch, and the person who makes it
 *     is locked out of the only screen that could undo it.
 *   - The last enabled admin cannot be disabled or demoted, by anyone. One
 *     admin is the normal state of this business, so "there is always another
 *     one" is not a safe assumption to build on.
 *
 * Recovery, if it ever comes to it, is db/seed-staff.mjs on the server.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository, StaffRole } from '../db/repository';
import { can, type Capability, STAFF_ROLES } from '../auth/capabilities';
import {
  hashPassword,
  hashToken,
  normalizePhone,
  readSessionCookie,
  verifyPassword,
} from '../http/staffAuth';

/** Long enough to be worth hashing; the panel says the same thing. */
export const MIN_PASSWORD = 8;

/**
 * Every role that can be assigned, from the one place the matrix lives.
 *
 * This was a literal three-name list, so the panel could offer only the three
 * roles that existed before there were capabilities — a `seller` was a role you
 * could write a guard for and not a role you could give anybody.
 */
const ROLES = STAFF_ROLES;

const createBody = z.object({
  phone: z.string().min(4).max(32),
  displayName: z.string().trim().min(1).max(80),
  role: z.enum(ROLES),
  password: z.string().min(MIN_PASSWORD).max(200),
});

const patchBody = z.object({
  role: z.enum(ROLES).optional(),
  displayName: z.string().trim().min(1).max(80).optional(),
  password: z.string().min(MIN_PASSWORD).max(200).optional(),
  disabled: z.boolean().optional(),
});

const passwordBody = z.object({
  currentPassword: z.string().min(1).max(200),
  newPassword: z.string().min(MIN_PASSWORD).max(200),
});

export type AuthAdmin = (
  req: FastifyRequest,
) => Promise<{ staffId: string; role: StaffRole } | null>;

export function registerStaffAdminRoutes(
  app: FastifyInstance,
  repo: Repository,
  authAdmin: AuthAdmin,
): void {
  async function requireStaff(req: FastifyRequest, reply: FastifyReply) {
    const s = await authAdmin(req);
    if (!s) { reply.code(401).send({ error: 'unauthorized' }); return null; }
    return s;
  }
  /** Managing colleagues is the `staff` capability — owner and admin hold it. */
  async function requireCap(req: FastifyRequest, reply: FastifyReply, cap: Capability) {
    const s = await requireStaff(req, reply);
    if (!s) return null;
    if (!can(s.role, cap)) { reply.code(403).send({ error: 'forbidden', need: cap }); return null; }
    return s;
  }

  /**
   * Enabled accounts other than [exceptId] that could still manage staff — what
   * the last-admin guard counts.
   *
   * It counted `role === 'admin'` exactly. With `owner` also holding the
   * capability that reads as zero on a company whose only owner is an `owner`,
   * so the guard would refuse a legitimate demotion; and the day `admin` is
   * retired it would refuse every one of them. Count the capability.
   */
  async function otherEnabledAdmins(exceptId: string): Promise<number> {
    const all = await repo.listStaffAccounts();
    return all.filter((a) => can(a.role, 'staff') && !a.disabled && a.id !== exceptId).length;
  }

  // ---- The roster ----------------------------------------------------------
  app.get('/admin/staff', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    return reply.send({ staff: await repo.listStaffAccounts(), me: s.staffId });
  });

  // ---- Add a colleague -----------------------------------------------------
  app.post('/admin/staff', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const parsed = createBody.safeParse(req.body);
    if (!parsed.success) {
      // The password rule is the one a person actually trips over, so it is
      // named rather than folded into a generic "bad request".
      const tooShort = parsed.error.issues.some((i) => i.path[0] === 'password');
      return reply.code(400).send({
        error: tooShort ? 'weak_password' : 'bad_request',
        minPasswordLength: MIN_PASSWORD,
      });
    }

    const phone = normalizePhone(parsed.data.phone);
    if (phone.length < 10) return reply.code(400).send({ error: 'bad_phone' });

    const created = await repo.createStaffAccount({
      phone,
      passwordHash: await hashPassword(parsed.data.password),
      role: parsed.data.role,
      displayName: parsed.data.displayName,
    });
    // 409, not 200: the number belongs to somebody, and pretending the create
    // worked would leave the admin thinking a colleague can sign in when the
    // password they just chose is not the one on the account.
    if (!created) return reply.code(409).send({ error: 'phone_taken' });

    await repo.writeAudit({ staffId: s.staffId, action: 'staff_create', target: created.id });
    return reply.send({ ok: true, id: created.id });
  });

  // ---- Change a colleague's role, name, password, or access ----------------
  app.patch('/admin/staff/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = patchBody.safeParse(req.body);
    if (!parsed.success) {
      const tooShort = parsed.error.issues.some((i) => i.path[0] === 'password');
      return reply.code(400).send({
        error: tooShort ? 'weak_password' : 'bad_request',
        minPasswordLength: MIN_PASSWORD,
      });
    }
    const patch = parsed.data;

    const target = await repo.staffById(id);
    if (!target) return reply.code(404).send({ error: 'not_found' });

    const losesAdmin =
      patch.disabled === true || (patch.role !== undefined && !can(patch.role, 'staff'));
    if (losesAdmin && target.id === s.staffId) {
      return reply.code(409).send({ error: 'cannot_lock_yourself_out' });
    }
    if (losesAdmin && can(target.role, 'staff') && !target.disabled) {
      if ((await otherEnabledAdmins(target.id)) === 0) {
        return reply.code(409).send({ error: 'last_admin' });
      }
    }

    await repo.updateStaffAccount(id, {
      role: patch.role,
      displayName: patch.displayName,
      disabled: patch.disabled,
      passwordHash: patch.password ? await hashPassword(patch.password) : undefined,
    });

    // A new password or a lockout that leaves the old sessions alive has done
    // nothing: the browser that is already signed in stays signed in for the
    // rest of the twelve hours.
    let signedOut = 0;
    if (patch.password || patch.disabled === true) {
      signedOut = await repo.deleteStaffSessionsFor(id);
    }

    await repo.writeAudit({ staffId: s.staffId, action: 'staff_update', target: id });
    return reply.send({ ok: true, signedOut });
  });

  // ---- Change your own password -------------------------------------------
  app.post('/admin/staff/me/password', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const parsed = passwordBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'weak_password', minPasswordLength: MIN_PASSWORD });
    }

    const me = await repo.staffById(s.staffId);
    if (!me) return reply.code(401).send({ error: 'unauthorized' });

    // The current password, again. Without it, an unattended signed-in browser
    // is enough to take the account over permanently.
    if (!(await verifyPassword(parsed.data.currentPassword, me.passwordHash))) {
      return reply.code(403).send({ error: 'wrong_password' });
    }

    await repo.updateStaffAccount(me.id, {
      passwordHash: await hashPassword(parsed.data.newPassword),
    });

    // Every session dies, including this one — then the current browser is
    // handed a fresh cookie. That is what makes "someone else knows my
    // password" a thing a password change actually fixes.
    const killed = await repo.deleteStaffSessionsFor(me.id);
    const stillMine = readSessionCookie(req.headers.cookie);
    if (stillMine) {
      await repo.createStaffSession({
        tokenHash: hashToken(stillMine),
        staffId: me.id,
        expiresAt: new Date(Date.now() + 12 * 60 * 60 * 1000),
        userAgent: String(req.headers['user-agent'] ?? ''),
      });
    }

    await repo.writeAudit({ staffId: me.id, action: 'staff_password_change' });
    return reply.send({ ok: true, signedOutOtherSessions: Math.max(0, killed - 1) });
  });
}
