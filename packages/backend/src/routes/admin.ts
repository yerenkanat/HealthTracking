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
import type { ContentItemRow, Repository, ShopOrder, ShopOrderStatus } from '../db/repository';
import { ORDER_REFUND_REASONS, PRODUCT_STAGES, SHOP_ORDER_STATUSES, SUPPORT_CHANNELS, SUPPORT_STATUSES } from '../db/repository';
import { buildOrderTimeline, orderRef, orderWhatsappLink } from '../admin/orders';
import {
  buildIntegrations, integrationSummary, maskSecret,
  redactSettings, looksMasked, SECRET_SETTING_KEYS,
} from '../admin/integrations';
import { buildFinanceReport, financeCsv } from '../admin/finance';
import { buildSupportBoard, SUPPORT_SLA_HOURS, whatsappReplyLink } from '../admin/support';
import { bilingualMessage, bilingualProblems, missingLocales, type BilingualProblem } from '../content/bilingual';
import { weekAsReviewable, type PregnancyWeekOverride } from '../pregnancy/overrides';
import { servedCalendar } from '../pregnancy/served';
import { emergencyHelp, contractScenario } from '../emergency/help';
import { scenarioAsReviewable, type EmergencyHelpOverride } from '../emergency/overrides';
import { servedEmergencyHelp } from '../emergency/served';
import {
  CRY_MIN_CONFIDENCE_MAX, CRY_MIN_CONFIDENCE_MIN, servedCryThreshold,
} from '../cry/settings';
import {
  ageLabelRu, contractKey, vaccineAsReviewable, vaccineKeyOf,
  type VaccinationOverride,
} from '../vaccination/overrides';
import { servedVaccinationSchedule } from '../vaccination/served';
// Aliased: `coverageOf` in this file already means "how much of the timeline
// catalogue is filled in", which is a different question about a different table.
import {
  coverageOf as vaccinationCoverageOf, impactOf, impactOfNew,
} from '../vaccination/coverage';
import { buildQueues, overdue, SLA_HOURS } from '../admin/queues';
import {
  BROADCAST_AUDIENCES, BROADCAST_LOCALES, BROADCAST_MIN_GAP_DAYS, INFANT_MAX_MONTHS,
  SEGMENT_FIELDS, describeSegment, normalizeSegment, segmentMessage, validateSegment,
  type BroadcastSegment,
} from '../admin/broadcasts';
import { HOLD_REASON_RU, NOTIFY_CATEGORIES } from '../notifications/gate';
import { PROTECTED_ACTIONS, retentionSummary, summarizeSecurity } from '../admin/security';
import { buildOwnerDashboard } from '../admin/ownerDashboard';
import { buildMotherCard } from '../admin/motherCard';
import { MAMA_COURSE } from './entitlements';
import { normalizePhone } from '../phone';
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

/**
 * What a product photo may be, and how big.
 *
 * JPEG/PNG/WebP only: those three are what every browser and the Flutter app
 * decode without help. HEIC is deliberately absent — an iPhone will offer it,
 * and accepting a format half the surfaces cannot render is worse than
 * refusing it with a sentence naming what to use instead.
 *
 * 3 MB is a real product photo at a sane resolution. Above that somebody has
 * uploaded a 40-megapixel original, and the storefront becomes unusable on the
 * mobile connection most of these customers are on. The same ceiling is a CHECK
 * constraint in migration 044, because a limit enforced only at the route is a
 * limit that a second route will forget.
 */
const ALLOWED_PHOTO_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_PHOTO_BYTES = 3 * 1024 * 1024;
/** Where a stored photo is served from — one definition, used by the upload's
 *  reply and by the storefront payload, so the two cannot drift. */
export const photoUrlFor = (productId: string, color: string) =>
  `/shop/products/${encodeURIComponent(productId)}/photo${color ? `?color=${encodeURIComponent(color)}` : ''}`;

const localizedText = z.record(z.string(), z.string());
/**
 * An article's own text, per locale (admin frame 16a).
 *
 * Capped because this lands in a JSONB payload that is downloaded WHOLE to
 * every phone by `GET /content` — the catalogue is one document, so one pasted
 * book costs every mother on a mobile connection her data. 12 000 characters is
 * roughly two thousand words, several times the longest guide anybody has
 * asked for, and refusing at the edge names the field instead of letting the
 * app fail to load a week later.
 */
const articleText = z.record(z.string(), z.string().max(12000));
/** «Красный флаг» — short by nature: the few lines that mean "stop reading". */
const redFlagText = z.record(z.string(), z.string().max(2000));
const contentItem = z.object({
  id: z.string().min(1).max(80),
  kind: z.enum(['lesson', 'product']),
  title: localizedText,
  summary: localizedText,
  /**
   * The article itself — what a woman actually reads (admin frame 16a).
   *
   * A guide used to be a headline, a one-line summary and an external `url`,
   * which meant tapping one either threw her into a browser or, with no url,
   * did nothing at all. There was no way to write a guide and no way to read
   * one. This is the text, in her language, rendered as plain paragraphs.
   *
   * Optional, and it stays optional: the published catalogue predates it
   * entirely, and every one of those items must keep saving. See
   * content/bilingual.ts for why "optional" does not mean "translatable
   * later".
   *
   * It must be listed here or it would not exist: z.object STRIPS unknown
   * keys, so an absent field would mean every panel save silently erased an
   * article somebody had written.
   */
  body: articleText.optional(),
  /**
   * «Красный флаг» — when to stop reading this and call.
   *
   * Its OWN field rather than a paragraph of `body`, because
   * docs/CLAUDE-app-design.md §4.6 requires red flags in their own block and
   * never behind «читать дальше». A separate field is what lets the app draw
   * it above the article and always expanded; buried in the prose it would be
   * one paragraph among twenty, below the fold, at 2am.
   */
  redFlags: redFlagText.optional(),
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
   * Which shelf of the app's guides library (app screen 27) this belongs on.
   *
   * A CLOSED vocabulary rather than free text, because the app draws exactly
   * four tiles: a fifth value would be stored, downloaded to every phone and
   * rendered nowhere — this repo's commonest defect.
   *
   * Optional, and being optional is the point: 364 items are already published
   * and none of them carries this. The app derives a topic from the home stage
   * for anything untagged (w* → pregnancy, m0-m12 → baby, m13+ → child), so
   * the grid is full on day one and tagging is an improvement rather than a
   * migration. `mother` is the one no stage implies, so it is only ever
   * explicit — content about HER, at whatever week the baby is.
   *
   * It must be listed here or it would not exist: z.object STRIPS unknown
   * keys, so an absent field here would mean every panel save silently erased
   * a topic somebody had set.
   */
  topic: z.enum(['pregnancy', 'baby', 'child', 'mother']).optional(),
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
    // Generous because the fingerprint now quotes the whole article back (see
    // content/medicalReview.ts). The panel round-trips the stored review with
    // every save, so a cap below what textFingerprint can produce would 400
    // every attempt to re-save an approved article — and the field is ignored
    // on the way in anyway, so the ceiling only has to be big enough to accept
    // what this server itself wrote.
    fingerprint: z.string().max(120000),
  }).optional(),
}).refine((i) => i.minAgeYears == null || i.maxAgeYears == null || i.minAgeYears <= i.maxAgeYears, {
  // An inverted range matches nobody, so the item would vanish with no error
  // anywhere. Rejecting it at the edge is the only place a person sees why.
  message: 'minAgeYears must not exceed maxAgeYears',
  path: ['minAgeYears'],
});
const stageContentBody = z.object({ items: z.array(contentItem).max(50) });

/// One language's half of a calendar week (frame 14b).
///
/// Length-capped rather than free: this text is rendered into a fixed card in
/// the app and on a phone-sized screen, and a pasted essay would push the
/// recommendation — the actionable half — below the fold. Generous enough for
/// the longest week in the shipped contract, several times over.
const weekText = z.object({
  baby: z.string().trim().max(2000),
  you: z.string().trim().max(2000),
  recommend: z.string().trim().max(2000),
});

const pregnancyWeekBody = z.object({
  /// Nullable, and null is NOT the same as ''. Null means "keep whatever the
  /// shipped contract says about the baby's length"; '' means "this week has
  /// no length to show". An editor rewriting prose must be able to leave the
  /// numbers alone without asserting anything about them.
  lengthCm: z.string().trim().max(60).nullable().default(null),
  hcg: z.string().trim().max(120).nullable().default(null),
  ru: weekText,
  kk: weekText,
  /// Work in progress: saved, not served. This is what makes the clinician
  /// rule workable — half-written advice has somewhere to live.
  draft: z.boolean().default(false),
});

/// One language's half of one emergency-help scenario (frame 16b → screen 37).
///
/// `do` is the actionable half and the longest — «Звоните 103. Положите на бок,
/// уберите всё твёрдое рядом…» — so it gets the room. Nothing here is optional:
/// a scenario with a title and no instructions is a card that names a
/// catastrophe and says nothing about it.
const emergencyText = z.object({
  title: z.string().trim().max(160),
  what: z.string().trim().max(1200),
  do: z.string().trim().max(1200),
});

const emergencyHelpBody = z.object({
  /// The one field that is not prose. It decides the border colour and
  /// therefore whether the reader dials 103 or waits until morning, so it is
  /// constrained here, in the CHECK on the column, and inside the clinician's
  /// fingerprint.
  severity: z.enum(['red', 'amber']),
  /// Reading order. Editable because triage order is a clinical decision.
  sort: z.number().int().min(0).max(10_000),
  ru: emergencyText,
  kk: emergencyText,
  /// Work in progress: saved, not served — the reader keeps the shipped text.
  draft: z.boolean().default(false),
});

/// One language's half of one row of the immunisation calendar (frames 15/15a).
///
/// `note` is the line under the name — «Против пневмонии и отита…». Optional in
/// the schema and conditionally required in the route: a shipped vaccine
/// already has one in the app's l10n table under `vac_<id>_note`, so demanding
/// it here would make an editor retype text that is already correct, while an
/// ADDED vaccine has no l10n key at all and would render as a blank line.
const vaccineText = z.object({
  name: z.string().trim().min(0).max(160),
  note: z.string().trim().max(600).default(''),
});

const vaccinationBody = z.object({
  /// Completed months. 216 is eighteen years — past anything a childhood
  /// calendar covers, and the CHECK on the column agrees.
  atMonth: z.number().int().min(0).max(216),
  ru: vaccineText,
  kk: vaccineText,
  /// Only read when the key is NOT in the contract, i.e. frame 15a. On an
  /// existing row the dose is identity and cannot move — see the route.
  dose: z.number().int().min(1).max(9).nullable().default(null),
  /// Work in progress: saved, not served. Also the only way back — drafting an
  /// edit shows the contract through again, drafting an added vaccine retires it.
  draft: z.boolean().default(false),
});

/// The catch-up window, in months. 1..12 matches the column's CHECK.
// Frame 17c. A fraction, not a percentage: the app, the database and the
// public route all speak 0..1, and converting in three places is how 45
// becomes 0.45 in two of them and 45.0 in the third. The panel does the ×100
// for the human and sends the fraction back.
const cryThresholdBody = z.object({
  minConfidence: z.number().min(CRY_MIN_CONFIDENCE_MIN).max(CRY_MIN_CONFIDENCE_MAX),
});
const vaccinationSettingsBody = z.object({
  dueWindowMonths: z.number().int().min(1).max(12),
});

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

/**
 * Ways the back office reaches a customer's phone.
 *
 * Injected, not imported: notifications/push.ts calls
 * `admin.initializeApp(applicationDefault())` at module load, which throws on
 * every box without Google credentials — including every test run. Injecting
 * keeps this file loadable there and keeps the delivery decision in index.ts,
 * where the credentials are.
 *
 * Omitted means the channel is not configured. It MUST NOT mean the write
 * fails: an operator's reply is saved either way.
 */
export interface AdminNotifiers {
  /**
   * «Поддержка ответила» — frame 43. Must never throw; index.ts reports.
   */
  supportReply?: (
    userId: string,
    ticket: { id: string; subject: string },
    body: string,
  ) => Promise<void>;
  /**
   * A рассылка reaches the phones it was recorded against — frame 06.
   *
   * Takes the user ids the delivery ledger accepted, NOT the ones the segment
   * matched: the weekly gap is decided in the database, and a notifier that
   * re-derived the audience would be a second answer to «кому уходит», which
   * is exactly how somebody gets two messages in one afternoon.
   *
   * Both languages travel; index.ts picks per recipient from her own
   * `users.locale`. Omitted means no push channel on this box — the broadcast
   * is still published and still appears in her notification centre when the
   * app next syncs, which is why publishing does not depend on this.
   */
  broadcast?: (
    userIds: string[],
    message: {
      id: string;
      ru: { title: string; body: string };
      kk: { title: string; body: string };
    },
  ) => Promise<void>;
}

