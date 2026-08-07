/**
 * Admin / back-office API (`/admin/*`) for the staff web dashboard.
 * RBAC via an injected `authAdmin(req) → { staffId, role } | null`:
 *   - any authenticated staff: ops stats, live emergency feed, patient health view
 *   - admin only: user list, audit log
 * Every read of PHI/location is written to the audit log.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { sendTelegramTest } from '../notifications/leadAlert';
import { createAuditThrottle } from '../http/auditThrottle';
import { antenatalProtocol } from '../antenatal/protocol';
import { vaccinationSchedule } from '../vaccination/schedule';
import { pregnancyCalendar } from '../pregnancy/weeks';
import { childDevCalendar } from '../child/development';
import type { ContentItemRow, Repository } from '../db/repository';
import { bilingualMessage, bilingualProblems, type BilingualProblem } from '../content/bilingual';
import { buildQueues, overdue, SLA_HOURS } from '../admin/queues';
import {
  carryReview, reviewIsCurrent, reviewMessage, textFingerprint, unreviewed,
  type ReviewableItem,
} from '../content/medicalReview';

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
  /**
   * This card gives medical guidance, so «только после проверки врачом».
   *
   * Marked by whoever writes it. Getting it wrong in the safe direction — a
   * nursery-decoration card marked medical — costs one clinician a minute;
   * wrong the other way publishes unreviewed advice, so nothing here tries to
   * infer it from the text.
   */
  medical: z.boolean().optional(),
  /**
   * Not published. A draft is how an unfinished medical card gets written at
   * all: without one, the review rule would push the work into a document
   * nobody can review.
   */
  draft: z.boolean().optional(),
  /**
   * Who signed it off. Accepted in the body and then IGNORED — the stored value
   * comes from what is already in the database, and the only way to set one is
   * POST /admin/content/:stage/:id/review, which needs `health`. A client that
   * could send its own review would be self-approval by JSON.
   */
  review: z.object({
    by: z.string().max(80),
    at: z.string().max(40),
    fingerprint: z.string().max(20000),
  }).optional(),
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

import { can, type Capability, type StaffRole } from '../auth/capabilities';
export type AuthAdmin = (req: FastifyRequest) => Promise<{ staffId: string; role: StaffRole } | null>;

