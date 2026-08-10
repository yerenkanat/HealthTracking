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
import type { ContentItemRow, Repository, ShopOrder } from '../db/repository';
import { PRODUCT_STAGES } from '../db/repository';
import { buildIntegrations, integrationSummary, maskSecret } from '../admin/integrations';
import { buildFinanceReport, financeCsv } from '../admin/finance';
import { bilingualMessage, bilingualProblems, type BilingualProblem } from '../content/bilingual';
import { buildQueues, overdue, SLA_HOURS } from '../admin/queues';
import { summarizeSecurity } from '../admin/security';
import { buildOwnerDashboard } from '../admin/ownerDashboard';
import { buildMotherCard } from '../admin/motherCard';
import { MAMA_COURSE } from './entitlements';
import { normalizePhone } from '../phone';
import { ROUTE_RETENTION_DAYS } from '../privacy/retention';
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

import {
  ALL_CAPABILITIES, can, ROLE_CAPS, STAFF_ROLES,
  type Capability, type StaffRole,
} from '../auth/capabilities';
export type AuthAdmin = (req: FastifyRequest) => Promise<{ staffId: string; role: StaffRole } | null>;

/**
 * What frame 24 needs to know about the RUNNING server, which it cannot read
 * off the environment.
 *
 * index.ts only wires a real SMS sender under conditions this module cannot
 * see — `smsSender()` returns a console logger under dev shortcuts and
 * undefined otherwise — so a screen that inferred "подключено" from an
 * environment variable would report exactly the silent failure it exists to
 * expose. These are facts about what was actually injected.
 *
 * All optional and false by default: an older caller reports "off", which is
 * the safe direction to be wrong in.
 */
export interface AdminRuntimeFacts {
  /** A real gateway, not the console logger. */
  smsSenderIsReal?: boolean;
  /** The EFFECTIVE gate: a code is demanded and can be sent. */
  requirePhoneCode?: boolean;
  /** REQUIRE_PHONE_CODE=1 was set, whether or not it could be honoured. */
  phoneCodeRequested?: boolean;
  /** A push sender is wired and can deliver. */
  pushWired?: boolean;
}

