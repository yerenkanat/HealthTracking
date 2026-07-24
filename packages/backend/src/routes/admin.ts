/**
 * Admin / back-office API (`/admin/*`) for the staff web dashboard.
 * RBAC via an injected `authAdmin(req) → { staffId, role } | null`:
 *   - any authenticated staff: ops stats, live emergency feed, patient health view
 *   - admin only: user list, audit log
 * Every read of PHI/location is written to the audit log.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { ContentItemRow, Repository } from '../db/repository';

/// Pregnancy weeks 1..40 and child months 0..60 (birth to five years). Content
/// under any other key is unreachable by the app, so it is refused on write
/// rather than accepted and silently never shown.
function isStageKey(key: string): boolean {
  const n = Number(key.slice(1));
  if (!Number.isInteger(n)) return false;
  if (key.startsWith('w')) return n >= 1 && n <= 40;
  if (key.startsWith('m')) return n >= 0 && n <= 60;
  return false;
}

function allStageKeys(): string[] {
  return [
    ...Array.from({ length: 40 }, (_, i) => `w${i + 1}`),
    ...Array.from({ length: 61 }, (_, i) => `m${i}`),
  ];
}

/// What is published and what is still empty — the first question anyone
/// authoring 101 stages asks.
function coverageOf(catalog: Record<string, ContentItemRow[]>) {
  const filled: string[] = [];
  const empty: string[] = [];
  let items = 0;
  let linked = 0;

  // A stage served only by an item shared in from elsewhere IS covered.
  // Counting just the stage's own list would have reported it as a hole and
  // sent someone off to author content that already exists there — the very
  // duplication sharing was added to stop.
  const sharedInto = new Map<string, Set<string>>();
  for (const [home, list] of Object.entries(catalog)) {
    for (const item of list) {
      for (const key of item.alsoStages ?? []) {
        if (key === home) continue;
        let set = sharedInto.get(key);
        if (!set) sharedInto.set(key, (set = new Set()));
        set.add(item.id);
      }
    }
  }

  for (const key of allStageKeys()) {
    const own = catalog[key] ?? [];
    const shared = sharedInto.get(key)?.size ?? 0;
    if (own.length === 0 && shared === 0) {
      empty.push(key);
      continue;
    }
    filled.push(key);
    // Items are counted where they are AUTHORED, so the total stays a count of
    // things that exist rather than of appearances — a lesson shared across
    // fourteen weeks must not read as fourteen lessons in the catalogue size.
    items += own.length;
    linked += own.filter((i) => (i.url ?? '').trim().length > 0).length;
  }
  return {
    total: allStageKeys().length,
    filled,
    empty,
    items,
    linked,
    /// Stages that have nothing of their own but are covered by a shared item.
    /// Surfaced separately so the CMS can show them as covered-by-reuse rather
    /// than silently identical to a stage with its own content.
    sharedOnly: [...sharedInto.keys()].filter((k) => (catalog[k] ?? []).length === 0).sort(),
  };
}

const localizedText = z.record(z.string(), z.string());
const contentItem = z.object({
  id: z.string().min(1).max(80),
  kind: z.enum(['lesson', 'product']),
  title: localizedText,
  summary: localizedText,
  url: z.string().max(500).optional(),
  // Minor units (tiyn). Integer on purpose — money in floating point drifts.
  priceMinor: z.number().int().positive().optional(),
  currency: z.string().max(8).optional(),
  imageUrl: z.string().max(500).optional(),
  durationMin: z.number().int().positive().max(600).optional(),
  // Targeting. Absent means "everyone", which is what almost every item should
  // be — these narrow an item to where it can actually be delivered or to
  // material that is genuinely age-specific.
  // Where the lesson's video lives. 'hls'/'mp4' play in the app's own player;
  // 'youtube' opens externally, because YouTube's terms require their player
  // with their branding and forbid extracting the stream. Keeping the provider
  // explicit means moving to a white-label host later is a re-import, not a
  // code change.
  video: z
    .object({
      provider: z.enum(['hls', 'mp4', 'youtube']),
      url: z.string().min(1).max(500),
      posterUrl: z.string().max(500).optional(),
    })
    .optional(),
  cities: z.array(z.string().min(1).max(60)).max(30).optional(),
  minAgeYears: z.number().int().min(10).max(80).optional(),
  maxAgeYears: z.number().int().min(10).max(80).optional(),
  // Other stages this same item also serves. Most guidance is not specific to
  // one week — a second-trimester lesson is right for fourteen of them — and
  // filing it one stage at a time meant fourteen copies to keep in step. The
  // item is stored once, under the stage it is filed in, and listed under each
  // of these. Capped at the whole timeline, so a bad import cannot make one
  // item claim an unbounded number of places.
  alsoStages: z.array(z.string().regex(/^[wm]\d{1,2}$/)).max(101).optional(),
}).refine((i) => i.minAgeYears == null || i.maxAgeYears == null || i.minAgeYears <= i.maxAgeYears, {
  // An inverted range matches nobody, so the item would vanish with no error
  // anywhere. Rejecting it at the edge is the only place a person sees why.
  message: 'minAgeYears must not exceed maxAgeYears',
  path: ['minAgeYears'],
});
const stageContentBody = z.object({ items: z.array(contentItem).max(50) });

/// A whole catalogue in one request. 101 stages x 50 items is the ceiling the
/// per-stage route already implies; the record cap keeps a malformed file from
/// becoming an unbounded loop.
const bulkContentBody = z.object({
  stages: z.record(z.string(), z.array(contentItem).max(50)),
  /// 'merge' (the default) leaves stages absent from the file alone.
  /// 'replace' clears them — destructive, so it is never the default.
  mode: z.enum(['merge', 'replace']).default('merge'),
});

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

  // Acknowledge an emergency — admin-only (an accountable write), audited.
  // Idempotent: a second ack reports 409 rather than pretending it was first.
  app.post('/admin/emergencies/:id/ack', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const id = (req.params as { id: string }).id;
    const first = await repo.acknowledgeEmergency(id, s.staffId, new Date().toISOString());
    await repo.writeAudit({ staffId: s.staffId, action: 'ack_emergency', target: id });
    return first ? reply.send({ ok: true }) : reply.code(409).send({ error: 'already_acknowledged' });
  });

  // ---- Children demographics (admin only) ----
  app.get('/admin/children/stats', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_children_stats' });
    return reply.send(await repo.childrenStats(new Date().toISOString()));
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

  // ---- Patient wellness (sleep / cycle / safety alerts) — audited ----
  app.get('/admin/users/:id/wellness', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_wellness', target: userId });
    const [sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses] = await Promise.all([
      repo.listSleep(userId, 14),
      repo.listDayLogs(userId, '1970-01-01', '2999-12-31'),
      repo.listAlerts(userId, 50),
      repo.listWeight(userId, 30),
      repo.listMedications(userId),
      repo.listMedicalIds(userId),
      repo.listKickSessions(userId, 14),
      repo.listContractionSessions(userId, 14),
      repo.listNewbornEvents(userId, 20),
      repo.latestBpCalibration(userId),
      repo.listGrowth(userId),
      repo.listDoses(userId),
    ]);
    return reply.send({ sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses });
  });

  // ---- One family, assembled (clinician/admin) — audited PHI access ----
  app.get('/admin/users/:id/detail', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_user_detail', target: userId });
    const detail = await repo.adminUserDetail(userId);
    if (!detail) return reply.code(404).send({ error: 'not found' });
    // Her upcoming visits, so staff can see the antenatal plan she is actually
    // keeping. Read-only; failure here must not blank the whole card.
    const appointments = await repo.listAppointments(userId).catch(() => []);
    return reply.send({ ...detail, appointments });
  });

  // ---- Device fleet ----
  app.get('/admin/devices', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    // The fleet view is not a list of hardware: every row carries the
    // guardian's display name and their child's name. Opening one user's
    // health record was audited while browsing every family's names in one
    // request was not — the same personal data, reached a different way.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_devices' });
    return reply.send({ devices: await repo.adminDevices(limit) });
  });

  // ---- Safety feed across all families ----
  app.get('/admin/safety', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    await repo.writeAudit({ staffId: s.staffId, action: 'view_safety_feed' });
    return reply.send({ events: await repo.adminSafetyEvents(limit) });
  });

  // ---- Analytics ----
  app.get('/admin/analytics', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    return reply.send(await repo.adminAnalytics());
  });

  // Product metrics for the overview — DAU/WAU/MAU, growth, retention,
  // engagement mix. Aggregates only: no row here identifies a user, so this
  // needs staff but not admin, like the other read-only views.
  app.get('/admin/bi', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    return reply.send(await repo.adminBiMetrics());
  });

  // ---- Timeline content (the CMS) ----
  // Reading the catalogue is open to any staff; CHANGING what every user sees
  // — including what is offered for sale — is an admin action and is audited.
  app.get('/admin/content', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const catalog = await repo.contentCatalog();
    return reply.send({ stages: catalog, coverage: coverageOf(catalog) });
  });

  app.put('/admin/content/:stage', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;
    const stage = (req.params as { stage: string }).stage;
    if (!isStageKey(stage)) {
      return reply.code(400).send({ error: `unknown stage "${stage}" (expected w1..w40 or m0..m60)` });
    }
    const parsed = stageContentBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    // Ids must be unique WITHIN the stage; a repeat here would make two cards
    // indistinguishable to the app and merge them in analytics.
    const ids = new Set<string>();
    for (const item of parsed.data.items) {
      if (ids.has(item.id)) {
        return reply.code(400).send({ error: `duplicate id "${item.id}" in ${stage}` });
      }
      ids.add(item.id);
    }

    await repo.putStageContent(stage, parsed.data.items as ContentItemRow[]);
    await repo.writeAudit({ staffId: s.staffId, action: 'edit_content', target: stage });
    return reply.send({ ok: true, stage, items: parsed.data.items.length });
  });

  // ---- Bulk import (admin only) ----
  //
  // Authoring 101 stages one at a time through the panel is the real bottleneck
  // in getting this catalogue filled, and a spreadsheet exported to JSON is how
  // the work actually gets done.
  //
  // ALL-OR-NOTHING. Everything is validated before anything is written: a
  // partial apply across a hundred stages leaves the catalogue in a state
  // nobody can reason about, and the person importing cannot tell how far it
  // got. One bad stage rejects the whole file, naming the stage.
  app.put('/admin/content', async (req, reply) => {
    const s = await requireAdmin(req, reply);
    if (!s) return;

    const parsed = bulkContentBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const { stages, mode } = parsed.data;
    const keys = Object.keys(stages);

    // Validate every key and every id BEFORE the first write.
    for (const key of keys) {
      if (!isStageKey(key)) {
        return reply.code(400).send({ error: `"${key}" is not a stage (w1-w40, m0-m60)` });
      }
      const ids = new Set<string>();
      for (const item of stages[key]) {
        if (ids.has(item.id)) {
          return reply.code(400).send({ error: `duplicate id "${item.id}" in ${key}` });
        }
        ids.add(item.id);
      }
    }

    // 'replace' clears every stage absent from the file. It is destructive in a
    // way 'merge' is not — a file covering ten stages would wipe the other
    // ninety-one — so it only ever happens when asked for by name.
    const existing = mode === 'replace' ? await repo.contentCatalog() : {};
    const toClear = mode === 'replace'
      ? Object.keys(existing).filter((k) => !(k in stages))
      : [];

    for (const key of keys) {
      await repo.putStageContent(key, stages[key] as ContentItemRow[]);
    }
    for (const key of toClear) {
      await repo.putStageContent(key, []);
    }

    await repo.writeAudit({
      staffId: s.staffId,
      action: 'bulk_import_content',
      target: `${mode}:${keys.length} stages`,
    });
    return reply.send({
      ok: true,
      mode,
      stagesWritten: keys.length,
      stagesCleared: toClear.length,
      items: keys.reduce((n, k) => n + stages[k].length, 0),
    });
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
