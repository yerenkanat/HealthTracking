/**
 * Admin / back-office API (`/admin/*`) for the staff web dashboard.
 * RBAC via an injected `authAdmin(req) → { staffId, role } | null`:
 *   - any authenticated staff: ops stats, live emergency feed, patient health view
 *   - admin only: user list, audit log
 * Every read of PHI/location is written to the audit log.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { Repository } from '../db/repository';

export type StaffRole = 'admin' | 'clinician' | 'support';
export type AuthAdmin = (req: FastifyRequest) => Promise<{ staffId: string; role: StaffRole } | null>;

export function registerAdminRoutes(app: FastifyInstance, repo: Repository, authAdmin: AuthAdmin): void {
  async function requireStaff(req: FastifyRequest, reply: FastifyReply) {
    const s = await authAdmin(req);
    if (!s) {
      reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    return s;
  }
  async function requireAdmin(req: FastifyRequest, reply: FastifyReply) {
    const s = await requireStaff(req, reply);
    if (!s) return null;
    if (s.role !== 'admin') {
      reply.code(403).send({ error: 'forbidden' });
      return null;
    }
    return s;
  }

  // ---- Ops dashboard KPIs ----
  app.get('/admin/stats', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    return reply.send(await repo.adminStats());
  });

  // ---- Live emergency feed ----
  app.get('/admin/emergencies', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 50, 200);
    await repo.writeAudit({ staffId: s.staffId, action: 'view_emergencies' });
    return reply.send({ emergencies: await repo.recentEmergencies(limit) });
  });

  // ---- User list (admin only) ----
  app.get('/admin/users', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const q = (req.query as { q?: string }).q ?? '';
    const limit = clampLimit((req.query as { limit?: string }).limit, 25, 100);
    const offset = Math.max(0, Number((req.query as { offset?: string }).offset ?? 0) || 0);
    await repo.writeAudit({ staffId: s.staffId, action: 'list_users' });
    return reply.send(await repo.adminListUsers(q, limit, offset));
  });

  // ---- Patient health (clinician/admin) — audited PHI access ----
  app.get('/admin/users/:id/health', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_health', target: userId });
    const health = await repo.adminUserHealth(userId);
    if (!health) return reply.code(404).send({ error: 'not found' });
    return reply.send(health);
  });

  // ---- Audit log (admin only) ----
  app.get('/admin/audit', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    return reply.send({ audit: await repo.listAudit(limit) });
  });
}

function clampLimit(raw: string | undefined, def: number, max: number): number {
  const n = Number(raw ?? def);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(max, Math.floor(n));
}