export function registerAdminRoutes(
  app: FastifyInstance,
  repo: Repository,
  authAdmin: AuthAdmin,
  runtime: AdminRuntimeFacts = {},
): void {
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

  /**
   * How many of her orders the mother's card counts over.
   *
   * A window, not "all of them", because this is one indexed read inside a
   * request that already does a dozen. It is generous enough that a real
   * customer never hits it — but when she does, the card SAYS the figures are
   * a window rather than presenting a partial spend as her whole history.
   */
  const MOTHER_ORDER_WINDOW = 100;

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

    /**
     * Frame 09a — the card's right-hand column: «этап, заказы, курс».
     *
     * All three were already in the database and none of them reached this
     * card, so an operator answering «где мой заказ» left the mother's record,
     * opened the orders tab, and searched by a number she had just read out —
     * with the record she was supposed to be reading still open behind her.
     *
     * Everything below is keyed on the NORMALISED phone. Orders arrive from
     * the landing page, from WhatsApp typed by staff, and from the app, in
     * three different written forms of one number; the entitlement and the
     * course rows are stored under the normalised form. Matching on the raw
     * string is how a woman with a charge on her card gets an empty card —
     * see src/phone.ts.
     *
     * A profile with no phone at all owns nothing we can find, which is a real
     * answer (an empty block) rather than a missing one.
     */
    const phone = normalizePhone(detail.phone ?? '');

    /**
     * Read-only and best-effort, every one of them: a failure in the shop or
     * the course must not blank the clinical card this route primarily is.
     *
     * But best-effort is not the same as pretending. A `.catch(() => [])` here
     * turns "shop_orders is unreachable" into "she has never ordered", and the
     * panel then prints «Заказов на этот номер нет» at an operator on the
     * phone with a woman holding her Kaspi receipt. So each failure is CARRIED
     * — the card gets the empty value AND the fact that we could not look.
     */
    const settled = async <T>(p: Promise<T>, fallback: T): Promise<{ value: T; failed: boolean }> => {
      try {
        return { value: await p, failed: false };
      } catch (err) {
        req.log.warn({ err, userId }, 'mother card: a side read failed');
        return { value: fallback, failed: true };
      }
    };

    const [appointments, orders, courseUnlocked, courseProgress] = await Promise.all([
      // Her upcoming visits, so staff can see the antenatal plan she is
      // actually keeping.
      repo.listAppointments(userId).catch(() => []),
      // shopOrdersByPhone, not adminShopOrders filtered here: the indexed
      // per-customer query is the one the shop already answers screen 42 with,
      // and it matches on phone_normalized. Pulling the last N orders in the
      // whole shop and filtering in Node would silently lose the customer who
      // ordered before the window — precisely the woman who rings up to ask
      // where her order is.
      phone
        ? settled(repo.shopOrdersByPhone(phone, MOTHER_ORDER_WINDOW), [] as ShopOrder[])
        : Promise.resolve({ value: [] as ShopOrder[], failed: false }),
      phone
        ? settled(repo.hasEntitlement(phone, MAMA_COURSE), false)
        : Promise.resolve({ value: false, failed: false }),
      phone
        ? settled(repo.courseProgress(phone), [] as Awaited<ReturnType<typeof repo.courseProgress>>)
        : Promise.resolve({ value: [] as Awaited<ReturnType<typeof repo.courseProgress>>, failed: false }),
    ]);

    const mother = buildMotherCard({
      dueDate: detail.dueDate,
      children: detail.children,
      orders: orders.value,
      courseUnlocked: courseUnlocked.value,
      courseProgress: courseProgress.value,
      now: new Date().toISOString(),
      ordersUnavailable: orders.failed,
      // Either half missing makes the course block a guess: an entitlement we
      // could not read and progress rows we could not count are both «неизвестно».
      courseUnavailable: courseUnlocked.failed || courseProgress.failed,
      ordersWindow: MOTHER_ORDER_WINDOW,
      // A full window means there is very likely an older order we did not
      // count. The card says so rather than presenting a partial total as her
      // whole history.
      ordersTruncated: orders.value.length >= MOTHER_ORDER_WINDOW,
    });

    return reply.send({ ...detail, appointments, mother });
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
   * Frame 00 — «Дашборд владельца». The money, what is on fire, and one
   * decision.
   *
   * Separate from /admin/dashboard, which is the raw snapshot: this one is the
   * OWNER's reading of it, and it exists because the raw snapshot answered
   * "what is true" without ever answering "so what". Every signal in «Что
   * горит» is read from the system that owns it rather than recomputed here —
   * a second implementation of "which stock is low" is a second answer to it.
   *
   * `finance`, like the snapshot it is built from.
   */
  app.get('/admin/owner', async (req, reply) => {
    const s = await requireCap(req, reply, 'finance');
    if (!s) return;
    const now = new Date();

    const [orders, products, snapshot, catalog, settings, audit] = await Promise.all([
      repo.adminShopOrders(500).catch(() => []),
      repo.adminProducts().catch(() => []),
      repo.dashboardSnapshot(now.toISOString()).catch(() => null),
      repo.contentCatalog().catch(() => ({} as Record<string, ContentItemRow[]>)),
      repo.getShopSettings().catch(() => ({} as Record<string, string>)),
      repo.listAudit(2000).catch(() => []),
    ]);

    // Medical cards published without a current signature — the same rule the
    // review queue applies, not a second opinion about it.
    let unreviewedMedical = 0;
    for (const items of Object.values(catalog)) {
      for (const raw of items) {
        const item = raw as ReviewableItem;
        if (item.medical && !item.draft && !reviewIsCurrent(item)) unreviewedMedical++;
      }
    }

    const q = buildQueues(
      {
        leads: await repo.adminShopLeads(200).catch(() => []),
        orders,
        emergencies: await repo.recentEmergencies(200).catch(() => []),
      },
      now.getTime(),
    );

    // Absent or unparseable is NO plan, not a plan of zero — the difference
    // between "we missed the target" and "nobody set one".
    const rawPlan = Number(settings.revenuePlanMinor);
    const planMinor = Number.isFinite(rawPlan) && rawPlan > 0 ? rawPlan : null;

    const course = snapshot?.course;
    return reply.send({
      asOf: now.toISOString(),
      ...buildOwnerDashboard(
        {
          orders,
          products,
          planMinor,
          signals: {
            overdue: overdue(q),
            lowStock: snapshot?.commerce.lowStock ?? [],
            unreviewedMedical,
            unregisteredDevices: snapshot?.devices.unregistered ?? 0,
            accessWithoutReason: summarizeSecurity(audit, now, 30).withoutReason,
            // Bought and never opened. Granted-minus-started, floored: a
            // negative would mean somebody is watching without access, which
            // is a different bug and must not show up here as a negative count.
            courseNeverStarted: course ? Math.max(0, course.granted - course.started) : 0,
          },
        },
        now,
      ),
      // For «Кто с нами» and «Живо ли приложение» — the third row of the frame.
      // Passed through rather than recomputed, so the owner's screen and the
      // Dashboard tab cannot disagree about how many mothers there are.
      who: snapshot
        ? {
            mothers: snapshot.mothers,
            children: snapshot.children.total,
            devices: snapshot.devices,
            dau: snapshot.users.dau,
            wau: snapshot.users.wau,
            mau: snapshot.users.mau,
            retentionD7: snapshot.users.retentionD7,
            course: snapshot.course,
          }
        : null,
    });
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

  /**
   * Frame 22 — «Безопасность». Who has been reading special-category data.
   *
   * Every part of this existed and none of it was on a screen: the log records
   * who opened whose record and why, the matrix decides who may, and the
   * retention sweep deletes routes at 90 days. What was missing was the page
   * that lets somebody ASK whether it is being abused.
   *
   * `staff`, like the audit log itself — being able to read health records is
   * not the same as being able to read the record of everyone reading them.
   */
  app.get('/admin/security', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const days = Math.min(365, Math.max(1, Number((req.query as { days?: string }).days) || 30));
    // A wide slice, because the summary counts over it and the panel shows the
    // hundred newest. Bounded so a year cannot pull the whole table.
    const audit = await repo.listAudit(5000).catch(() => []);
    // This page lists patients by name — «кто открывал карту Айгерім и почему»
    // — so reading it is itself a read of special-category data and is
    // recorded. Unlike GET /admin/audit, which returns the raw log and is
    // exempt because auditing it makes the log describe mostly itself, this
    // one is opened rarely and deliberately: the row is worth having.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_security' });
    return reply.send({
      ...summarizeSecurity(audit, new Date(), days),
      // The retention promises this page reports on, from the one place each
      // is defined — so the screen cannot drift from what actually runs.
      retention: {
        routeDays: ROUTE_RETENTION_DAYS,
        auditYears: 3,
      },
    });
  });

  /**
   * Frame 23a — «Роли и права». The permission matrix, as data.
   *
   * Served from ROLE_CAPS rather than re-typed in the panel's HTML. A matrix
   * the panel draws from its own copy is a matrix that tells a manager one
   * thing while the guards do another, and the whole point of the screen is
   * that somebody can trust it when deciding what a new hire may see.
   *
   * The spec draws 18 permission rows against 5 roles. The guards enforce 8
   * capabilities across 8 roles, so the rows here are the capabilities — every
   * one true, and every one backed by a `requireCap` somewhere — instead of 18
   * invented names the server would not honour. `special` marks the rows the
   * spec highlights: the ones carrying health or a child's whereabouts.
   */
  app.get('/admin/roles', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    return reply.send({
      roles: STAFF_ROLES.map((role) => ({ role, caps: ROLE_CAPS[role] })),
      caps: ALL_CAPABILITIES.map((cap) => ({
        cap,
        // Health readings, children and their locations travel under `health`;
        // an SOS carries a live position with a name beside it.
        special: cap === 'health' || cap === 'emergencies',
      })),
      /** Who is signed in, so the panel can mark their own row. */
      you: s.role,
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
  // ---- Catalogue (frames 08 / 08a / 08b) ----
  //
  // `catalog` capability, not `stock`: deciding what a product IS — its stage,
  // its age band, its Kazakh copy — is the content editor's job, and the spec
  // gives the seller stock and prices without the catalogue. Reading is open to
  // any signed-in staff member, because every screen that lists an order needs
  // to name the product on it.
  app.get('/admin/shop/products', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const [all, categories] = await Promise.all([
      repo.adminProducts(),
      repo.listShopCategories(),
    ]);

    // «Продавец … без маржи». Cost is the one field on a product that is not
    // everybody's business, so it is REMOVED for accounts without `stock`
    // rather than the whole screen being refused: every role that reads an
    // order needs to name the product on it.
    const seesCost = can(s.role, 'stock');
    const products = seesCost ? all : all.map(({ costMinor: _cost, ...rest }) => rest);

    return reply.send({ products, categories, stages: PRODUCT_STAGES, seesCost });
  });

  app.patch('/admin/shop/products/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const { id } = req.params as { id: string };

    // .optional() on every field and no .default() anywhere: an absent key must
    // leave the column alone, so saving the SEO tab cannot wipe персонализация.
    // .nullable() where the panel offers a «не указан» — clearing is a real
    // edit and must be distinguishable from not touching it.
    const text = (max: number) => z.string().trim().max(max).nullable().optional();
    const parsed = z.object({
      name: z.string().trim().min(1).max(120).optional(),
      nameKk: text(120),
      priceMinor: z.number().int().min(0).max(100_000_000).optional(),
      costMinor: z.number().int().min(0).max(100_000_000).nullable().optional(),
      active: z.boolean().optional(),
      sort: z.number().int().min(0).max(9999).optional(),
      sku: text(64),
      category: text(64),
      stage: z.enum(PRODUCT_STAGES).nullable().optional(),
      descriptionRu: text(4000),
      descriptionKk: text(4000),
      ageMinMonths: z.number().int().min(0).max(216).nullable().optional(),
      ageMaxMonths: z.number().int().min(0).max(216).nullable().optional(),
      photoUrl: text(500),
      seoSlug: text(120),
      seoTitle: text(200),
      seoDescription: text(400),
    }).strict().safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const patch = parsed.data;

    // The DB has the same CHECK, but a 400 naming the field beats a 500 from a
    // constraint violation on a screen where somebody just typed two numbers.
    const lo = patch.ageMinMonths, hi = patch.ageMaxMonths;
    if (lo != null && hi != null && lo > hi) {
      return reply.code(400).send({ error: 'age_min_months must not exceed age_max_months' });
    }

    // «Двуязычность блокирует публикацию» — the same rule the content editor
    // applies to a lesson. Checked against what the row will BE, not what was
    // sent, so activating a product whose Kazakh name is already missing is
    // refused too.
    if (patch.active === true) {
      const current = (await repo.adminProducts()).find((p) => p.id === id);
      if (!current) return reply.code(404).send({ error: 'not found' });
      const kk = patch.nameKk !== undefined ? patch.nameKk : current.nameKk;
      if (!kk || !kk.trim()) {
        return reply.code(400).send({ error: 'kk_required', field: 'nameKk' });
      }
    }

    await repo.updateProduct(id, patch);
    await repo.writeAudit({
      staffId: s.staffId,
      action: 'product_update',
      target: id,
      reason: Object.keys(patch).join(','),
    });
    return reply.send({ ok: true });
  });

  app.put('/admin/shop/categories/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const parsed = z.object({
      nameRu: z.string().trim().min(1).max(80),
      nameKk: z.string().trim().max(80).nullable().optional(),
      sort: z.number().int().min(0).max(9999).default(0),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const { id } = req.params as { id: string };
    if (!/^[a-z0-9_-]{1,64}$/.test(id)) {
      return reply.code(400).send({ error: 'id must be a slug: a-z, 0-9, _ and -' });
    }
    await repo.upsertShopCategory({
      id, nameRu: parsed.data.nameRu, nameKk: parsed.data.nameKk ?? null, sort: parsed.data.sort,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'category_upsert', target: id });
    return reply.send({ ok: true });
  });

  app.delete('/admin/shop/categories/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const { id } = req.params as { id: string };
    const ok = await repo.deleteShopCategory(id);
    // 409, not 404: the category exists, and the caller needs to know the
    // difference between "gone" and "still in use".
    if (!ok) return reply.code(409).send({ error: 'category_in_use' });
    await repo.writeAudit({ staffId: s.staffId, action: 'category_delete', target: id });
    return reply.send({ ok: true });
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
      /**
       * The month's revenue target in minor units, for «выручка к плану» on
       * the owner's dashboard.
       *
       * Digits only. A target that fails to parse would read there as no plan
       * at all — the screen cannot distinguish them — so a typo is refused
       * here where somebody is looking at it, rather than silently blanking a
       * number on another screen next week. Empty string clears it.
       */
      revenuePlanMinor: z.string().trim().regex(/^\d*$/).max(15).optional(),
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
  /**
   * Frames 05 / 05a / 05b — «Финансы», «Возвраты и брак», «Отчёт».
   *
   * `owner`-shaped work, so it needs the capability that already gates margin:
   * «продавец … без маржи». A seller reading this would see exactly what the
   * spec keeps from them.
   *
   * The window defaults to the current month, which is what «выручка к плану»
   * is measured against — a default of "everything" would answer a question
   * nobody asked and be slow besides.
   */
  app.get('/admin/finance', async (req, reply) => {
    const s = await requireCap(req, reply, 'stock');
    if (!s) return;

    const q = req.query as { from?: string; to?: string; format?: string };
    const iso = /^\d{4}-\d{2}-\d{2}$/;
    const today = new Date().toISOString().slice(0, 10);
    const to = iso.test(q.to ?? '') ? q.to! : today;
    const from = iso.test(q.from ?? '') ? q.from! : `${today.slice(0, 7)}-01`;
    if (from > to) {
      return reply.code(400).send({ error: 'from must not be after to' });
    }

    const [orders, products, moves, settings] = await Promise.all([
      repo.adminShopOrders(1000).catch(() => []),
      repo.adminProducts().catch(() => []),
      repo.stockMoves(2000).catch(() => []),
      repo.getShopSettings().catch(() => ({} as Record<string, string>)),
    ]);

    const planRaw = (settings.revenuePlanMinor ?? '').trim();
    const report = buildFinanceReport({
      orders, products, moves,
      planMinor: /^\d+$/.test(planRaw) ? Number(planRaw) : null,
      from, to,
    });

    // Reading the books is worth recording: it is the one screen that shows
    // margin and cost across the whole business.
    await repo.writeAudit({
      staffId: s.staffId, action: 'view_finance', reason: `${from}..${to}`,
    });

    if (q.format === 'csv') {
      return reply
        .header('content-type', 'text/csv; charset=utf-8')
        .header('content-disposition', `attachment; filename="finance-${from}_${to}.csv"`)
        .send(financeCsv(report));
    }
    return reply.send(report);
  });

  /**
   * Frame 24 — «Интеграции».
   *
   * `staff`, same as /admin/settings: this is about keys and outside services,
   * which is an owner/admin concern rather than a seller's.
   *
   * NOT audited, unlike /admin/settings — and deliberately, because unlike that
   * route this one returns no secret. A stored key comes back as `••••7f2a`,
   * which tells an operator which key is installed and a shoulder-surfer
   * nothing. Auditing a screen that reveals nothing would bury the entries
   * recording who read the real values.
   */
  app.get('/admin/integrations', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const settings = await repo.getShopSettings().catch(() => ({} as Record<string, string>));
    const list = buildIntegrations({
      settings,
      // Asked of the running server rather than assumed from the environment:
      // index.ts only wires a REAL sender under conditions this route cannot
      // see, and a screen that reports "подключено" because a variable is set
      // would be exactly the silent failure it exists to expose.
      smsSenderIsReal: runtime.smsSenderIsReal ?? false,
      requirePhoneCode: runtime.requirePhoneCode ?? false,
      // The gap between what was asked for and what is in force. Without this
      // a server started with REQUIRE_PHONE_CODE=1 and no gateway looked
      // identical to one where nobody had tried — which is how the variable
      // came to be written down as a mitigation it cannot be.
      phoneCodeRequested: runtime.phoneCodeRequested ?? false,
      pushWired: runtime.pushWired ?? false,
      anthropicEnvKey: process.env.ANTHROPIC_API_KEY ?? null,
    });
    return reply.send({ integrations: list, summary: integrationSummary(list) });
  });

  /**
   * Frame 24b — «Проверить связь».
   *
   * A real round trip, reported step by step, because "не работает" is not a
   * diagnosis. Each step says what was tried and what came back, so the person
   * reading it knows whether to fix the key, the chat, or the network.
   *
   * Only integrations this server can actually reach are checkable; the rest
   * say so rather than offering a button that always fails.
   */
  app.post('/admin/integrations/:id/check', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const { id } = req.params as { id: string };
    const cfg = await repo.getShopSettings().catch(() => ({} as Record<string, string>));
    const steps: Array<{ step: string; ok: boolean; detail: string }> = [];

    if (id !== 'telegram') {
      // Honest refusal rather than a fake pass. Nothing else here has an
      // endpoint this server can call: SMS and push have no sender at all, and
      // the Maps key lives in the Android build.
      return reply.code(400).send({
        ok: false,
        steps: [{ step: 'Проверка', ok: false, detail: 'Эту интеграцию отсюда проверить нельзя' }],
      });
    }

    const token = (cfg.telegramBotToken ?? '').trim();
    const chat = (cfg.telegramChatId ?? '').trim();
    steps.push({
      step: 'Токен бота сохранён', ok: !!token,
      detail: token ? maskSecret(token)! : 'Токен не сохранён',
    });
    steps.push({
      step: 'Чат указан', ok: !!chat,
      detail: chat || 'Чат не указан',
    });

    if (!token || !chat) {
      return reply.send({ ok: false, steps });
    }

    await repo.writeAudit({ staffId: s.staffId, action: 'integration_check', target: id });
    const result = await sendTelegramTest(token, chat);
    steps.push({
      step: 'Тестовое сообщение доставлено',
      ok: !!result.ok,
      detail: result.ok ? 'Сообщение ушло в чат' : (result.error ?? 'Telegram не принял сообщение'),
    });
    return reply.send({ ok: !!result.ok, steps });
  });

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