export function registerAdminRoutes(app: FastifyInstance, repo: Repository, authAdmin: AuthAdmin): void {
  // Shared by the routes the panel polls. One per server, so it survives across
  // requests — which is the whole point.
  const auditThrottle = createAuditThrottle();

  async function requireStaff(req: FastifyRequest, reply: FastifyReply) {
    const s = await authAdmin(req);
    if (!s) {
      reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    return s;
  }
  /**
   * Guard on what the job needs, not on which role somebody happens to hold.
   *
   * What stood here was `requireAdmin` — "are you the owner?" — the only
   * question this panel could ask. It is the right question for staff
   * management and the wrong one for everything else: it makes every new role
   * either an owner or useless, and it is why every signed-in member of staff,
   * a warehouse hand included, could open a customer's health record.
   *
   * See auth/capabilities.ts for the matrix. An unknown role gets nothing.
   */
  async function requireCap(req: FastifyRequest, reply: FastifyReply, cap: Capability) {
    const s = await requireStaff(req, reply);
    if (!s) return null;
    if (!can(s.role, cap)) {
      reply.code(403).send({ error: 'forbidden', need: cap });
      return null;
    }
    return s;
  }

  /**
   * Why this person is opening this person's record.
   *
   * «Показатели здоровья и геолокация — … каждый просмотр в журнале с указанием
   * причины.» The log answered who looked at whom and when, which is everything
   * you need AFTER something has gone wrong and nothing before: a row reading
   * "s-4 viewed health of u-91" is identical whether a clinician was returning
   * a call or somebody was reading a neighbour's blood pressure.
   *
   * Refused rather than defaulted. A reason of "не указана" written
   * automatically is worse than none — it makes an unreviewable log look
   * reviewed. Eight characters, so «ok» and «.» do not pass as answers while
   * «звонок» and «жалоба» do.
   *
   * Applies to the three per-person reads. The feeds (/admin/safety,
   * /admin/devices) stay audited without one: they are lists the panel polls,
   * not a decision to open one family's record, and prompting on a poll would
   * train everyone to click through the prompt.
   */
  const MIN_REASON = 8;

  function readReason(req: FastifyRequest, reply: FastifyReply): string | null {
    const raw = String((req.query as { reason?: string }).reason ?? '').trim();
    if (raw.length < MIN_REASON) {
      reply.code(400).send({
        error: 'reason_required',
        minLength: MIN_REASON,
        message: 'Укажите причину просмотра — она попадёт в журнал действий.',
      });
      return null;
    }
    return raw.slice(0, 300);
  }

  // ---- Reference data the panel draws ------------------------------------
  //
  // The same constants the app's content API serves, under /admin so the panel
  // can reach them.
  //
  // Four tabs — Антенатальный уход, Календарь беременности, Календарь
  // развития, Вакцинация — fetched /antenatal/protocol and friends directly.
  // Those are app-API paths, and the app API is closed at the edge until it
  // has real authentication, so all four answered 404 in production and each
  // tab showed "доступно, когда панель обслуживается сервером". Four of
  // sixteen tabs were an apology. Every one of them has a render test, and all
  // four passed, because the tests stub fetch.
  //
  // Staff-only rather than public: this is the product's content catalogue,
  // and opening it is a decision for when the app API opens, not a side effect
  // of fixing the panel.
  const REFERENCE = {
    antenatal: antenatalProtocol,
    vaccination: vaccinationSchedule,
    pregnancy: pregnancyCalendar,
    childdev: childDevCalendar,
  } as const;

  app.get('/admin/reference/:kind', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const { kind } = req.params as { kind: string };
    const data = REFERENCE[kind as keyof typeof REFERENCE];
    if (!data) return reply.code(404).send({ error: 'unknown_reference' });
    return reply.send(data);
  });

  // ---- Ops dashboard KPIs ----
  app.get('/admin/stats', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const stats = await repo.adminStats();

    // Whether anyone would be TOLD about an outage.
    //
    // deploy/uptime-check.sh watches the site every few minutes and sends
    // through the same Telegram credentials the lead notifier uses. With no
    // token it still records state and exits non-zero — so the monitoring is
    // working perfectly and reporting to a journal nobody reads. Silence then
    // looks exactly like health, which is the worst thing a monitor can do.
    //
    // A boolean, never the credentials: this route is polled every 20 seconds
    // by every open panel.
    let alertsConfigured = false;
    try {
      const settings = await repo.getShopSettings();
      alertsConfigured = Boolean(settings.telegramBotToken && settings.telegramChatId);
    } catch {
      /* settings table absent on an unmigrated database — reported as not configured */
    }

    return reply.send({ ...stats, alertsConfigured });
  });

  // ---- Live emergency feed ----
  app.get('/admin/emergencies', async (req, reply) => {
    const s = await requireCap(req, reply, 'emergencies');
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 50, 200);
    // Throttled, not dropped: this is a live feed the panel re-fetches every
    // 20 seconds, so an unthrottled write turned one open tab into ~4 300
    // audit rows a day. See http/auditThrottle.ts.
    if (auditThrottle.shouldWrite(s.staffId, 'view_emergencies')) {
      await repo.writeAudit({ staffId: s.staffId, action: 'view_emergencies' });
    }
    return reply.send({ emergencies: await repo.recentEmergencies(limit) });
  });

  // Acknowledge an emergency — admin-only (an accountable write), audited.
  // Idempotent: a second ack reports 409 rather than pretending it was first.
  app.post('/admin/emergencies/:id/ack', async (req, reply) => {
    const s = await requireCap(req, reply, 'emergencies');
    if (!s) return;
    const id = (req.params as { id: string }).id;
    const first = await repo.acknowledgeEmergency(id, s.staffId, new Date().toISOString());
    await repo.writeAudit({ staffId: s.staffId, action: 'ack_emergency', target: id });
    return first ? reply.send({ ok: true }) : reply.code(409).send({ error: 'already_acknowledged' });
  });

  // ---- Children demographics (admin only) ----
  app.get('/admin/children/stats', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_children_stats' });
    return reply.send(await repo.childrenStats(new Date().toISOString()));
  });

  // ---- User list (admin only) ----
  app.get('/admin/users', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const q = (req.query as { q?: string }).q ?? '';
    const limit = clampLimit((req.query as { limit?: string }).limit, 25, 100);
    const offset = Math.max(0, Number((req.query as { offset?: string }).offset ?? 0) || 0);
    await repo.writeAudit({ staffId: s.staffId, action: 'list_users' });
    return reply.send(await repo.adminListUsers(q, limit, offset));
  });

  // ---- Patient health (clinician/admin) — audited PHI access ----
  app.get('/admin/users/:id/health', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const reason = readReason(req, reply);
    if (reason == null) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_health', target: userId, reason });
    const health = await repo.adminUserHealth(userId);
    if (!health) return reply.code(404).send({ error: 'not found' });
    return reply.send(health);
  });

  // ---- Patient wellness (sleep / cycle / safety alerts) — audited ----
  app.get('/admin/users/:id/wellness', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const reason = readReason(req, reply);
    if (reason == null) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_wellness', target: userId, reason });
    const [sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses, vaccines] = await Promise.all([
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
      repo.listVaccines(userId),
    ]);
    return reply.send({ sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses, vaccines });
  });

  // ---- One family, assembled (clinician/admin) — audited PHI access ----
  app.get('/admin/users/:id/detail', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const reason = readReason(req, reply);
    if (reason == null) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_user_detail', target: userId, reason });
    const detail = await repo.adminUserDetail(userId);
    if (!detail) return reply.code(404).send({ error: 'not found' });
    // Her upcoming visits, so staff can see the antenatal plan she is actually
    // keeping. Read-only; failure here must not blank the whole card.
    const appointments = await repo.listAppointments(userId).catch(() => []);
    return reply.send({ ...detail, appointments });
  });

  // ---- Device fleet ----
  app.get('/admin/devices', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
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
    const s = await requireCap(req, reply, 'health');
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

  /**
   * The Dashboard: what this business is, as of one instant.
   *
   * Admin rather than staff, unlike /admin/bi. Nothing here identifies a
   * person, but revenue, margin and stock value together are the commercial
   * position of the company, which is not the same category of thing as a
   * retention curve.
   */
  app.get('/admin/dashboard', async (req, reply) => {
    const s = await requireCap(req, reply, 'finance');
    if (!s) return;
    return reply.send(await repo.dashboardSnapshot(new Date().toISOString()));
  });

  /**
   * The operator's dashboard: what is waiting, and how long it has waited.
   *
   * «Дашбордов два … Оператору — очереди задач. Не смешивать.» /admin/dashboard
   * is the other one, and it is the owner's — revenue, margin, stock value. An
   * operator was being shown it for want of anything else, and once `finance`
   * became a capability she was being shown it with the numbers blanked.
   *
   * Guarded per SECTION rather than as a whole. A seller has `orders` and not
   * `emergencies`, and the honest answer to "what is waiting for me" is her two
   * queues rather than a 403 — so a missing capability drops that queue from
   * the response instead of refusing the screen. `available` says which ones
   * were computed, so an empty queue and an unavailable one cannot look alike.
   */
  app.get('/admin/queues', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;

    const mayOrders = can(s.role, 'orders');
    const mayEmergencies = can(s.role, 'emergencies');
    if (!mayOrders && !mayEmergencies) {
      // Nothing queues for a warehouse hand or a content editor: their work
      // arrives as a shipment or a brief, not as a list of people waiting.
      return reply.send({ available: [], queues: null });
    }

    const [leads, orders, emergencies] = await Promise.all([
      mayOrders ? repo.adminShopLeads(200).catch(() => []) : Promise.resolve([]),
      mayOrders ? repo.adminShopOrders(200).catch(() => []) : Promise.resolve([]),
      mayEmergencies ? repo.recentEmergencies(200).catch(() => []) : Promise.resolve([]),
    ]);

    // One instant for the whole board. Measuring each queue against its own
    // Date.now() lets two of them disagree about what "now" is, which shows up
    // as an off-by-one hour nobody can reproduce.
    const q = buildQueues({ leads, orders, emergencies }, Date.now());

    // Audited: every row on this board carries a customer's name, and the
    // emergency queue carries the names of women who pressed an SOS. Reaching
    // that through a summary is the same read as reaching it through the feed.
    //
    // Throttled, because the dashboard polls this — the same reason
    // /admin/emergencies is throttled. Unthrottled it would turn one open tab
    // into thousands of audit rows a day and bury the reads that matter.
    if (auditThrottle.shouldWrite(s.staffId, 'view_queues')) {
      await repo.writeAudit({ staffId: s.staffId, action: 'view_queues' });
    }

    const available: string[] = [];
    if (mayOrders) available.push('leads', 'orders');
    if (mayEmergencies) available.push('emergencies');

    return reply.send({
      available,
      queues: {
        ...(mayOrders ? { leads: q.leads, orders: q.orders } : {}),
        ...(mayEmergencies ? { emergencies: q.emergencies } : {}),
      },
      // Only over the queues this person can actually see, so a seller is never
      // told something is late that she is not allowed to look at.
      overdue: overdue(q).filter((k) => available.includes(k)),
      slaHours: SLA_HOURS,
    });
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
    const s = await requireCap(req, reply, 'content');
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

    // Both languages, or it does not go live. The app falls back to Russian
    // and says nothing about it, so a half-translated card reads to a Kazakh
    // mother as the app ignoring the language she chose. See content/bilingual.
    const problems = parsed.data.items.flatMap(bilingualProblems);
    if (problems.length) {
      return reply.code(400).send({
        error: 'translation_required',
        stage,
        problems,
        message: bilingualMessage(problems),
      });
    }

    // Medical guidance is checked by a clinician before anybody reads it, and
    // editing approved text takes the approval away — approve-then-rewrite is
    // the obvious way round the rule and the one that happens by accident.
    // See content/medicalReview.ts.
    const catalog: Record<string, ContentItemRow[]> =
      await repo.contentCatalog().catch(() => ({}));
    const previousById = new Map<string, ReviewableItem>(
      (catalog[stage] ?? []).map((i) => [i.id, i as ReviewableItem]),
    );
    const needReview = unreviewed(parsed.data.items, previousById);
    if (needReview.length) {
      return reply.code(409).send({
        error: 'review_required',
        stage,
        problems: needReview,
        message: reviewMessage(needReview) +
          '. Отправьте на проверку врачу или сохраните как черновик.',
      });
    }

    // The review that gets stored is the one already in the database, never the
    // one in the request body.
    const toStore = parsed.data.items.map((i) => carryReview(i, previousById.get(i.id)));

    await repo.putStageContent(stage, toStore as ContentItemRow[]);
    await repo.writeAudit({ staffId: s.staffId, action: 'edit_content', target: stage });
    return reply.send({ ok: true, stage, items: toStore.length });
  });

  /**
   * A clinician signs off one medical card.
   *
   * Guarded on `health`, not `content`. That is the whole mechanism: authoring
   * needs `content`, approving needs `health`, and no role but an owner holds
   * both — so the rule is two people rather than a checkbox the author ticks.
   *
   * The signature records WHAT was read, so a later edit to the same card
   * invalidates it automatically. Nobody has to remember to un-approve.
   */
  app.post('/admin/content/:stage/:id/review', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const { stage, id } = req.params as { stage: string; id: string };
    if (!isStageKey(stage)) return reply.code(400).send({ error: 'unknown_stage' });

    const catalog: Record<string, ContentItemRow[]> = await repo.contentCatalog().catch(() => ({}));
    const items = catalog[stage] ?? [];
    const item = items.find((i) => i.id === id) as ReviewableItem | undefined;
    if (!item) return reply.code(404).send({ error: 'not_found' });
    if (!item.medical) {
      // Not an error worth blocking on, but not a silent success either: a
      // review recorded against a card nobody will ever gate on is a signature
      // that means nothing, and whoever gave it should know.
      return reply.code(409).send({
        error: 'not_medical',
        message: 'Эта карточка не помечена как медицинская — проверка не требуется.',
      });
    }

    const review = { by: s.staffId, at: new Date().toISOString(), fingerprint: textFingerprint(item) };
    const next = items.map((i) => (i.id === id ? { ...i, review } : i));
    await repo.putStageContent(stage, next as ContentItemRow[]);
    // Named as its own action rather than folded into edit_content: this is the
    // record that a clinician took responsibility for a piece of advice.
    await repo.writeAudit({ staffId: s.staffId, action: 'content_review', target: `${stage}/${id}` });
    return reply.send({ ok: true, review });
  });

  /**
   * Everything waiting on a clinician — the queue that makes the rule workable.
   *
   * Without it the review rule is a wall: an author is refused and a clinician
   * has no way to find what is refused. `stale` items are listed first because
   * they are the dangerous kind — the card is LIVE and its text has moved since
   * anybody checked it.
   */
  app.get('/admin/content/review-queue', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const catalog = await repo.contentCatalog().catch(() => ({}));
    const waiting: Array<{ stage: string; id: string; title: string; reason: string; draft: boolean }> = [];
    for (const [stage, items] of Object.entries(catalog)) {
      for (const raw of items) {
        const item = raw as ReviewableItem;
        if (!item.medical) continue;
        if (reviewIsCurrent(item)) continue;
        waiting.push({
          stage,
          id: item.id,
          title: item.title?.ru ?? item.title?.kk ?? item.id,
          reason: item.review ? 'stale' : 'never',
          draft: item.draft === true,
        });
      }
    }
    waiting.sort((a, b) => (a.reason === b.reason ? 0 : a.reason === 'stale' ? -1 : 1));
    return reply.send({ waiting });
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
    const s = await requireCap(req, reply, 'content');
    if (!s) return;

    const parsed = bulkContentBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const { stages, mode } = parsed.data;
    const keys = Object.keys(stages);

    // Validate every key and every id BEFORE the first write.
    const untranslated: Array<BilingualProblem & { stage: string }> = [];
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
        // Collected across the WHOLE file rather than thrown on the first one.
        // An import is a spreadsheet somebody spent a day on; being told about
        // one missing translation per upload is how a day becomes a week.
        for (const p of bilingualProblems(item)) untranslated.push({ stage: key, ...p });
      }
    }
    // Same medical rule as the per-stage save, over the whole file. An import
    // is the easy way to publish a hundred unreviewed cards at once, which is
    // exactly why it cannot be the exception.
    const existingCatalog: Record<string, ContentItemRow[]> =
      await repo.contentCatalog().catch(() => ({}));
    const unreviewedRows: Array<{ stage: string; id: string; reason: string }> = [];
    for (const key of keys) {
      const prior = new Map(((existingCatalog[key] ?? []) as ReviewableItem[]).map((i) => [i.id, i]));
      for (const p of unreviewed(stages[key], prior)) unreviewedRows.push({ stage: key, ...p });
    }

    if (untranslated.length) {
      return reply.code(400).send({
        error: 'translation_required',
        problems: untranslated,
        message: `${untranslated.length} материалов без перевода — ничего не записано. ` +
          bilingualMessage(untranslated.slice(0, 5)) +
          (untranslated.length > 5 ? ` и ещё ${untranslated.length - 5}` : ''),
      });
    }

    if (unreviewedRows.length) {
      return reply.code(409).send({
        error: 'review_required',
        problems: unreviewedRows,
        message: `${unreviewedRows.length} медицинских материалов без проверки врачом — ` +
          'ничего не записано. ' + reviewMessage(unreviewedRows.slice(0, 5) as never),
      });
    }

    // 'replace' clears every stage absent from the file. It is destructive in a
    // way 'merge' is not — a file covering ten stages would wipe the other
    // ninety-one — so it only ever happens when asked for by name.
    const toClear = mode === 'replace'
      ? Object.keys(existingCatalog).filter((k) => !(k in stages))
      : [];

    for (const key of keys) {
      const prior = new Map(((existingCatalog[key] ?? []) as ReviewableItem[]).map((i) => [i.id, i]));
      const toStore = stages[key].map((i) => carryReview(i, prior.get(i.id)));
      await repo.putStageContent(key, toStore as ContentItemRow[]);
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
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    return reply.send({ audit: await repo.listAudit(limit) });
  });

  // ---- Shop: inventory (per-colour stock) + orders to fulfil ----
  app.get('/admin/shop/variants', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    return reply.send({ variants: await repo.adminShopVariants() });
  });
  app.patch('/admin/shop/variants/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = z.object({ stock: z.number().int().min(0).max(100000) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.setShopVariantStock((req.params as { id: string }).id, parsed.data.stock);
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_set_stock', target: (req.params as { id: string }).id });
    return reply.send({ ok: true });
  });
  app.post('/admin/shop/variants', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const parsed = z.object({
      productId: z.string().min(1).max(64),
      color: z.string().trim().min(1).max(60),
      colorHex: z.string().regex(/^#[0-9a-fA-F]{6}$/),
      stock: z.number().int().min(0).max(100000).default(0),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const { productId, color, colorHex, stock } = parsed.data;
    await repo.addShopVariant(productId, color, colorHex, stock);
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_add_variant', target: `${productId}/${color}` });
    return reply.code(201).send({ ok: true });
  });
  app.get('/admin/shop/orders', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    await repo.writeAudit({ staffId: s.staffId, action: 'view_shop_orders' });
    return reply.send({ orders: await repo.adminShopOrders(limit) });
  });

  // App settings & integration keys — WhatsApp/Kaspi (public, shown on the
  // landing) plus secret API keys (Anthropic, Google Maps) used server-side.
  // Editable by staff; the public /shop/config exposes ONLY the public keys.
  app.get('/admin/settings', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    // Auditable: this exposes the stored API keys, so record who read them.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_settings' });
    return reply.send({ settings: await repo.getShopSettings() });
  });
  app.put('/admin/settings', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const parsed = z.object({
      whatsapp: z.string().trim().max(32).optional(),
      kaspiUrl: z.string().trim().max(500).optional(),
      anthropicApiKey: z.string().trim().max(300).optional(),
      // No googleMapsApiKey. The app's map key is a build-time input baked into
      // the Android manifest, so nothing server-side could ever act on one
      // stored here — see the note in index.ts. A row already in the table is
      // left alone; it is simply never read.
      // Where a new callback request is announced. SECRET — the bot token lets
      // anyone post as the bot, so like the API keys it must never appear in
      // the public /shop/config.
      telegramBotToken: z.string().trim().max(200).optional(),
      telegramChatId: z.string().trim().max(64).optional(),
      // Social proof — public. reviews is a JSON array of {name,city,text,stars}.
      reviews: z.string().trim().max(6000).optional(),
      rating: z.string().trim().max(8).optional(),
      reviewCount: z.string().trim().max(12).optional(),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    // Store only the keys actually sent. The phone is normalised to digits so
    // wa.me links work regardless of how it was typed.
    const patch: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed.data)) {
      if (v === undefined) continue;
      patch[k] = k === 'whatsapp' ? v.replace(/\D/g, '') : v;
    }
    await repo.setShopSettings(patch);
    // Audit key NAMES only — never the secret values.
    await repo.writeAudit({ staffId: s.staffId, action: 'set_settings', target: Object.keys(patch).join(',') });
    return reply.send({ ok: true, settings: await repo.getShopSettings() });
  });
  // Prove the Telegram settings actually work.
  //
  // Saving them succeeds regardless of whether the token is valid, so without
  // this the first sign of a typo is a customer who was never called back. The
  // whole point is to fail here, loudly, in front of the person who can fix it.
  app.post('/admin/settings/test-telegram', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const cfg = await repo.getShopSettings();
    if (!cfg.telegramBotToken?.trim() || !cfg.telegramChatId?.trim()) {
      return reply.send({ ok: false, error: 'сначала сохраните токен и chat ID' });
    }
    await repo.writeAudit({ staffId: s.staffId, action: 'test_telegram' });
    const result = await sendTelegramTest(cfg.telegramBotToken, cfg.telegramChatId);
    return reply.send(result);
  });

  /**
   * Record an order taken by hand.
   *
   * Almost every sale arrives on WhatsApp or through Kaspi — a person calls,
   * staff write the address down. Until now there was nowhere to put it: the
   * only thing that could create an order was the public storefront, and the
   * storefront was retired. So stock never moved, revenue never appeared, and
   * the комплект could not grant the course it is sold with, because no order
   * for it could exist.
   *
   * Same repository call as the storefront used, so it is one code path: stock
   * comes off atomically, the ledger gets its 'sale' rows, and a bundle is
   * priced and validated by the server rather than by whoever is typing.
   */
  app.post('/admin/shop/orders', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const parsed = z.object({
      customerName: z.string().trim().min(1).max(120),
      phone: z.string().trim().min(5).max(40),
      city: z.string().trim().min(1).max(120),
      address: z.string().trim().min(3).max(400),
      note: z.string().trim().max(500).optional(),
      items: z.array(z.object({
        variantId: z.string().min(1).max(64),
        qty: z.number().int().min(1).max(20),
      })).min(1).max(10),
      bundleId: z.string().min(1).max(64).optional(),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const res = await repo.placeShopOrder(parsed.data);
    if (!res.ok) {
      // 409 for "the shelf disagrees", 400 for "the order is malformed" — the
      // panel says something different for each, and staff can act on the first.
      return reply.code(res.error === 'out_of_stock' ? 409 : 400)
        .send({ error: res.error, variantId: res.variantId });
    }
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_order_create', target: res.id });
    return reply.code(201).send({ id: res.id, totalMinor: res.totalMinor, discountMinor: res.discountMinor });
  });

  app.patch('/admin/shop/orders/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const parsed = z.object({ status: z.enum(['new', 'confirmed', 'shipped', 'delivered', 'cancelled']) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.setShopOrderStatus((req.params as { id: string }).id, parsed.data.status);
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_order_status', target: (req.params as { id: string }).id });
    return reply.send({ ok: true });
  });

  /**
   * Which physical units went out with this order.
   *
   * Recorded at DISPATCH — at intake there is no order yet. It is the link that
   * answers "she says her tracker is broken; which one did we send her, and
   * when?", which nothing in the system could answer before: the registry knew
   * the unit and the order knew the customer, and the two never met.
   */
  app.get('/admin/shop/orders/:id/devices', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { id } = req.params as { id: string };
    // Audited: an order names a customer, so "which devices went to this order"
    // is a read about a person, not an aggregate.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_order_devices', target: id });
    return reply.send({ devices: await repo.devicesForOrder(id) });
  });

  app.post('/admin/shop/orders/:id/devices', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = z.object({ serials: z.string().min(1).max(5000) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const serials = parsed.data.serials.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean);
    if (serials.length === 0) return reply.code(400).send({ error: 'no_serials' });

    const result = await repo.assignDevicesToOrder(id, serials);
    await repo.writeAudit({ staffId: s.staffId, action: 'order_devices', target: id });
    // The unrecognised ones come back so the packer sees them. A typo on a
    // packing slip that is silently accepted becomes a warranty case nobody
    // can trace.
    return reply.send({ ok: true, ...result });
  });

  // Landing-page callback requests ("перезвоним сами"). A queue of phone numbers
  // to work through, not orders — staff call, then mark what came of it.
  app.get('/admin/shop/leads', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    await repo.writeAudit({ staffId: s.staffId, action: 'view_shop_leads' });
    return reply.send({ leads: await repo.adminShopLeads(limit) });
  });
  app.patch('/admin/shop/leads/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const parsed = z.object({ status: z.enum(['new', 'called', 'ordered', 'dropped']) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.setShopLeadStatus((req.params as { id: string }).id, parsed.data.status);
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_lead_status', target: (req.params as { id: string }).id });
    return reply.send({ ok: true });
  });

  // ---- Daily calendar audio (pregnancy + child development) ----
  const audioParams = z.object({
    track: z.enum(['pregnancy', 'child']),
    day: z.coerce.number().int().min(1).max(400),
    locale: z.enum(['ru', 'kk']),
  });

  // Coverage list for a track (metadata only — which days have a clip).
  app.get('/admin/audio', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const track = (req.query as { track?: string }).track;
    if (track !== 'pregnancy' && track !== 'child') return reply.code(400).send({ error: 'bad_track' });
    return reply.send({ audio: await repo.listDailyAudio(track) });
  });

  // Upload/replace a day's clip. Raw audio bytes in the body (content-type is the
  // audio mime); the day/locale come from the path and an optional ?title=.
  app.post('/admin/audio/:track/:day/:locale', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const p = audioParams.safeParse(req.params);
    if (!p.success) return reply.code(400).send({ error: p.error.flatten() });
    const mime = String(req.headers['content-type'] ?? '');
    if (!/^audio\//.test(mime)) return reply.code(415).send({ error: 'not_audio' });
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) return reply.code(400).send({ error: 'empty_audio' });
    const title = ((req.query as { title?: string }).title ?? '').slice(0, 200) || null;
    await repo.upsertDailyAudio({ track: p.data.track, day: p.data.day, locale: p.data.locale, title, mime: mime.split(';')[0], bytes: body });
    await repo.writeAudit({ staffId: s.staffId, action: 'audio_upload', target: `${p.data.track}/${p.data.day}/${p.data.locale}` });
    return reply.code(201).send({ ok: true });
  });

  app.delete('/admin/audio/:track/:day/:locale', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const p = audioParams.safeParse(req.params);
    if (!p.success) return reply.code(400).send({ error: p.error.flatten() });
    await repo.deleteDailyAudio(p.data.track, p.data.day, p.data.locale);
    await repo.writeAudit({ staffId: s.staffId, action: 'audio_delete', target: `${p.data.track}/${p.data.day}/${p.data.locale}` });
    return reply.send({ ok: true });
  });
}

function clampLimit(raw: string | undefined, def: number, max: number): number {
  const n = Number(raw ?? def);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(max, Math.floor(n));
}