export function registerAdminRoutes(
  app: FastifyInstance,
  repo: Repository,
  authAdmin: AuthAdmin,
  runtime: AdminRuntimeFacts = {},
  notify: AdminNotifiers = {},
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
    pregnancy: pregnancyCalendar,
    childdev: childDevCalendar,
  } as const;

  app.get('/admin/reference/:kind', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const { kind } = req.params as { kind: string };
    // Not in the constant table: the immunisation calendar is now editable, and
    // this route has to answer with what a PHONE receives. Serving the raw
    // contract here would mean staff opening «Вакцинация» saw a schedule the
    // app does not use — which is the one thing a reference tab exists to
    // prevent. Frame 15.
    if (kind === 'vaccination') return reply.send(await servedVaccinationSchedule(repo));
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

  /**
   * ---- Where a mother's vitals are read ----
   *
   * `GET /admin/users/:id/health` used to live here: `health` capability, a
   * mandatory reason, one audit row, and a body of `{latest, triage}` from
   * `repo.adminUserHealth`. It was DELETED (docs/BACKLOG.md §3, 2026-08-17),
   * not because it was broken but because nothing called it and nothing could
   * honestly be made to:
   *
   *   - `/admin/users/:id/detail` below calls `adminUserHealth` internally and
   *     returns the same `latest` and the same `triage` inside the mother card
   *     the panel actually opens, so every byte it served is still served;
   *   - it carried the same guard, the same reason gate and the same audit, so
   *     removing it removed no protection and closed no access: anybody who
   *     could call it can call `/detail` and get a superset;
   *   - wiring it into the card would have meant a SECOND read of the same
   *     rows, with a second audit line and a second «зачем» prompt for data
   *     already on screen — the exact reasoning that put `epds` on /wellness
   *     rather than giving it a route of its own (see the note there).
   *
   * What was left was a live PHI endpoint whose only exercise was its own
   * tests. Those tests were not deleted with it: every one of them used it as
   * the canonical audited per-person read, so they now drive `/detail`, which
   * is guarded identically. `view_health` therefore has no writer any more —
   * `view_user_detail` and `view_wellness` are the health entries the security
   * page counts (src/admin/security.ts), and the panel keeps the label because
   * rows written before this deletion are still in the log.
   */

  // ---- Patient wellness (sleep / cycle / safety alerts) — audited ----
  app.get('/admin/users/:id/wellness', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const reason = readReason(req, reply);
    if (reason == null) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_wellness', target: userId, reason });
    // `epds` rides this route rather than getting its own: it is read in the
    // same breath as her diary, by the same person, under the same audit line
    // and the same «зачем» — a separate endpoint would mean a second reason
    // prompt for one number, which is how a reason prompt gets clicked through.
    const [sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses, vaccines, epds] = await Promise.all([
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
      repo.listEpds(userId, 10),
    ]);
    return reply.send({ sleep, days, alerts, weight, medications, medicalIds, kickSessions, contractionSessions, newbornEvents, bpCalibration, growth, doses, vaccines, epds });
  });

  /**
   * How many of her watch days the card shows.
   *
   * Two weeks: enough to answer «часы вообще передают данные?» and to see a
   * gap, short enough to stay one indexed read on a card that already makes a
   * dozen. The panel prints the window, so nobody reads an empty fortnight as
   * "she has never worn it".
   */
  const WEARABLE_DAY_WINDOW = 14;

  /**
   * ---- What the watch has actually been sending (migration 040) ----
   *
   * `Repository.listWearableDays` landed implemented in both repositories with
   * no caller at all — this repo's signature defect, an hour old. Steps,
   * distance, calories, stress, breathing rate, MET, wear state and the
   * watch's own battery reached the database and nothing could read them back.
   *
   * A route of its own rather than another field on /detail: it is a
   * per-person read with its own window and its own audit line, and folding it
   * into the card's payload would mean every open of a mother's record pulled
   * her activity history whether anybody looked at it or not.
   *
   * Guarded and reasoned exactly like /wellness, because that is what this is:
   * how much she moved, how she slept and how stressed the watch thinks she
   * was is special-category data about a named person, not fleet telemetry.
   */
  app.get('/admin/users/:id/wearable', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const reason = readReason(req, reply);
    if (reason == null) return;
    const userId = (req.params as { id: string }).id;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_wearable', target: userId, reason });
    const days = await repo.listWearableDays(userId, WEARABLE_DAY_WINDOW);
    // The window travels with the answer: «нет данных» over 14 days and «нет
    // данных никогда» are different sentences, and the panel can only tell
    // them apart if it knows what it asked for.
    return reply.send({ days, window: WEARABLE_DAY_WINDOW });
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

  // ---- Device fleet (frame 11) ----
  //
  // «На связи» has to be derived from a real timestamp against a stated
  // window, never from a flag somebody set once. Both numbers are sent to the
  // panel and printed under the metrics, so the reader can disagree with the
  // rule rather than with the figure.
  //
  // 24 hours, not the 15 minutes /admin/stats counts with: a watch reaches us
  // through her phone, and a phone that spent the night in another room is not
  // a broken device. Three days is where "nothing has come from this device"
  // stops being explainable by a weekend.
  const DEVICE_ONLINE_HOURS = 24;
  const DEVICE_STALE_DAYS = 3;

  app.get('/admin/devices', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const limit = clampLimit((req.query as { limit?: string }).limit, 100, 500);
    // The fleet view is not a list of hardware: every row carries the
    // guardian's display name and their child's name. Opening one user's
    // health record was audited while browsing every family's names in one
    // request was not — the same personal data, reached a different way.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_devices' });
    // The threshold «на связи» is derived from, sent WITH the rows so the
    // panel cannot quietly disagree with the server about what online means.
    // It is a real timestamp against a stated window — never a boolean
    // somebody set once.
    return reply.send({
      devices: await repo.adminDevices(limit),
      onlineWithinHours: DEVICE_ONLINE_HOURS,
      staleAfterDays: DEVICE_STALE_DAYS,
      limit,
    });
  });

  /**
   * Frame 11 · «Пометить браком», and taking the mark back.
   *
   * A support note on ONE mother's paired watch: somebody found it faulty.
   * Deliberately NOT `device_registry.status = 'blocked'`, which is the
   * warehouse action on the Склад screen — that stops a serial pairing with
   * any account, and doing both from one button would mean an operator
   * flagging a faulty unit silently cut a customer off.
   *
   * Addressed by our row id, not by the MAC: UNIQUE is (user_id, ble_mac), so
   * the same unit resold to a second family is two rows with one MAC and a
   * write keyed on it would mark a stranger's device.
   *
   * `health`, like the list it is drawn on: everyone who can open frame 11 can
   * use the button on it. A guard the screen's own readers fail would be a
   * control that is visible and refuses.
   */
  app.post('/admin/devices/:id/defect', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const id = (req.params as { id: string }).id;
    const body = (req.body ?? {}) as { defect?: unknown; note?: unknown };
    const defect = body.defect !== false; // absent = mark it
    const note = typeof body.note === 'string' ? body.note.trim().slice(0, 300) : '';
    const ok = await repo.markDeviceDefect(
      id,
      defect ? { at: new Date().toISOString(), by: s.staffId, note: note || null } : null,
    );
    // A write that matched no row is not a success. Reporting ok:true here is
    // exactly how a tick appears over a mark that was never saved.
    if (!ok) return reply.code(404).send({ error: 'unknown_device' });
    await repo.writeAudit({
      staffId: s.staffId,
      action: defect ? 'device_defect' : 'device_defect_clear',
      target: id,
      // The note IS the reason — «экран треснул», «не заряжается». Absent
      // rather than an invented «не указана», which makes an unreviewable log
      // look reviewed.
      reason: note || undefined,
    });
    return reply.send({ ok: true, defect });
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
   * How many protected reads one request will count over.
   *
   * A ceiling, not a window: the window itself is a SQL predicate now
   * (Repository.listProtectedAudit), and this only bounds how many matching
   * rows one request carries. Generous, because these rows are rare by
   * construction — every one is somebody opening a named woman's record — so a
   * busy year of them still fits.
   *
   * When it IS reached, the answer says so. The alternative is the bug it
   * replaced: a partial count printed as a total, on the one screen whose job
   * is to be believed by a regulator.
   *
   * Declared here rather than beside /admin/security because both readers of it
   * are below, and the first is /admin/owner.
   */
  const SECURITY_ROW_CAP = 20_000;

  /** The window the owner's «что горит» signal counts unexplained reads over. */
  const OWNER_ACCESS_WINDOW_DAYS = 30;

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
      // The unexplained-reads signal, over its own window and only over the
      // protected actions — the same query frame 22 makes, for the same reason.
      //
      // This was the newest 2 000 rows of the whole log, filtered here to 30
      // days. The log's ordinary traffic fills 2 000 rows in days, so the
      // owner's «что горит» card could show nothing at all while a month's
      // worth of unexplained reads sat just past the slice. A signal that only
      // fires when the count is above zero, fed a count that cannot rise, is a
      // reassuring blank.
      repo
        .listProtectedAudit(
          Object.keys(PROTECTED_ACTIONS),
          new Date(now.getTime() - OWNER_ACCESS_WINDOW_DAYS * 86_400_000).toISOString(),
          SECURITY_ROW_CAP,
        )
        .catch(() => ({ entries: [], hasMore: false })),
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
            accessWithoutReason: summarizeSecurity(
              audit.entries, now, OWNER_ACCESS_WINDOW_DAYS,
            ).withoutReason,
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
    // The window is asked of the DATABASE, not applied to whatever the newest
    // few thousand rows happened to be.
    //
    // This read the newest 5 000 rows of the whole log and filtered them here
    // against a window of up to 365 days. audit_log is dominated by ordinary
    // traffic — `list_users` and `view_support` on every open, the throttled
    // emergency feed from every open tab — so 5 000 rows is DAYS. Whoever
    // answered a regulator set the window to a year, read «Защищённых
    // просмотров: 12 · без причины: 0», and concluded that no health record had
    // been opened unexplained in twelve months, when the query had never looked
    // past last week. And `hasMore` came back from listAudit already, saying
    // exactly that, and was thrown away on this line.
    //
    // Filtered on both axes in SQL now (Repository.listProtectedAudit): only
    // the protected actions, only inside the window. Those rows are a small
    // minority of the table, so a year of them fits where a year of everything
    // does not — one index scan on (action, at DESC), migration 050.
    const since = new Date(Date.now() - days * 86_400_000).toISOString();
    const page = await repo
      .listProtectedAudit(Object.keys(PROTECTED_ACTIONS), since, SECURITY_ROW_CAP)
      .catch(() => ({ entries: [], hasMore: false }));
    const audit = page.entries;
    // This page lists patients by name — «кто открывал карту Айгерім и почему»
    // — so reading it is itself a read of special-category data and is
    // recorded. Unlike GET /admin/audit, which returns the raw log and is
    // exempt because auditing it makes the log describe mostly itself, this
    // one is opened rarely and deliberately: the row is worth having.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_security' });
    return reply.send({
      ...summarizeSecurity(audit, new Date(), days),
      // Even a filtered query has a ceiling, and a count that stopped at it is
      // not a count. The page SAYS so rather than printing the partial total as
      // if it were the whole one: a number that under-reports silently is worse
      // than one labelled incomplete, and this is the number that exists to be
      // over- rather than under-reported.
      truncated: page.hasMore,
      rowCap: SECURITY_ROW_CAP,
      // The retention promises this page reports on, from the one place each
      // is defined — so the screen cannot drift from what actually runs.
      //
      // The audit period has been round this loop twice. It began as a bare
      // literal 3 directly beneath this comment, with nothing anywhere
      // deleting an audit_log row: the screen whose entire job is
      // accountability told a reviewer the record is kept three years when it
      // was kept for ever, and the fiction was credible precisely because it
      // sat beside the real 90-day route sweep. b8aac0c took the number away
      // and printed «срок не задан» instead, which was honest and useless.
      //
      // The owner has now set it, and privacy/retention.ts sweeps audit_log on
      // that period. So the number is back — and now so are the other six.
      // This object was a hand-kept pair of fields while EIGHT sweeps ran, so
      // the page that answers «what is kept, and for how long» under-reported
      // by six and looked complete doing it. `retentionSummary()` derives all
      // of it from RETENTION_SWEEPS and RETENTION_KEPT: a ninth sweep reaches
      // this screen without a line changing here.
      retention: retentionSummary(),
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
   *
   * IT SENDS THE TEXT, because the signature covers the text.
   * `textFingerprint` quotes the title, the summary, the link, the video, the
   * whole article and the red-flag block; a queue that sent only the title
   * asked a clinician to put their name in the audit log against paragraphs
   * they had not been shown. They cannot go and read them elsewhere either —
   * the guides editor is `content` and this role holds `health`, so this screen
   * is the ONLY place the text can reach them. Sending everything the
   * fingerprint quotes is what keeps «Подтвердить» from being a rubber stamp.
   */
  app.get('/admin/content/review-queue', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const catalog = await repo.contentCatalog().catch(() => ({}));
    const waiting: Array<{
      stage: string; id: string; title: string; reason: string; draft: boolean;
      summary: Record<string, string>;
      body: Record<string, string>;
      redFlags: Record<string, string>;
      url: string;
      video: string;
    }> = [];
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
          // Every locale, not just Russian: a clinician signs the Kazakh
          // paragraphs too, and they are what a Kazakh mother reads.
          summary: item.summary ?? {},
          body: item.body ?? {},
          redFlags: item.redFlags ?? {},
          url: item.url ?? '',
          // Flattened to the one string the fingerprint uses, so what is shown
          // and what is signed cannot describe different things.
          video: item.video ? `${item.video.provider}: ${item.video.url}` : '',
        });
      }
    }
    waiting.sort((a, b) => (a.reason === b.reason ? 0 : a.reason === 'stale' ? -1 : 1));
    return reply.send({ waiting });
  });

  // ---- Pregnancy calendar (frames 14a «40 недель» / 14b «Редактор недели») --
  //
  // The forty weeks of pregnancy content are the only thing this product shows
  // to EVERY pregnant user, and until this route existed they were a JSON file
  // compiled into the server and bundled into the app. Fixing a wrong hCG range
  // in week 22 meant a backend release and a store rollout.
  //
  // What is served stays contract-plus-overrides — see pregnancy/overrides.ts.
  // The contract is never touched, so the app keeps working with no signal and
  // app/tool/verify_pregnancy_weeks_contract.dart keeps passing.

  /**
   * The editor's view: every week, merged, with its edit state and how many
   * mothers are standing in it today.
   *
   * `mothers` is the number that turns «поправить неделю 22» into a decision.
   * It is counted off `users.due_date` and nothing else — if nobody is in week
   * 22 it says 0, out loud, rather than borrowing a plausible figure from
   * somewhere. `mothersTotal` is stated beside it so a row of zeroes reads as
   * "no pregnant users yet" rather than "the count is broken".
   *
   * Staff-read rather than `content`-gated: a clinician holding `health` has to
   * be able to READ what she is being asked to approve.
   */
  app.get('/admin/pregnancy/weeks', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const [overrides, mothers] = await Promise.all([
      // Nor is the edit state. Frame 14a is a READ of forty weeks of medical
      // content, and it read fine before this table existed — 500ing the whole
      // tab because migration 036 has not run yet, or because the database
      // blinked, takes the calendar away over the one part of it that is a
      // patch. So: the contract, plus `editsKnown: false` so the panel can say
      // out loud that it does not know which weeks were edited (and refuse to
      // let anyone save over an edit it cannot see) instead of drawing forty
      // untouched weeks that would read as "nobody has ever edited this".
      repo.pregnancyWeekOverrides().catch(() => null),
      // A count is not worth failing the screen for. If it cannot be had, the
      // panel is told so (`mothersKnown: false`) and shows no numbers at all,
      // rather than a column of zeroes that reads as "nobody is pregnant".
      repo.pregnancyWeekMotherCounts().catch(() => null),
    ]);
    const byWeek = new Map((overrides ?? []).map((o) => [o.week, o]));
    const served = await servedCalendar(repo);

    return reply.send({
      version: served.version,
      contractVersion: pregnancyCalendar.version,
      editsKnown: overrides != null,
      mothersKnown: mothers != null,
      mothersTotal: mothers ? Object.values(mothers).reduce((t, n) => t + n, 0) : null,
      weeks: pregnancyCalendar.weeks.map((base) => {
        const o = byWeek.get(base.week);
        // The EDITOR sees the draft; a reader does not. Opening a week you
        // saved as a draft and finding the shipped text back in the boxes is
        // how an afternoon's work gets retyped.
        const shown = o ?? base;
        // `base` is passed so the fingerprint is taken over the numbers this
        // row actually serves — the same merged values sent down as `lengthCm`
        // and `hcg` below, and the same ones the panel posts back.
        const item = o
          ? weekAsReviewable(base.week, { lengthCm: o.lengthCm, hcg: o.hcg, ru: o.ru, kk: o.kk, draft: o.draft }, base)
          : null;
        return {
          week: base.week,
          lengthCm: o ? o.lengthCm ?? base.lengthCm : base.lengthCm,
          hcg: o ? o.hcg ?? base.hcg : base.hcg,
          ru: shown.ru,
          kk: shown.kk,
          /// Somebody has edited this week; without it the panel cannot tell
          /// "same as shipped" from "edited back to the same words".
          edited: o != null,
          draft: o?.draft === true,
          /// What a phone gets right now is this row's text, not the contract's.
          live: o != null && !o.draft,
          review: o?.review ? { by: o.review.by, at: o.review.at } : null,
          /// Does that signature still describe the text above it?
          reviewCurrent: o?.review != null && item != null
            && o.review.fingerprint === textFingerprint(item),
          updatedAt: o?.updatedAt ?? null,
          updatedBy: o?.updatedBy ?? null,
          mothers: mothers ? mothers[base.week] ?? 0 : null,
        };
      }),
    });
  });

  /**
   * Save one week.
   *
   * The same two rules as `PUT /admin/content/:stage`, for the same reasons and
   * in the same words:
   *
   *  - no Kazakh, no publication. The app falls back to Russian silently, so a
   *    half-translated week reads to a Kazakh mother as the app ignoring the
   *    language she chose.
   *  - medical text is checked by a clinician, and EDITING approved text takes
   *    the approval away. Every week of this calendar is medical — it tells a
   *    pregnant woman what is happening to her and when to worry — so there is
   *    no unmarked half of it to slip through.
   *
   * A draft is exempt from the second rule and not from the first: a draft is
   * how a week gets written at all, but a translation that is never started is
   * a translation that never happens.
   */
  app.put('/admin/pregnancy/weeks/:week', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const week = Number((req.params as { week: string }).week);
    // Only weeks the shipped calendar covers. A row for week 55 would be stored
    // faithfully and merged into nothing — an edit that vanishes silently.
    const baseWeek = pregnancyCalendar.weeks.find((w) => w.week === week);
    if (!baseWeek) {
      return reply.code(400).send({
        error: 'unknown_week',
        message: `Недели ${(req.params as { week: string }).week} нет в календаре ` +
          `(есть ${pregnancyCalendar.weeks[0]?.week}–${pregnancyCalendar.weeks.at(-1)?.week}).`,
      });
    }
    const parsed = pregnancyWeekBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const v = parsed.data;

    const problems: BilingualProblem[] = [];
    for (const field of ['baby', 'you', 'recommend'] as const) {
      const missing = missingLocales({ ru: v.ru[field], kk: v.kk[field] });
      if (missing.length) problems.push({ id: `неделя ${week}`, field, missing });
    }
    if (problems.length) {
      return reply.code(400).send({
        error: 'translation_required',
        week,
        problems,
        message: bilingualMessage(problems),
      });
    }

    // NOT `.catch(() => [])`. A failed read is not "no row yet": carryReview
    // would see no prior signature, store `review: null`, and a clinician's
    // sign-off would be destroyed by a save that reported success — with the
    // panel then showing «Врач ещё не проверял» on a week approved a minute
    // ago and no record that the approval was ever there. Drafts are exempt
    // from the review gate, so nothing else would have stopped the write.
    let stored: PregnancyWeekOverride[];
    try {
      stored = await repo.pregnancyWeekOverrides();
    } catch {
      return reply.code(503).send({
        error: 'overrides_unavailable',
        week,
        message: 'Не удалось прочитать сохранённые недели, поэтому сохранение отменено — ' +
          'иначе проверка врача по этой неделе была бы потеряна. Повторите через минуту.',
      });
    }
    const previous = stored.find((o) => o.week === week);
    // Both sides fingerprinted against the contract's numbers, so a cleared box
    // and the contract's own value are the same claim — see [weekAsReviewable].
    const incoming = weekAsReviewable(week, v, baseWeek);
    const prior: ReviewableItem | undefined = previous?.review
      ? { ...weekAsReviewable(week, previous, baseWeek), review: previous.review }
      : undefined;

    const needReview = unreviewed([incoming], new Map(prior ? [[incoming.id, prior]] : []));
    if (needReview.length) {
      return reply.code(409).send({
        error: 'review_required',
        week,
        problems: needReview,
        message: reviewMessage(needReview) +
          '. Отправьте на проверку врачу или сохраните как черновик.',
      });
    }

    // What gets STORED is the review already in the database, never one from
    // the request body — that would be self-approval by PUT.
    const carried = carryReview(incoming, prior);
    await repo.putPregnancyWeekOverride({
      week,
      lengthCm: v.lengthCm,
      hcg: v.hcg,
      ru: v.ru,
      kk: v.kk,
      draft: v.draft,
      review: carried.review ?? null,
      updatedBy: s.staffId,
    });
    await repo.writeAudit({
      staffId: s.staffId,
      action: v.draft ? 'edit_pregnancy_week_draft' : 'edit_pregnancy_week',
      target: `week-${week}`,
    });
    return reply.send({ ok: true, week, draft: v.draft, reviewed: carried.review != null });
  });

  /**
   * A clinician signs off one week.
   *
   * `health`, not `content` — that separation IS the two-person rule: authoring
   * needs `content`, approving needs `health`, and no role but an owner holds
   * both. The signature records what was read, so a later edit invalidates it
   * without anybody having to remember to.
   *
   * Only an EDITED week can be reviewed. The shipped contract came through the
   * MoH calendar and its own release; asking a clinician to re-approve forty
   * weeks nobody has touched would turn the queue into noise.
   */
  app.post('/admin/pregnancy/weeks/:week/review', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const week = Number((req.params as { week: string }).week);
    const current = (await repo.pregnancyWeekOverrides()).find((o) => o.week === week);
    if (!current) {
      return reply.code(404).send({
        error: 'not_edited',
        message: 'Эта неделя не редактировалась — проверять нечего.',
      });
    }
    const review = {
      by: s.staffId,
      at: new Date().toISOString(),
      // Against the contract's numbers, so what is signed is what is served —
      // and so the editor's next publish can reproduce it.
      fingerprint: textFingerprint(
        weekAsReviewable(week, current, pregnancyCalendar.weeks.find((w) => w.week === week)),
      ),
    };
    await repo.putPregnancyWeekOverride({
      week,
      lengthCm: current.lengthCm,
      hcg: current.hcg,
      ru: current.ru,
      kk: current.kk,
      // Approving does NOT publish. Two decisions, two people, two moments —
      // the clinician says the text is safe, the editor says it is finished.
      draft: current.draft,
      review,
      updatedBy: current.updatedBy ?? s.staffId,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'pregnancy_week_review', target: `week-${week}` });
    return reply.send({ ok: true, week, review, draft: current.draft });
  });

  // ---- Emergency help (frame 16b «Экстренная помощь» → app screen 37) -----
  //
  // Nine scenarios that tell a frightened person at 3am whether to dial 103 now
  // or call the clinic in the morning, and until these routes existed they were
  // a JSON file compiled into the server and bundled into the app. Correcting
  // «держите ожог под водой 20 минут» to whatever the protocol actually says
  // was a backend release AND a store rollout.
  //
  // What is served stays contract-plus-overrides — see emergency/overrides.ts.
  // The contract is never touched, so the app keeps working with no signal and
  // app/tool/verify_emergency_help_contract.dart keeps passing.

  /**
   * The editor's view: every scenario, merged, with its edit state.
   *
   * Staff-read rather than `content`-gated, for the same reason as the
   * pregnancy calendar: a clinician holding `health` has to be able to READ
   * what she is being asked to approve.
   *
   * There is deliberately no head-count beside a scenario. The pregnancy editor
   * can say «это увидят N мам» because `users.due_date` answers it; nothing in
   * this product records who opened screen 37, and a number here would be
   * invented.
   */
  app.get('/admin/emergency-help', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    // Frame 16b is a READ of nine pieces of first aid, and it read fine before
    // this table existed — 500ing the whole tab because migration 043 has not
    // run yet takes the list away over the one part of it that is a patch. So:
    // the contract, plus `editsKnown: false` so the panel can say out loud that
    // it does not know which scenarios were edited (and refuse to let anyone
    // save over an edit it cannot see).
    const overrides = await repo.emergencyHelpOverrides().catch(() => null);
    const byId = new Map((overrides ?? []).map((o) => [o.id, o]));
    const served = await servedEmergencyHelp(repo);

    return reply.send({
      version: served.version,
      contractVersion: emergencyHelp.version,
      tel: emergencyHelp.tel,
      editsKnown: overrides != null,
      scenarios: emergencyHelp.scenarios.map((base) => {
        const o = byId.get(base.id);
        // The EDITOR sees the draft; a reader does not. Opening a scenario you
        // saved as a draft and finding the shipped text back in the boxes is
        // how an afternoon's work gets retyped.
        const shown = o ?? base;
        const item = o
          ? scenarioAsReviewable(base.id, { severity: o.severity, ru: o.ru, kk: o.kk, draft: o.draft })
          : null;
        return {
          id: base.id,
          severity: shown.severity,
          sort: shown.sort,
          ru: shown.ru,
          kk: shown.kk,
          /// Somebody has edited this scenario; without it the panel cannot
          /// tell "same as shipped" from "edited back to the same words".
          edited: o != null,
          draft: o?.draft === true,
          /// What a phone gets right now is this row's text, not the contract's.
          live: o != null && !o.draft,
          review: o?.review ? { by: o.review.by, at: o.review.at } : null,
          /// Does that signature still describe the text above it?
          reviewCurrent: o?.review != null && item != null
            && o.review.fingerprint === textFingerprint(item),
          updatedAt: o?.updatedAt ?? null,
          updatedBy: o?.updatedBy ?? null,
        };
      }).sort((a, b) => (a.sort - b.sort) || a.id.localeCompare(b.id)),
    });
  });

  /**
   * Save one scenario.
   *
   * The same two rules as the pregnancy week editor, for the same reasons and
   * in the same words:
   *
   *  - no Kazakh, no publication. The app falls back to Russian silently, so a
   *    half-translated scenario reads to a Kazakh mother as the app ignoring
   *    the language she chose — while she is deciding whether to call an
   *    ambulance.
   *  - medical text is checked by a clinician, and EDITING approved text takes
   *    the approval away. Every scenario here is an instruction about a
   *    bleeding or unbreathing person; there is no unmarked half to slip
   *    through.
   */
  app.put('/admin/emergency-help/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const id = (req.params as { id: string }).id;
    // Only scenarios the shipped contract covers. A row for an invented id
    // would be stored faithfully and merged into nothing — an edit that
    // vanishes silently. Adding a scenario is a contract change.
    if (!contractScenario(id)) {
      return reply.code(400).send({
        error: 'unknown_scenario',
        message: `Сценария «${id}» нет в справочнике ` +
          `(есть ${emergencyHelp.scenarios.map((x) => x.id).join(', ')}).`,
      });
    }
    const parsed = emergencyHelpBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const v = parsed.data;

    const problems: BilingualProblem[] = [];
    for (const field of ['title', 'what', 'do'] as const) {
      const missing = missingLocales({ ru: v.ru[field], kk: v.kk[field] });
      if (missing.length) problems.push({ id: `сценарий «${id}»`, field, missing });
    }
    if (problems.length) {
      return reply.code(400).send({
        error: 'translation_required',
        id,
        problems,
        message: bilingualMessage(problems),
      });
    }

    // NOT `.catch(() => [])`. A failed read is not "no row yet": carryReview
    // would see no prior signature, store `review: null`, and a clinician's
    // sign-off would be destroyed by a save that reported success. Drafts are
    // exempt from the review gate, so nothing else would have stopped the
    // write.
    let stored: EmergencyHelpOverride[];
    try {
      stored = await repo.emergencyHelpOverrides();
    } catch {
      return reply.code(503).send({
        error: 'overrides_unavailable',
        id,
        message: 'Не удалось прочитать сохранённые сценарии, поэтому сохранение отменено — ' +
          'иначе проверка врача по этому сценарию была бы потеряна. Повторите через минуту.',
      });
    }
    const previous = stored.find((o) => o.id === id);
    const incoming = scenarioAsReviewable(id, v);
    const prior: ReviewableItem | undefined = previous?.review
      ? { ...scenarioAsReviewable(id, previous), review: previous.review }
      : undefined;

    const needReview = unreviewed([incoming], new Map(prior ? [[incoming.id, prior]] : []));
    if (needReview.length) {
      return reply.code(409).send({
        error: 'review_required',
        id,
        problems: needReview,
        message: reviewMessage(needReview) +
          '. Отправьте на проверку врачу или сохраните как черновик.',
      });
    }

    // What gets STORED is the review already in the database, never one from
    // the request body — that would be self-approval by PUT.
    const carried = carryReview(incoming, prior);
    await repo.putEmergencyHelpOverride({
      id,
      severity: v.severity,
      sort: v.sort,
      ru: v.ru,
      kk: v.kk,
      draft: v.draft,
      review: carried.review ?? null,
      updatedBy: s.staffId,
    });
    await repo.writeAudit({
      staffId: s.staffId,
      action: v.draft ? 'edit_emergency_help_draft' : 'edit_emergency_help',
      target: `emergency-${id}`,
    });
    return reply.send({ ok: true, id, draft: v.draft, reviewed: carried.review != null });
  });

  /**
   * A clinician signs off one scenario.
   *
   * `health`, not `content` — that separation IS the two-person rule: authoring
   * needs `content`, approving needs `health`, and no role but an owner holds
   * both. The signature records what was read, so a later edit — including
   * downgrading red to amber — invalidates it without anybody having to
   * remember to.
   *
   * Only an EDITED scenario can be reviewed. The shipped contract came through
   * its own release; asking a clinician to re-approve nine untouched scenarios
   * would turn the queue into noise.
   */
  app.post('/admin/emergency-help/:id/review', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const id = (req.params as { id: string }).id;
    const current = (await repo.emergencyHelpOverrides()).find((o) => o.id === id);
    if (!current) {
      return reply.code(404).send({
        error: 'not_edited',
        message: 'Этот сценарий не редактировался — проверять нечего.',
      });
    }
    const review = {
      by: s.staffId,
      at: new Date().toISOString(),
      fingerprint: textFingerprint(scenarioAsReviewable(id, current)),
    };
    await repo.putEmergencyHelpOverride({
      id,
      severity: current.severity,
      sort: current.sort,
      ru: current.ru,
      kk: current.kk,
      // Approving does NOT publish. Two decisions, two people, two moments —
      // the clinician says the text is safe, the editor says it is finished.
      draft: current.draft,
      review,
      updatedBy: current.updatedBy ?? s.staffId,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'emergency_help_review', target: `emergency-${id}` });
    return reply.send({ ok: true, id, review, draft: current.draft });
  });

  // ---- Immunisation calendar (frames 15 / 15a / 15b) ----------------------
  //
  // Sixteen entries that decide what every parent in this app is told to do and
  // when, and until these routes existed they were a JSON file compiled into
  // the server and mirrored in Dart. When the ministry moved the second
  // pneumococcal dose, changing it was a backend release AND a store rollout.
  //
  // What is served stays contract-plus-overrides — see vaccination/overrides.ts.
  // The contract is never touched, so the app keeps working with no signal and
  // app/tool/verify_vaccination_contract.dart keeps passing.

  /** The contract entry behind a key, if the shipped calendar has one. */
  const contractVaccine = (key: string) =>
    vaccinationSchedule.vaccines.find((v) => contractKey(v) === key) ?? null;

  /** `bcg/null` from the two path segments the panel sends. */
  const keyFromParams = (p: { id: string; dose: string }) => {
    const dose = p.dose === 'null' || p.dose === '' ? null : Number(p.dose);
    if (dose != null && !Number.isInteger(dose)) return null;
    return { key: vaccineKeyOf(p.id, dose), id: p.id, dose };
  };

  /**
   * The editor's view: every injection the calendar knows about, merged, with
   * its edit state.
   *
   * Rows come from the contract AND from the override table, because the two
   * sets are not the same: a vaccine added in frame 15a exists only in the
   * table, and one that has been retired (drafted) has to stay visible to the
   * person who might want it back. A list built from the served schedule alone
   * would make retiring a vaccine the one edit that cannot be undone.
   *
   * Staff-read rather than `content`-gated: a clinician holding `health` has to
   * be able to READ what she is being asked to approve.
   */
  app.get('/admin/vaccination/schedule', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    // Nor is the edit state. Frame 15 is a READ of the national calendar and it
    // read fine before this table existed — 500ing the whole tab because
    // migration 038 has not run yet takes the calendar away over the one part
    // of it that is a patch. So: the contract, plus `editsKnown: false` so the
    // panel can say out loud that it does not know what has been edited (and
    // refuse to let anyone save over an edit it cannot see).
    const [overrides, settings] = await Promise.all([
      repo.vaccinationOverrides().catch(() => null),
      repo.vaccinationSettings().catch(() => undefined),
    ]);
    const served = await servedVaccinationSchedule(repo);
    const byKey = new Map((overrides ?? []).map((o) => [o.key, o]));

    const row = (key: string, o: VaccinationOverride | undefined, base: ReturnType<typeof contractVaccine>) => {
      // The EDITOR sees the draft; a reader does not. Opening a vaccine you
      // saved as a draft and finding the shipped label back in the box is how
      // an afternoon's work gets retyped.
      const shown = o
        ? { atMonth: o.atMonth, dose: o.dose, ru: o.ru, kk: o.kk, draft: o.draft }
        : {
          atMonth: base!.atMonth,
          dose: base!.dose ?? null,
          // The contract carries a Russian label and nothing else — no Kazakh,
          // no note. Those live in the app's l10n table, which this server
          // cannot read, so the boxes start empty rather than pre-filled with a
          // guess. That is also why the FIRST edit of a shipped vaccine is
          // where the bilingual rule bites: it is the first time anybody has
          // been asked to write the Kazakh down here.
          ru: { name: base!.ru, note: '' },
          kk: { name: '', note: '' },
          draft: false,
        };
      const item = o ? vaccineAsReviewable(key, o, base) : null;
      const live = served.vaccines.find((v) => v.key === key) ?? null;
      return {
        key,
        id: o?.id ?? base!.id,
        dose: shown.dose,
        atMonth: shown.atMonth,
        /// What the shipped calendar says, so the panel can show «было / стало»
        /// and offer «вернуть к шипованному графику» only where there is one.
        contractAtMonth: base ? base.atMonth : null,
        contractRu: base ? base.ru : null,
        inContract: base != null,
        added: o?.added === true,
        ru: shown.ru,
        kk: shown.kk,
        /// Somebody has edited this; without it the panel cannot tell "same as
        /// shipped" from "edited back to the same words".
        edited: o != null,
        draft: o?.draft === true,
        /// Is this row on a phone right now?
        live: live != null,
        /// ...and at what age, which is not the same as `atMonth` when this row
        /// is a draft: the reader still gets the contract's month.
        liveAtMonth: live ? live.atMonth : null,
        review: o?.review ? { by: o.review.by, at: o.review.at } : null,
        reviewCurrent: o?.review != null && item != null
          && o.review.fingerprint === textFingerprint(item),
        updatedAt: o?.updatedAt ?? null,
        updatedBy: o?.updatedBy ?? null,
      };
    };

    const rows = vaccinationSchedule.vaccines.map((v) => {
      const key = contractKey(v);
      return row(key, byKey.get(key), v);
    });
    for (const o of overrides ?? []) {
      if (contractVaccine(o.key)) continue;
      rows.push(row(o.key, o, null));
    }
    rows.sort((a, b) => a.atMonth - b.atMonth || a.key.localeCompare(b.key));

    return reply.send({
      version: served.version,
      contractVersion: vaccinationSchedule.version,
      editsKnown: overrides != null,
      /// `undefined` from the catch above means the read FAILED; `null` means
      /// there is no row, which is a decision nobody has taken rather than a
      /// failure. The panel prints those two differently.
      settingsKnown: settings !== undefined,
      dueWindowMonths: served.dueWindowMonths,
      contractDueWindowMonths: vaccinationSchedule.dueWindowMonths,
      dueWindowEdited: settings != null,
      dueWindowUpdatedAt: settings?.updatedAt ?? null,
      dueWindowUpdatedBy: settings?.updatedBy ?? null,
      vaccines: rows,
    });
  });

  /**
   * Save one injection.
   *
   * The same two rules as the pregnancy week editor, for the same reasons and
   * in the same words: no Kazakh, no publication; and editing approved medical
   * text takes the approval away. Every row here tells a parent to take a child
   * for an injection on a date, so there is no unmarked half to slip through.
   *
   * A draft is exempt from the second rule and not from the first.
   *
   * `dose` is IDENTITY and cannot move on an existing row. A mother's tick is
   * filed under `<id>/<dose>` (`child_vaccines.vaccine_key`), so renumbering a
   * dose would orphan every tick already recorded against it and quietly reset
   * the coverage figure for that injection to zero. The route says so instead
   * of doing it.
   */
  app.put('/admin/vaccination/schedule/:id/:dose', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const p = keyFromParams(req.params as { id: string; dose: string });
    if (!p) return reply.code(400).send({ error: 'bad_key', message: 'Доза должна быть числом или null.' });
    if (!/^[a-z][a-z0-9_]{1,31}$/.test(p.id)) {
      return reply.code(400).send({
        error: 'bad_id',
        message: 'Код прививки — латиница, цифры и подчёркивание, 2–32 символа (например pcv).',
      });
    }
    const parsed = vaccinationBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const v = parsed.data;
    const base = contractVaccine(p.key);

    let stored: VaccinationOverride[];
    // NOT `.catch(() => [])`. A failed read is not "no row yet": carryReview
    // would see no prior signature, store `review: null`, and a clinician's
    // sign-off would be destroyed by a save that reported success. Drafts are
    // exempt from the review gate, so nothing else would have stopped the write.
    try {
      stored = await repo.vaccinationOverrides();
    } catch {
      return reply.code(503).send({
        error: 'overrides_unavailable',
        key: p.key,
        message: 'Не удалось прочитать сохранённые прививки, поэтому сохранение отменено — ' +
          'иначе проверка врача по этой прививке была бы потеряна. Повторите через минуту.',
      });
    }
    const previous = stored.find((o) => o.key === p.key);

    // A key that is neither in the contract nor already stored is a NEW vaccine
    // (frame 15a); the dose in the body has to agree with the one in the path,
    // or the row would be filed under a key nobody can reach.
    if (!base && !previous && v.dose !== p.dose) {
      return reply.code(400).send({
        error: 'dose_mismatch',
        message: `Доза в адресе (${p.dose ?? 'нет'}) и в форме (${v.dose ?? 'нет'}) не совпадают.`,
      });
    }
    if (previous && v.dose !== previous.dose) {
      return reply.code(409).send({
        error: 'dose_is_identity',
        message: 'Номер дозы менять нельзя: под ключом «' + p.key + '» уже сохранены отметки мам ' +
          'о сделанных прививках. Добавьте прививку с новой дозой и уберите старую в черновик.',
      });
    }

    const problems: BilingualProblem[] = [];
    const label = base ? base.ru : (previous?.ru.name || p.key);
    const nameMissing = missingLocales({ ru: v.ru.name, kk: v.kk.name });
    if (nameMissing.length) problems.push({ id: label, field: 'name', missing: nameMissing });
    // The note is required for an ADDED vaccine — nothing in the app's l10n
    // table can fill it, so the row would render with a blank second line — and
    // whenever one language's note has been written, because half a translation
    // is exactly what the bilingual rule exists to stop.
    const added = previous ? previous.added : !base;
    if (added || v.ru.note || v.kk.note) {
      const noteMissing = missingLocales({ ru: v.ru.note, kk: v.kk.note });
      if (noteMissing.length) problems.push({ id: label, field: 'note', missing: noteMissing });
    }
    if (problems.length) {
      return reply.code(400).send({
        error: 'translation_required',
        key: p.key,
        problems,
        message: bilingualMessage(problems),
      });
    }

    const incoming = vaccineAsReviewable(p.key, { ...v, dose: p.dose }, base);
    const prior: ReviewableItem | undefined = previous?.review
      ? { ...vaccineAsReviewable(p.key, previous, base), review: previous.review }
      : undefined;
    const needReview = unreviewed([incoming], new Map(prior ? [[incoming.id, prior]] : []));
    if (needReview.length) {
      return reply.code(409).send({
        error: 'review_required',
        key: p.key,
        problems: needReview,
        message: reviewMessage(needReview) +
          '. Отправьте на проверку врачу или сохраните как черновик.',
      });
    }

    // What gets STORED is the review already in the database, never one from
    // the request body — that would be self-approval by PUT.
    const carried = carryReview(incoming, prior);
    await repo.putVaccinationOverride({
      key: p.key,
      id: p.id,
      dose: p.dose,
      atMonth: v.atMonth,
      ru: v.ru,
      kk: v.kk,
      added,
      draft: v.draft,
      review: carried.review ?? null,
      updatedBy: s.staffId,
    });
    await repo.writeAudit({
      staffId: s.staffId,
      action: v.draft ? 'edit_vaccine_draft' : 'edit_vaccine',
      target: p.key,
    });
    return reply.send({
      ok: true, key: p.key, draft: v.draft, added,
      reviewed: carried.review != null,
    });
  });

  /**
   * A clinician signs off one injection.
   *
   * `health`, not `content` — that separation IS the two-person rule. The
   * signature covers the age as well as the words (see [vaccineAsReviewable]),
   * so moving a dose after approval invalidates it without anybody having to
   * remember to.
   *
   * Only an EDITED vaccine can be reviewed. The shipped calendar came through
   * the ministry's own order and this product's release; asking a clinician to
   * re-approve sixteen untouched rows would turn the queue into noise.
   */
  app.post('/admin/vaccination/schedule/:id/:dose/review', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const p = keyFromParams(req.params as { id: string; dose: string });
    if (!p) return reply.code(400).send({ error: 'bad_key' });
    const current = (await repo.vaccinationOverrides()).find((o) => o.key === p.key);
    if (!current) {
      return reply.code(404).send({
        error: 'not_edited',
        message: 'Эта прививка не редактировалась — проверять нечего.',
      });
    }
    const review = {
      by: s.staffId,
      at: new Date().toISOString(),
      fingerprint: textFingerprint(vaccineAsReviewable(p.key, current, contractVaccine(p.key))),
    };
    await repo.putVaccinationOverride({
      key: p.key,
      id: current.id,
      dose: current.dose,
      atMonth: current.atMonth,
      ru: current.ru,
      kk: current.kk,
      added: current.added,
      // Approving does NOT publish. Two decisions, two people, two moments.
      draft: current.draft,
      review,
      updatedBy: current.updatedBy ?? s.staffId,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'vaccine_review', target: p.key });
    return reply.send({ ok: true, key: p.key, review, draft: current.draft });
  });

  /**
   * «Настройки напоминаний», as much of them as this product can honestly offer.
   *
   * There is NO server-side vaccination sender. Nothing in this backend pushes
   * a «пора прививаться» notification — the reminder a parent gets is scheduled
   * on her own phone by the app — so a toggle here for switching one on would
   * be a control wired to nothing, which is this repository's favourite defect.
   *
   * What genuinely reaches every phone is the catch-up window: how long a
   * vaccine reads as «пора» before it reads as «стоит наверстать». It used to
   * be a Dart constant. It is now this row, the app fetches it, and the panel
   * says out loud that it is the only reminder setting there is.
   */
  app.put('/admin/vaccination/settings', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const parsed = vaccinationSettingsBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.putVaccinationSettings({
      dueWindowMonths: parsed.data.dueWindowMonths,
      updatedBy: s.staffId,
    });
    await repo.writeAudit({
      staffId: s.staffId,
      action: 'edit_vaccination_settings',
      target: `dueWindowMonths=${parsed.data.dueWindowMonths}`,
    });
    return reply.send({ ok: true, dueWindowMonths: parsed.data.dueWindowMonths });
  });

  /**
   * Frame 15's coverage column.
   *
   * READ THE HEADER OF vaccination/coverage.ts BEFORE QUOTING ANY OF THIS. Every
   * figure is **self-reported by mothers in the app** — a row in
   * `child_vaccines` exists because a parent tapped a circle. Nothing in this
   * product reads a polyclinic record. It is «охват по отметкам мам», never
   * «охват по РК», and the payload says so in a field the panel prints rather
   * than leaving it to whoever writes the HTML.
   */
  app.get('/admin/vaccination/coverage', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const schedule = await servedVaccinationSchedule(repo);
    let data;
    try {
      data = await repo.vaccinationCoverage();
    } catch {
      // A count is not worth failing the screen for, and a screen full of
      // zeroes would read as «никто не прививается».
      return reply.code(503).send({
        error: 'coverage_unavailable',
        message: 'Не удалось посчитать охват — данные о детях сейчас недоступны. ' +
          'График прививок ниже верен, цифры охвата не показаны.',
      });
    }
    const report = vaccinationCoverageOf(schedule, data);
    return reply.send({
      ...report,
      version: schedule.version,
      source: 'self_reported',
      sourceNote: 'Отметки мам в приложении, а не данные поликлиник. ' +
        'Это доля родителей — пользователей приложения, которые отметили прививку сделанной.',
      rule: `В знаменателе — дети, у которых возраст прививки и догоняющее окно (${report.dueWindowMonths} мес.) уже прошли; ` +
        'дети, у которых прививка ещё «пора», не считаются ни в одну сторону.',
      /// The sentence under frame 15's «провал» callout, written HERE so the
      /// browser prints a claim this server stands behind rather than one
      /// whoever edits the HTML invents. Two things it has to say out loud:
      /// what «самый низкий» was chosen out of, and that a low share is not
      /// evidence a child went unvaccinated — only that nobody ticked the
      /// circle. Attributing it to the injection instead of to the tick is the
      /// one misreading this screen can cause.
      lowestRule: report.lowest
        ? `Самый низкий охват выбран среди ${report.measured} прививок из ${report.vaccines.length}, ` +
          'по которым знаменатель вообще есть — у остальных ни один ребёнок ещё не прошёл догоняющее окно. ' +
          'Низкая доля не означает, что прививку не сделали: она означает, что её не отметили в приложении. ' +
          'Данных поликлиник у этой панели нет.'
        : 'Самый низкий охват не показан: ни по одной прививке ни один ребёнок ещё не прошёл догоняющее окно, ' +
          'поэтому сравнивать нечего. Это «неизвестно», а не ноль.',
    });
  });

  /**
   * «Затронет N детей» — what an age change would actually do.
   *
   * `?key=pcv/1` for an existing injection, `?atMonth=` alone for a vaccine
   * that does not exist yet (frame 15a). The query string carries the slash in
   * a key without any encoding argument.
   *
   * The number that matters is `reclassified`: how many children's rows flip
   * between «предстоит», «пора» and «стоит наверстать» the moment the change is
   * published. Moving a booster by a month can put thousands of children into a
   * catch-up list overnight, and nobody should be able to do that without the
   * count in front of them.
   */
  app.get('/admin/vaccination/impact', async (req, reply) => {
    const s = await requireCap(req, reply, 'health');
    if (!s) return;
    const q = req.query as { key?: string; atMonth?: string };
    const proposed = q.atMonth == null || q.atMonth === '' ? null : Number(q.atMonth);
    if (proposed != null && (!Number.isInteger(proposed) || proposed < 0 || proposed > 216)) {
      return reply.code(400).send({ error: 'bad_at_month' });
    }
    const schedule = await servedVaccinationSchedule(repo);
    let data;
    try {
      data = await repo.vaccinationCoverage();
    } catch {
      return reply.code(503).send({
        error: 'impact_unavailable',
        message: 'Не удалось посчитать, скольких детей это затронет. Сохранение не заблокировано, ' +
          'но число сейчас неизвестно — это не ноль.',
      });
    }
    if (!q.key) {
      if (proposed == null) return reply.code(400).send({ error: 'at_month_required' });
      return reply.send({ ...impactOfNew(schedule, data, proposed), isNew: true, ageLabel: ageLabelRu(proposed) });
    }
    const impact = impactOf(schedule, data, q.key, proposed);
    if (!impact) {
      // A drafted vaccine is not in the served schedule, so there is honestly
      // nothing on a phone for a change to reclassify.
      return reply.code(404).send({
        error: 'not_served',
        message: 'Эта прививка сейчас не в графике (черновик), поэтому изменение никого не затронет.',
      });
    }
    return reply.send({ ...impact, isNew: false, ageLabel: ageLabelRu(impact.atMonth) });
  });

  /**
   * Frame 15b «История версий».
   *
   * Straight off the append-only log, so the diff is what actually happened
   * rather than something reconstructed from the current row. A `before` of
   * null is not a gap: it means there was no row, and the text that edit
   * departed from is the shipped contract, which the panel has and shows.
   */
  app.get('/admin/vaccination/log', async (req, reply) => {
    const s = await requireStaff(req, reply);
    if (!s) return;
    const limit = Math.min(200, Math.max(1, Number((req.query as { limit?: string }).limit) || 50));
    try {
      return reply.send({ entries: await repo.vaccinationScheduleLog(limit) });
    } catch {
      return reply.code(503).send({
        error: 'log_unavailable',
        message: 'Журнал версий недоступен — таблица не отвечает. ' +
          'Это не значит, что правок не было.',
      });
    }
  });

  // ---- Детектор плача (кадр 17c) ------------------------------------------
  //
  // READ THIS BEFORE PRINTING ANY NUMBER FROM HERE AS «ТОЧНОСТЬ».
  //
  // `cry_results` records what the classifier ANSWERED — a reason and its own
  // confidence. Until migration 046 there was no column anywhere in this
  // product saying whether the answer was right, and there still is no other
  // source of one: nothing here reads a clinic, and the recording itself is
  // never stored (см. __tests__/cryNotStored.test.ts), so nobody can go back
  // and listen. A model's confidence is not evidence about the model.
  //
  // So accuracy is computed over RATED rows only — the analyses a mother
  // answered «это было верно?» about — and the response carries `unrated` and
  // `ratedSince` beside it so the panel can say «оценок пока нет · собираем
  // с …» instead of inventing a percentage out of average confidence.
  //
  // Aggregates only. No cry row of any individual mother reaches this response:
  // it is GROUP BY reason and nothing else, because a per-mother list here
  // would be a feed of one family's nights in a back office.

  const CRY_WINDOW_DAYS = 30;

  app.get('/admin/cry', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const [threshold, stats] = await Promise.all([
      servedCryThreshold(repo),
      repo.cryStats(CRY_WINDOW_DAYS).catch(() => null),
    ]);
    if (!stats) {
      // A screen of zeroes would read as «детектором никто не пользуется»,
      // which is a claim about the product, not about a failed query.
      return reply.code(503).send({
        error: 'cry_stats_unavailable',
        message: 'Не удалось посчитать статистику детектора — таблица разборов сейчас недоступна. ' +
          'Порог ниже верен; цифры не показаны, и это не нули.',
      });
    }
    const rated = stats.byReason.reduce((n, r) => n + r.correct + r.wrong, 0);
    const correct = stats.byReason.reduce((n, r) => n + r.correct, 0);
    return reply.send({
      windowDays: CRY_WINDOW_DAYS,
      ...stats,
      minConfidence: threshold.minConfidence,
      defaultMinConfidence: threshold.defaultMinConfidence,
      thresholdSource: threshold.source,
      thresholdUpdatedAt: threshold.updatedAt,
      maxMinConfidence: CRY_MIN_CONFIDENCE_MAX,
      // `...stats` above already carries `firstAt` — «собираем с …», the only
      // honest thing to print where a percentage would go while nothing has
      // been rated. Not re-exported under a second name: two fields holding one
      // value is how a panel ends up showing two different dates.
      /// Rated by a mother. THE denominator of every accuracy figure here.
      rated,
      correct,
      /// null, never 0, when nothing has been rated: «нет данных» and «0 %
      /// правильных» are opposite statements about the model.
      accuracy: rated > 0 ? correct / rated : null,
      /// Where the ground truth comes from, in the payload rather than left to
      /// whoever writes the HTML — the same discipline as the vaccination
      /// coverage route's `sourceNote`.
      source: 'mother_verdicts',
      sourceNote: 'Точность считается только по разборам, которые мама оценила сама («это было верно?»). ' +
        'Уверенность модели — это её мнение о себе, и точностью не является.',
      audioNote: 'Записи не хранятся: клип уходит в классификатор и нигде не сохраняется, ' +
        'поэтому послушать разбор из панели нельзя.',
      rule: `Окно — ${CRY_WINDOW_DAYS} дней. «Ниже порога» — разборы с уверенностью меньше ` +
        `${Math.round(threshold.minConfidence * 100)} %: приложение по ним НЕ называет причину.`,
    });
  });

  /**
   * The threshold, changed without a release — the whole point of frame 17c.
   *
   * Below it the app names no reason: it says «не уверены», keeps the bars and
   * asks for another recording. Raising it means more «не уверены» and fewer
   * confident wrong answers; lowering it the reverse. The panel states that
   * consequence beside the field, and this route states the range.
   */
  app.put('/admin/cry/threshold', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const parsed = cryThresholdBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.setCryThreshold({ minConfidence: parsed.data.minConfidence, updatedBy: s.staffId });
    await repo.writeAudit({
      staffId: s.staffId,
      action: 'edit_cry_threshold',
      target: `minConfidence=${parsed.data.minConfidence}`,
    });
    return reply.send({ ok: true, minConfidence: parsed.data.minConfidence });
  });

  // ---- Рассылки (frame 06 «Маркетинг») ------------------------------------
  //
  // Writing to every pregnant user at once is the most dangerous button in this
  // panel: it is irreversible, it reaches people who did not ask for it, and it
  // is the only place where a mistake is delivered rather than displayed. Three
  // rules make it survivable, and all three are enforced HERE rather than in
  // the browser:
  //
  //   * publication needs the Kazakh version (the content editor's own rule);
  //   * a woman is written to at most once a week, across broadcasts;
  //   * a segment may only name what the schema honestly knows — never health.
  //
  // The panel checks the first before the round trip so the refusal is instant.
  // The server checks all three because a check only in the browser is not a
  // rule.

  const BROADCAST_LIMIT = 200;

  const broadcastBody = z.object({
    id: z.string().trim().min(1).max(64),
    titleRu: z.string().trim().min(1).max(120),
    bodyRu: z.string().trim().min(1).max(600),
    // Nullable so a draft can be written in one language first. Publication is
    // where the bilingual rule bites.
    titleKk: z.string().trim().max(120).nullish(),
    bodyKk: z.string().trim().max(600).nullish(),
    // Validated by validateSegment, not by zod: an unknown key must produce a
    // sentence naming the field, and `.strict()` produces «unrecognized_keys».
    segment: z.unknown().optional(),
  });

  /** The segment, or null having already answered 400 with a readable reason. */
  function readSegment(raw: unknown, reply: FastifyReply): BroadcastSegment | null {
    const problems = validateSegment(raw);
    if (problems.length) {
      reply.code(400).send({
        error: problems.some((p) => p.health) ? 'segment_health_forbidden' : 'segment_unsupported_field',
        problems,
        message: segmentMessage(problems),
      });
      return null;
    }
    return normalizeSegment(raw);
  }

  /**
   * Everything the marketing tab draws, in one response.
   *
   * The rule constants travel with the data so the footer states the same
   * seven days the database enforces — a panel with its own copy of that
   * number is a panel that will one day promise a fortnight.
   */
  app.get('/admin/broadcasts', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    let broadcasts;
    try {
      broadcasts = await repo.listBroadcasts(BROADCAST_LIMIT);
    } catch {
      // Migration 037 not applied, or a database blip. Said out loud: an empty
      // table and an unreadable one call for opposite responses, and the panel
      // must not offer «Опубликовать» over a list it could not read.
      return reply.code(503).send({
        error: 'broadcasts_unavailable',
        message: 'Не удалось прочитать таблицу рассылок (broadcasts). Список и отправка недоступны, ' +
          'пока база не ответит — иначе «получателей: 0» читалось бы как «никого нет».',
      });
    }
    return reply.send({
      broadcasts,
      minGapDays: BROADCAST_MIN_GAP_DAYS,
      audiences: BROADCAST_AUDIENCES,
      locales: BROADCAST_LOCALES,
      segmentFields: SEGMENT_FIELDS,
      infantMaxMonths: INFANT_MAX_MONTHS,
    });
  });

  /**
   * How many people this segment covers, and how many of them we may not write
   * to yet.
   *
   * NEVER computed in the browser. The panel holds no user rows at all, and the
   * ids the app knows are local — so any count assembled client-side would be a
   * confident number about a population it cannot see.
   *
   * `:id` may be the literal `new`, and a `segment` query parameter overrides
   * the stored one, so the constructor can show a live count while somebody is
   * still choosing the audience.
   */
  app.get('/admin/broadcasts/:id/preview', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const { id } = req.params as { id: string };
    const raw = (req.query as { segment?: string }).segment;
    let wanted: unknown;
    if (raw != null && raw !== '') {
      try {
        wanted = JSON.parse(raw);
      } catch {
        return reply.code(400).send({
          error: 'segment_unreadable',
          message: 'Сегмент в запросе не разобрать — ожидается JSON вида {"audience":"pregnant"}.',
        });
      }
    } else {
      if (id === 'new') wanted = {};
      else {
        const stored = (await repo.listBroadcasts(BROADCAST_LIMIT)).find((b) => b.id === id);
        if (!stored) return reply.code(404).send({ error: 'not_found' });
        wanted = stored.segment;
      }
    }
    const segment = readSegment(wanted, reply);
    if (!segment) return;
    const audience = await repo.broadcastAudience(segment);
    return reply.send({
      segment,
      ...audience,
      /** Who would actually receive it if it went out now. */
      deliverable: Math.max(0, audience.matched - audience.excluded),
      minGapDays: BROADCAST_MIN_GAP_DAYS,
      describe: describeSegment(segment),
    });
  });

  /** Create a draft. Never sends — publishing is its own decision. */
  app.post('/admin/broadcasts', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const parsed = broadcastBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const segment = readSegment(parsed.data.segment ?? {}, reply);
    if (!segment) return;
    const existing = (await repo.listBroadcasts(BROADCAST_LIMIT)).find((b) => b.id === parsed.data.id);
    if (existing) {
      return reply.code(409).send({
        error: 'already_exists',
        message: `Рассылка «${parsed.data.id}» уже существует — сохраните её через изменение, а не создание.`,
      });
    }
    await saveDraft(parsed.data, segment, s.staffId, reply);
    if (reply.sent) return;
    await repo.writeAudit({ staffId: s.staffId, action: 'broadcast_create', target: parsed.data.id });
    return reply.code(201).send({ ok: true, id: parsed.data.id, segment });
  });

  /** Edit a draft. A published broadcast is refused — it is already on a phone. */
  app.put('/admin/broadcasts/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = broadcastBody.safeParse({ ...(req.body as object), id });
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const segment = readSegment(parsed.data.segment ?? {}, reply);
    if (!segment) return;
    await saveDraft(parsed.data, segment, s.staffId, reply);
    if (reply.sent) return;
    await repo.writeAudit({ staffId: s.staffId, action: 'broadcast_edit', target: id });
    return reply.send({ ok: true, id, segment });
  });

  /** The write both save routes share, including what it says when it refuses. */
  async function saveDraft(
    v: z.infer<typeof broadcastBody>,
    segment: BroadcastSegment,
    staffId: string,
    reply: FastifyReply,
  ): Promise<void> {
    try {
      await repo.saveBroadcast({
        id: v.id,
        titleRu: v.titleRu,
        bodyRu: v.bodyRu,
        titleKk: v.titleKk?.trim() ? v.titleKk.trim() : null,
        bodyKk: v.bodyKk?.trim() ? v.bodyKk.trim() : null,
        segment,
        createdBy: staffId,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('broadcast_already_published')) {
        reply.code(409).send({
          error: 'already_published',
          message: 'Эта рассылка уже отправлена — её текст лежит у людей в телефонах, и изменить его задним числом нельзя. ' +
            'Создайте новую.',
        });
        return;
      }
      throw e;
    }
  }

  /**
   * Send it.
   *
   * The two refusals are the whole feature. Without the Kazakh half a woman who
   * set the app to Kazakh receives Russian marketing — the same silent fallback
   * the week editor exists to close. And the weekly gap is applied in the
   * database rather than in the panel, so a second tab, a double click and a
   * nervous re-publish all land on the same ledger.
   *
   * The response reports MATCHED and EXCLUDED, not just delivered: «ушло 0 из
   * 40» is the sentence an operator needs, and a bare «отправлено» over an
   * audience entirely inside the gap is the confident wrong number this panel
   * must never print.
   */
  app.post('/admin/broadcasts/:id/publish', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const { id } = req.params as { id: string };
    const b = (await repo.listBroadcasts(BROADCAST_LIMIT)).find((x) => x.id === id);
    if (!b) return reply.code(404).send({ error: 'not_found' });
    if (b.status === 'published') {
      return reply.code(409).send({
        error: 'already_published',
        message: 'Эта рассылка уже отправлена. Повторная отправка создала бы второе сообщение об одном и том же.',
      });
    }

    // «Двуязычность обязательна» — the same rule, in the same words, as the
    // timeline cards and the week editor.
    const problems: BilingualProblem[] = [];
    for (const [field, ru, kk] of [
      ['title', b.titleRu, b.titleKk],
      ['summary', b.bodyRu, b.bodyKk],
    ] as const) {
      const missing = missingLocales({ ru: ru ?? '', kk: kk ?? '' });
      if (missing.length) problems.push({ id: b.titleRu || id, field, missing });
    }
    if (problems.length) {
      return reply.code(400).send({
        error: 'translation_required',
        problems,
        message: `${bilingualMessage(problems)}. Без казахской версии рассылку отправить нельзя.`,
      });
    }

    const result = await repo.publishBroadcast(id);
    if (!result) return reply.code(404).send({ error: 'not_found' });
    await repo.writeAudit({
      staffId: s.staffId,
      action: 'broadcast_publish',
      target: id,
      reason: `${describeSegment(b.segment)} · доставлено ${result.delivered} из ${result.matched}`,
    });

    // Push to exactly the people the ledger accepted. FAILS SOFT: the
    // broadcast is published either way, and it reaches her notification centre
    // on the next sync regardless — telling an operator «не отправилось»
    // because one phone had a dead token would be a lie about what happened.
    let pushed = true;
    if (result.userIds.length) {
      try {
        await notify.broadcast?.(result.userIds, {
          id,
          ru: { title: b.titleRu, body: b.bodyRu },
          kk: { title: b.titleKk ?? b.titleRu, body: b.bodyKk ?? b.bodyRu },
        });
      } catch (e) {
        pushed = false;
        app.log.warn(
          `broadcast ${id} published to ${result.delivered} recipient(s) but the push failed — ` +
          `${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }
    return reply.send({
      ok: true,
      id,
      ...result,
      // The ids are what the notifier needed; the panel gets counts. A list of
      // user ids on a marketing screen is a list of people nobody there has a
      // reason to see.
      userIds: undefined,
      pushed,
      minGapDays: BROADCAST_MIN_GAP_DAYS,
    });
  });

  /**
   * How far back frame 25 looks by default.
   *
   * Thirty days, the same window as the cry detector's, because both answer
   * «работает ли это сейчас» rather than «сколько всего». A lifetime total
   * would keep looking healthy for months after delivery broke.
   */
  const NOTIFY_WINDOW_DAYS = 30;

  /**
   * КАДР 25 · УВЕДОМЛЕНИЯ — what happened to every push we tried to send.
   *
   * Listed in the spec and never built, which is why nothing in this product
   * could answer the two questions a notification feature generates: «сколько
   * дошло» and «почему ЕЙ не пришло». The marketing tab's «Доставлено N» counts
   * ledger rows — people we decided to write to — and says nothing about
   * phones.
   *
   * THREE THINGS THIS DELIBERATELY DOES NOT RETURN.
   *
   * An open rate. FCM accepting a message is not a phone displaying it and is
   * certainly not a woman reading it. Nothing in this product records an open,
   * so there is no such number to print and none is derived.
   *
   * A padded list of kinds. A kind nothing happened to is absent, not a row of
   * zeros: «broadcast 0 0 0» reads as a broken sender, when the truth is that
   * nobody has sent one this week.
   *
   * Anybody's identity. The held counts say how many attempts were held and
   * why, never who — the switches are hers, and a back office does not need a
   * list of women who muted advertisements to know the feature works.
   *
   * `content` rather than `staff`: this is the delivery half of the marketing
   * and support screens, and it is the content editor who writes the messages
   * whose fate it reports.
   */
  app.get('/admin/notifications', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const raw = Number((req.query as { days?: string }).days ?? NOTIFY_WINDOW_DAYS);
    const days = Number.isFinite(raw) ? Math.min(90, Math.max(1, Math.trunc(raw))) : NOTIFY_WINDOW_DAYS;
    let summary;
    try {
      summary = await repo.pushDeliverySummary(days);
    } catch {
      // Migration 047 not applied, or a database blip. Said out loud rather
      // than answered with zeros: «доставлено 0» and «мы не смогли прочитать»
      // call for opposite reactions, and an empty table that means the second
      // one is how somebody spends an afternoon debugging a working sender.
      return reply.code(503).send({
        error: 'notifications_unavailable',
        message: 'Не удалось прочитать журнал отправок (push_deliveries). Пока база не ответит, ' +
          'цифр здесь не будет — ноль читался бы как «ничего не отправлялось».',
      });
    }
    return reply.send({
      ...summary,
      // The vocabulary travels with the data, so the panel labels the same
      // reasons the server writes and cannot invent a third.
      holdReasons: HOLD_REASON_RU,
      categories: NOTIFY_CATEGORIES,
      // Stated by the server, so the footer's promise and the gate's behaviour
      // are one fact rather than two.
      alwaysDelivered: ['sos', 'emergency'],
    });
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

  /**
   * ---- Audit log (`staff`) ----
   *
   * Paged. It served the newest 100 and nothing else, and the panel drew no
   * pager, so a reviewer could reach the most recent page of the log and no
   * other. That makes the guarantee the whole design rests on — opening a
   * mother's record costs a written reason, and somebody can read the log
   * afterwards — true only for this week.
   *
   * `hasMore` and not `total`: see AuditPage in db/repository.ts. The number
   * of rows in an append-only table is a full scan Postgres would run on
   * every open of the tab, and printing a made-up one instead is not on the
   * table. The panel says so on screen.
   *
   * `limit` and `offset` are echoed back so the footer can number the page
   * from what the server actually served rather than from what it asked for.
   */
  app.get('/admin/audit', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    const q = req.query as { limit?: string; offset?: string };
    const limit = clampLimit(q.limit, 100, 500);
    const offset = Math.max(0, Number(q.offset ?? 0) || 0);
    const page = await repo.listAudit(limit, offset);
    return reply.send({ audit: page.entries, hasMore: page.hasMore, limit, offset });
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

  /**
   * Frame 02 «Заказы» — one page of the list, plus the numbers it prints.
   *
   * `total` follows the filter so the footer can say «Показано 25 из 40
   * отменённых» and mean it. `counts` deliberately does NOT: those figures sit
   * on the filter chips, and a counter that changes the moment you click it
   * cannot be used to decide what to click.
   *
   * `orders` stays the top-level key it always was — /admin/dashboard and the
   * finance report are not the only readers of this shape, and renaming it to
   * fit a footer would break screens that never asked for one.
   */
  app.get('/admin/shop/orders', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const q = req.query as { limit?: string; offset?: string; status?: string };
    const limit = clampLimit(q.limit, 100, 500);
    const offset = Math.max(0, Number(q.offset ?? 0) || 0);
    // An unknown status is dropped rather than refused: a stale bookmark should
    // show the whole list, not an error page.
    const status = (SHOP_ORDER_STATUSES as readonly string[]).includes(q.status ?? '')
      ? (q.status as ShopOrderStatus)
      : undefined;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_shop_orders' });
    const page = await repo.adminShopOrderPage({ limit, offset, status });
    return reply.send({ ...page, limit, offset, status: status ?? null });
  });

  /**
   * Frame 03 «Карточка заказа».
   *
   * Everything on one card: the composition, the recorded history, the link
   * that opens the conversation with the customer, and — as a stated absence —
   * what the schema cannot tell the operator about payment. Clicking a row in
   * frame 02 used to do nothing at all.
   *
   * The serials bound to the order are NOT here. They are the one thing on this
   * screen behind a different capability (`stock`, not `orders`), and folding
   * them in would either widen who can read the device registry or refuse the
   * whole card to an operator who is entitled to all the rest of it. The panel
   * asks GET /admin/shop/orders/:id/devices separately and says so when that
   * request is the one that is refused.
   */
  app.get('/admin/shop/orders/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const { id } = req.params as { id: string };
    const order = await repo.shopOrderById(id);
    if (!order) return reply.code(404).send({ error: 'not_found' });

    // Audited: unlike the list, this is one named customer with her address and
    // her telephone number on the screen.
    await repo.writeAudit({ staffId: s.staffId, action: 'view_shop_order', target: id });

    const timeline = buildOrderTimeline(order, await repo.shopOrderEvents(id));

    /**
     * Refunds booked against this order — frame 05a.
     *
     * NULL, not [], when the read throws. An empty list is «возвратов не было»,
     * which is a claim; a failed read is «мы не знаем», and the card says so
     * rather than drawing an order as clean when it may not be.
     */
    const refunds = await repo.orderRefunds(id).catch(() => null);
    const refundedMinor = refunds ? refunds.reduce((n, r) => n + r.amountMinor, 0) : null;

    return reply.send({
      order,
      ref: orderRef(order.id),
      refunds,
      timeline: timeline.entries,
      // The card prints this sentence when it is true. See admin/orders.ts.
      historyGap: timeline.gap,
      // Null when there is no number we can write to — the card then says the
      // order has no reachable contact instead of offering a dead link.
      whatsapp: orderWhatsappLink(order),
      /**
       * What this product does not record about money.
       *
       * There is no payment column anywhere in the schema: no method, no paid
       * flag, no transaction id. Orders are cash on delivery — that is why
       * fulfilling one, not placing it, is what grants the course. An operator
       * reading a card must be told that rather than left to assume a blank
       * field means unpaid.
       */
      payment: {
        totalMinor: order.totalMinor,
        discountMinor: order.discountMinor,
        recorded: false,
        /** Already handed back. Null when the refunds read failed. */
        refundedMinor,
        /**
         * The most this order can still be refunded — the SAME arithmetic the
         * repository refuses on, sent once so the form and the server cannot
         * disagree about the limit. Null when we could not read the refunds:
         * the form then refuses to guess rather than offering the full total.
         */
        refundableMinor: refundedMinor == null
          ? null
          : Math.max(0, order.totalMinor - refundedMinor),
        note: 'Оплата при получении. Способ и факт оплаты в базе не хранятся — '
          + 'отметить заказ оплаченным здесь нельзя, и сумма ниже это только цена заказа.',
      },
    });
  });

  /**
   * What the storefront card (Магазин) and the keys card (Настройки →
   * Интеграции, frame 24a) both read.
   *
   * NO SECRET LEAVES HERE. The Anthropic key and the Telegram bot token used to
   * come back in full: the panel put them in `<input>` elements, so the key was
   * in the DOM of any screen an operator left open, in the network tab of any
   * browser, and in any HAR anybody exported while reporting a bug. They are
   * `••••7f2a` now — enough to tell which key is installed, useless to a
   * shoulder. See redactSettings() and frame 24's `••••7f2a` rule.
   *
   * Still audited. It is no longer a read of the key values themselves, but it
   * is still the screen where somebody changes what the storefront says and
   * which credentials the server runs on, and `view_settings` is how that is
   * traced. Cheap, and one row per open rather than per poll.
   */
  app.get('/admin/settings', async (req, reply) => {
    const s = await requireCap(req, reply, 'staff');
    if (!s) return;
    await repo.writeAudit({ staffId: s.staffId, action: 'view_settings' });
    const { settings, secrets } = redactSettings(await repo.getShopSettings());
    // The environment can supply the Anthropic key instead of the panel, and
    // frame 24 already draws that distinction («Ключ из панели» / «Ключ из
    // переменных окружения»). The keys form says the same thing in the same
    // words, so an owner who sees no key in the box is not told the assistant
    // is dead when it is running on ANTHROPIC_API_KEY.
    // The ENVIRONMENT wins, and it wins at startup: index.ts copies a stored key
    // across only when `!process.env.ANTHROPIC_API_KEY`. So `source` is which
    // key the server is really running on, not which one was typed last.
    const envMask = maskSecret(process.env.ANTHROPIC_API_KEY ?? null);
    return reply.send({
      settings,
      secrets: {
        ...secrets,
        anthropicApiKey: {
          ...secrets.anthropicApiKey,
          source: envMask ? 'env' : (secrets.anthropicApiKey.stored ? 'panel' : null),
          envMask,
        },
      },
    });
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
      // A review someone actually wrote on WhatsApp is a real review, so this
      // one stays and /shop/config still publishes it.
      reviews: z.string().trim().max(6000).optional(),
      /**
       * No `rating`, no `reviewCount`.
       *
       * They were two free-text boxes — «Рейтинг (напр. 4.9)» and «Кол-во
       * отзывов» — that saved, read back, and reached nothing: /shop/config
       * stopped publishing both because nothing in this schema can produce
       * either number. There is no ratings table, no order feedback and no
       * reviews table, so whatever was typed there would be invented, and the
       * landing has already carried invented social proof once. See the note in
       * routes/crud.ts and landingHonesty.test.ts.
       *
       * So the owner typed 4.9, the panel said «Сохранено», and the storefront
       * never showed it. Withdrawn the same way `googleMapsApiKey` was: zod
       * strips an unknown key, so a client still sending one is ignored rather
       * than refused, and any row already in shop_settings is left exactly
       * where it is — nothing is silently destroyed. The panel names those
       * leftovers on screen instead of pretending they matter.
       */
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
    /** Secrets that arrived as their own mask and were therefore not written. */
    const kept: string[] = [];
    for (const [k, v] of Object.entries(parsed.data)) {
      if (v === undefined) continue;
      // The mask must never be able to become the key.
      //
      // Once GET stopped returning the real value, the obvious client bug is a
      // form that renders `••••7f2a` in the box and posts it straight back on
      // the next save — for an edit to the WhatsApp number, say. Writing that
      // would replace a working API key with eight bullet characters, report
      // success, and leave no trace until the assistant went quiet. Refusing it
      // HERE means no client can do it, not just the one we shipped.
      if ((SECRET_SETTING_KEYS as readonly string[]).includes(k) && looksMasked(v)) {
        kept.push(k);
        continue;
      }
      patch[k] = k === 'whatsapp' ? v.replace(/\D/g, '') : v;
    }
    await repo.setShopSettings(patch);
    // Audit key NAMES only — never the secret values.
    await repo.writeAudit({ staffId: s.staffId, action: 'set_settings', target: Object.keys(patch).join(',') });
    const { settings, secrets } = redactSettings(await repo.getShopSettings());
    // The response is redacted for the same reason the GET is: a PUT that
    // echoed the stored key back would put it in the browser anyway.
    return reply.send({
      ok: true,
      settings,
      secrets,
      /** Named so the panel can say «ключ оставлен прежним» rather than imply it was rewritten. */
      keptUnchanged: kept,
      /** Which keys were actually written, so «Сохранено» is not a guess. */
      written: Object.keys(patch),
    });
  });
  // ---- Frame 12 · «Поддержка» -------------------------------------------
  //
  // `customers`, which the support role has and a warehouse hand does not. NOT
  // `health`: a support operator answering «где мой заказ» has no business
  // reading a pregnancy record, and the spec is explicit that health and
  // location are the owner's alone. Every ticket names a person, so all of
  // these are audited.

  /**
   * Who is holding a ticket, by NAME.
   *
   * `assignee_id` is selected on every ticket and was drawn nowhere, so two
   * operators answered the same woman a minute apart and neither could see the
   * other had. A raw staff UUID on the screen would not fix that — nobody
   * recognises a colleague by uuid — so it is resolved here, once per request,
   * against the roster.
   *
   * ONLY the display name crosses the wire. A support operator holds
   * `customers`, not `staff`, and has no business receiving the roster's phone
   * numbers and roles as a side effect of opening a ticket.
   *
   * An unresolvable id (a deleted account, or a repository that cannot list
   * staff) comes back as null, and the panel says «имя не найдено» rather than
   * inventing one or pretending the ticket is unassigned.
   */
  async function assigneeNames(ids: Array<string | null>): Promise<Map<string, string>> {
    const wanted = new Set(ids.filter((id): id is string => !!id));
    if (!wanted.size) return new Map();
    const roster = await repo.listStaffAccounts().catch(() => []);
    const out = new Map<string, string>();
    for (const a of roster) {
      if (wanted.has(a.id) && a.displayName) out.set(a.id, a.displayName);
    }
    return out;
  }

  app.get('/admin/support', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const [tickets, templates] = await Promise.all([
      repo.listSupportTickets(300).catch(() => []),
      repo.listSupportTemplates().catch(() => []),
    ]);
    await repo.writeAudit({ staffId: s.staffId, action: 'view_support' });
    const board = buildSupportBoard(tickets, new Date().toISOString());
    const names = await assigneeNames(board.items.map((t) => t.assigneeId));
    return reply.send({
      ...board,
      templates,
      slaHours: SUPPORT_SLA_HOURS,
      // The link is built server-side so the panel cannot compose a different
      // one — and so a ticket with no usable number comes back as null rather
      // than as a button that opens nothing.
      items: board.items.map((t) => ({
        ...t,
        whatsapp: whatsappReplyLink(t),
        assigneeName: t.assigneeId ? names.get(t.assigneeId) ?? null : null,
      })),
    });
  });

  app.get('/admin/support/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const { id } = req.params as { id: string };
    const ticket = await repo.getSupportTicket(id);
    if (!ticket) return reply.code(404).send({ error: 'not found' });
    await repo.writeAudit({ staffId: s.staffId, action: 'view_support_ticket', target: id });
    const names = await assigneeNames([ticket.assigneeId]);
    return reply.send({
      ticket,
      // See assigneeNames: the drawer names the colleague who has this ticket,
      // and null means "we could not resolve the id", not "nobody has it".
      assigneeName: ticket.assigneeId ? names.get(ticket.assigneeId) ?? null : null,
      replies: await repo.listSupportReplies(id).catch(() => []),
      whatsapp: whatsappReplyLink(ticket),
    });
  });

  app.post('/admin/support', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const parsed = z.object({
      subject: z.string().trim().min(1).max(200),
      body: z.string().trim().max(4000).default(''),
      phone: z.string().trim().max(40).nullable().optional(),
      customerName: z.string().trim().max(120).nullable().optional(),
      channel: z.enum(SUPPORT_CHANNELS).default('phone'),
      userId: z.string().uuid().nullable().optional(),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    // The table's CHECK demands one or the other; refusing here names the field
    // instead of letting a constraint violation reach the operator as a 500.
    const t = parsed.data;
    if (!t.userId && !(t.phone ?? '').trim()) {
      return reply.code(400).send({ error: 'a ticket needs a phone or a user' });
    }

    const id = await repo.createSupportTicket({
      subject: t.subject,
      body: t.body,
      phone: t.phone ?? null,
      customerName: t.customerName ?? null,
      channel: t.channel,
      userId: t.userId ?? null,
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'support_create', target: id });
    return reply.code(201).send({ ok: true, id });
  });

  app.post('/admin/support/:id/reply', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = z.object({
      body: z.string().trim().min(1).max(4000),
      /** Mark it as now waiting on her rather than on us. */
      waiting: z.boolean().default(true),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const ticket = await repo.getSupportTicket(id);
    if (!ticket) return reply.code(404).send({ error: 'not found' });

    await repo.addSupportReply({
      ticketId: id, author: 'staff', staffId: s.staffId, body: parsed.data.body,
    });
    // answeredAt is what stops the SLA clock. Set on every staff reply, so a
    // ticket answered in four minutes never reads as four hours late because
    // she has not written back.
    await repo.updateSupportTicket(id, {
      answeredAt: new Date().toISOString(),
      status: parsed.data.waiting ? 'waiting' : 'open',
    });
    await repo.writeAudit({ staffId: s.staffId, action: 'support_reply', target: id });

    // Tell her. Without this the reply lands in a screen she has no reason to
    // reopen, which is the same silence the app-side thread was built to end.
    //
    // FAILS SOFT, on purpose and in both directions: a box with no FCM
    // credentials has no notifier at all, and a notifier that cannot deliver
    // reports rather than throws. The reply is already saved, so an operator
    // being told «не отправилось» here would be told a lie about the thing she
    // actually did. What did not happen is logged instead.
    if (ticket.userId) {
      try {
        await notify.supportReply?.(
          ticket.userId, { id, subject: ticket.subject }, parsed.data.body,
        );
      } catch (e) {
        app.log.warn(
          `support: reply saved for ticket ${id} but the push failed — ` +
          `${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }
    return reply.send({ ok: true });
  });

  app.patch('/admin/support/:id', async (req, reply) => {
    const s = await requireCap(req, reply, 'customers');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = z.object({
      status: z.enum(SUPPORT_STATUSES).optional(),
      assigneeId: z.string().uuid().nullable().optional(),
    }).strict().safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const patch: Record<string, unknown> = { ...parsed.data };
    // «Ничего не удаляется» — closing is a status and a timestamp, never a
    // delete, so the ticket stays readable afterwards.
    if (parsed.data.status === 'closed') patch.closedAt = new Date().toISOString();
    // Reopening clears it, or a reopened ticket would still claim it is closed.
    if (parsed.data.status && parsed.data.status !== 'closed') patch.closedAt = null;

    const ok = await repo.updateSupportTicket(id, patch);
    if (!ok) return reply.code(404).send({ error: 'not found' });
    await repo.writeAudit({
      staffId: s.staffId, action: 'support_update', target: id,
      reason: Object.keys(parsed.data).join(','),
    });
    return reply.send({ ok: true });
  });

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
  // `finance`, not `stock` — and the comment above has always said so.
  //
  // It asked for «the capability that already gates margin» and then named the
  // one that gates the warehouse. `seller: ['orders','customers','stock']` and
  // `warehouse: ['stock']` are precisely the two roles the spec keeps margin
  // FROM, and `stock` is the single capability they both hold — so the guard
  // admitted exactly the people it was written to exclude. Unit cost, margin,
  // revenue and the CSV export of all three, to whoever packs the boxes.
  //
  // `finance` already existed — «Money: cost, margin, revenue, the owner's
  // dashboard», held by owner and admin alone. Nothing had to be invented; the
  // wrong string was typed, once, and read as correct ever after because the
  // sentence beside it described the right thing.
  //
  // roleAccess.test.ts had a case named «a seller sees no margin» that never
  // reached this route. It does now, along with /admin/owner, /admin/security
  // and /admin/entitlements, which the same gap admitted.
  /**
   * How many rows one finance report reads.
   *
   * Windows, not "everything": this route is opened casually and the tables
   * grow forever. What they are NOT is a period — the caller picks that, and
   * these two say how far back the answer can actually see. Both travel into
   * buildFinanceReport so the report can tell when the period it was asked
   * about starts before the rows it was given.
   *
   * The moves window is the binding one: a sale writes one stock move per order
   * line, so 2 000 moves is reached long before 1 000 orders.
   */
  const FINANCE_ORDER_WINDOW = 1000;
  const FINANCE_MOVE_WINDOW = 2000;

  app.get('/admin/finance', async (req, reply) => {
    const s = await requireCap(req, reply, 'finance');
    if (!s) return;

    const q = req.query as { from?: string; to?: string; format?: string };
    const iso = /^\d{4}-\d{2}-\d{2}$/;
    const today = new Date().toISOString().slice(0, 10);
    const to = iso.test(q.to ?? '') ? q.to! : today;
    const from = iso.test(q.from ?? '') ? q.from! : `${today.slice(0, 7)}-01`;
    if (from > to) {
      return reply.code(400).send({ error: 'from must not be after to' });
    }

    // Refunds are read for the WHOLE window rather than as a newest-N slice:
    // there are few of them, and «Возвращено денег» must not be a floor on the
    // one screen somebody reconciles against a bank statement.
    //
    // The failure is carried instead of swallowed. Every other read here falls
    // back to [], which for a COUNT means «ноль» — and zero refunds is a
    // flattering lie. `refundsUnavailable` makes the report say «неизвестно».
    let refundsUnavailable = false;
    const [orders, products, moves, refunds, settings] = await Promise.all([
      repo.adminShopOrders(FINANCE_ORDER_WINDOW).catch(() => []),
      repo.adminProducts().catch(() => []),
      repo.stockMoves(FINANCE_MOVE_WINDOW).catch(() => []),
      repo.refundsBetween(from, to).catch(() => { refundsUnavailable = true; return []; }),
      repo.getShopSettings().catch(() => ({} as Record<string, string>)),
    ]);

    const planRaw = (settings.revenuePlanMinor ?? '').trim();
    const report = buildFinanceReport({
      orders, products, moves, refunds, refundsUnavailable,
      planMinor: /^\d+$/.test(planRaw) ? Number(planRaw) : null,
      from, to,
      // The mother card's pattern, applied to the books: a full slice means
      // there is very likely older data we did not read, and the report says so
      // rather than reporting on a period it never reached. A sale writes one
      // stock move PER LINE, so the moves slice is exhausted well before the
      // orders one — ask for last February and every returns figure was 0,
      // including the rate, printed as «Доля возвратов, % — 0,0».
      ordersWindow: FINANCE_ORDER_WINDOW,
      ordersTruncated: orders.length >= FINANCE_ORDER_WINDOW,
      movesWindow: FINANCE_MOVE_WINDOW,
      movesTruncated: moves.length >= FINANCE_MOVE_WINDOW,
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

  /*
   * POST /admin/settings/test-telegram is GONE, and nothing lost a capability.
   *
   * It sent a real message and answered {ok} or {ok:false,error} — one bit and
   * a string. Its only caller was the «Отправить тестовое сообщение» button on
   * the Магазин card, and that card no longer holds the Telegram credentials;
   * they are on Настройки → Интеграции with the rest of the keys.
   *
   * POST /admin/integrations/telegram/check above is the same send, reported as
   * frame 24b asks: token stored, chat named, message delivered — each step
   * with what came back, so «не работает» arrives as a diagnosis rather than as
   * a shrug. Keeping both would have left one of them wired to nothing, which
   * is the defect this panel already has too much of.
   */

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
    const parsed = z.object({ status: z.enum(SHOP_ORDER_STATUSES) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    // The staff id goes to the repository, not only to the audit log: frame 03
    // shows «Отправлен · Нуржан» on the timeline, and the audit row records
    // that the status was changed without recording what it was changed to.
    await repo.setShopOrderStatus((req.params as { id: string }).id, parsed.data.status, s.staffId);
    await repo.writeAudit({ staffId: s.staffId, action: 'shop_order_status', target: (req.params as { id: string }).id });
    return reply.send({ ok: true });
  });

  /**
   * Кадр 05a «Возвраты и брак» — the write side.
   *
   * An operator taking a delivered комплект back from a mother had nowhere to
   * put it. The only writer of a reason='return' move was order CANCELLATION,
   * so the choice was to write the unit off — which destroys stock and inflates
   * «Списано на сумму» — or to record nothing, and the refunded money stayed in
   * «Заработано» for ever.
   *
   * WHY `orders` AND NOT THE OTHER TWO:
   *  · not `stock`, even though this moves stock. `stock` is the warehouse
   *    capability — receipts, write-offs, serials — and a warehouse hand must
   *    not be able to declare that a customer got her money back. This route
   *    writes a financial fact whose stock move is a consequence.
   *  · not `finance`, even though it writes money. `finance` is the READ of the
   *    books and is held by the owner and admins only (ROLE_CAPS); the person
   *    who actually takes the box back at the door is an operator. Guarding the
   *    refund with a capability the operator does not hold is how it goes on
   *    being recorded as a write-off.
   *  · `orders` is what already guards creating an order and moving its status
   *    — the two other irreversible things one can do to somebody's order.
   *
   * Never changes the order's status: a refunded order was still delivered, and
   * quietly marking it «отменён» would move real revenue into «Потеряно на
   * отменах» and return the stock a second time.
   */
  app.post('/admin/shop/orders/:id/refund', async (req, reply) => {
    const s = await requireCap(req, reply, 'orders');
    if (!s) return;
    const { id } = req.params as { id: string };
    const parsed = z.object({
      // Minor units. Positive, because a refund of nothing is not an event; the
      // upper bound is a typo guard, not a policy — the real limit is the
      // order's own total, which only the repository can check.
      amountMinor: z.number().int().min(1).max(1_000_000_000),
      reason: z.enum(ORDER_REFUND_REASONS),
      note: z.string().trim().max(500).optional(),
      // Which lines actually came back on the shelf. Optional and allowed to be
      // empty: a broken unit is refunded and NOT restocked, and pretending it
      // was would sell it again.
      restock: z.array(z.object({
        variantId: z.string().min(1).max(64),
        qty: z.number().int().min(1).max(100),
      })).max(20).optional(),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const res = await repo.recordOrderRefund({
      orderId: id,
      amountMinor: parsed.data.amountMinor,
      reason: parsed.data.reason,
      note: parsed.data.note ?? null,
      staffId: s.staffId,
      restock: parsed.data.restock ?? [],
    });
    if (!res.ok) {
      // Each refusal keeps its own name and its own status: «столько вернуть
      // нельзя» and «такого заказа нет» need different things from the person
      // holding the box, and one shared 400 would tell them neither.
      const code = res.error === 'not_found' ? 404
        : res.error === 'unknown_line' ? 400
          : 409;
      return reply.code(code).send({ error: res.error, variantId: res.variantId });
    }
    // The reason travels into the log as well as into the row: «кто вернул
    // 39 000 ₸ и почему» is exactly the question this log is read for.
    await repo.writeAudit({
      staffId: s.staffId, action: 'order_refund', target: id,
      reason: `${parsed.data.amountMinor / 100} ₸ · ${parsed.data.reason}`,
    });
    return reply.code(201).send({ refund: res.refund });
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
    const leads = await repo.adminShopLeads(limit);
    /**
     * The callback queue's own count — and it is now a TOTAL.
     *
     * The panel used to count `status === 'new'` over whatever this page
     * returned and print it as «не обработано: N», while the dashboard printed
     * «50 из 140» from a real count(*). Two numbers for one queue, and the one
     * an operator works from was the smaller. Since the page is ordered newest
     * first, the leads that fall off it are the OLDEST uncalled ones — exactly
     * the women who have been waiting longest.
     *
     * `repo.shopLeadCounts()` exists so this route can answer that itself. The
     * true figure used to live only on /admin/dashboard, which requires
     * `finance` — and seller, operator and support, the three roles that
     * actually work this queue, do not hold it. So the people doing the calling
     * were the only ones who could not see how much calling was left.
     *
     * `shown` stays beside `total`: they are different questions («сколько в
     * таблице» vs «сколько всего»), and collapsing them is what started this.
     * `exact` stays for the same reason it was added — a panel served by a
     * backend one deploy behind must be able to tell a real total from a page
     * count — and is now true whenever the counts came back.
     *
     * A failed count does not fail the queue: the rows are what somebody rings
     * from. `counts.total` is then null and the panel says the total is
     * unknown, rather than printing the page size as one.
     */
    const counted = await repo.shopLeadCounts().catch(() => null);
    return reply.send({
      leads,
      counts: {
        shown: leads.length,
        /// Over the whole table. Null only when the count itself failed.
        total: counted ? counted.total : null,
        /**
         * «Не обработано» over the whole table — the number the queue is worked
         * from. Falls back to the page's own count when the total read failed,
         * and `exact` then says it is a floor.
         */
        uncalled: counted ? counted.uncalled : leads.filter((l) => l.status === 'new').length,
      },
      limit,
      exact: counted != null,
    });
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
  /**
   * Upload a product photo. Raw image bytes in the body, like the audio route
   * below — the panel sends the file itself rather than asking an operator to
   * find a URL for it.
   *
   * `content` rather than `orders`: this is the shelf's appearance, the same
   * capability that already gates the product copy it sits beside.
   */
  app.post('/admin/shop/products/:id/photo', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const id = String((req.params as { id?: string }).id ?? '');
    const color = String((req.query as { color?: string }).color ?? '').slice(0, 40);
    const mime = String(req.headers['content-type'] ?? '').split(';')[0].trim();
    if (!ALLOWED_PHOTO_MIME.has(mime)) {
      // Named, not a bare 415: an operator who just picked a HEIC off an iPhone
      // needs to be told which formats work, not that something was "wrong".
      return reply.code(415).send({ error: 'not_an_image', allowed: [...ALLOWED_PHOTO_MIME] });
    }
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) return reply.code(400).send({ error: 'empty_photo' });
    if (body.length > MAX_PHOTO_BYTES) {
      return reply.code(413).send({ error: 'photo_too_large', maxBytes: MAX_PHOTO_BYTES });
    }
    // The product has to exist. Otherwise a typo in the id creates a photo
    // nothing will ever show and nobody will ever find.
    const products = await repo.shopProducts().catch(() => []);
    if (!products.some((p: { id: string }) => p.id === id)) return reply.code(404).send({ error: 'no_such_product' });
    await repo.putProductPhoto({ productId: id, color, mime, bytes: body, staffId: s.staffId });
    await repo.writeAudit({ staffId: s.staffId, action: 'product_photo_upload', target: color ? `${id}/${color}` : id });
    return reply.code(201).send({ ok: true, url: photoUrlFor(id, color) });
  });

  app.delete('/admin/shop/products/:id/photo', async (req, reply) => {
    const s = await requireCap(req, reply, 'content');
    if (!s) return;
    const id = String((req.params as { id?: string }).id ?? '');
    const color = String((req.query as { color?: string }).color ?? '').slice(0, 40);
    await repo.deleteProductPhoto(id, color);
    await repo.writeAudit({ staffId: s.staffId, action: 'product_photo_delete', target: color ? `${id}/${color}` : id });
    return reply.send({ ok: true });
  });

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
