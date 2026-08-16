/**
 * In-memory Repository — lets the backend boot and serve real requests WITHOUT a
 * Postgres/Timescale/PostGIS stack, for local dev and demos on test data.
 * Selected in index.ts when USE_MEMORY_DB=true (or no DATABASE_URL). Not for
 * production: state lives in process memory and is lost on restart.
 */

import { randomBytes, randomUUID, scryptSync } from 'node:crypto';
import { CRY_MIN_CONFIDENCE_DEFAULT, type CryThresholdRow } from '../cry/settings';
import type { AnnouncementRow, BroadcastRow, ContentItemRow, Repository, StaffAccount, SleepNight, WearableDayRow, CryRow, WeightRow, KickSessionRow, ContractionSessionRow, MedicalIdRow, NewbornEventRow, GrowthRow, DoseRow, DayLogRow, EpdsRow, SafetyAlertRow, ProfileRow, PregnancyWeekOverride, EmergencyHelpOverride, VaccinationOverride, VaccinationSettings, VaccinationLogEntry, ShopOrderStatus, ShopLeadLocale, ShopLeadStatus, InventoryProduct, StockMoveReason, CourseLesson, CourseProgress, DeviceRegistryRow, ProductStage, ShopCategoryRow, SupportTicketRow, SupportReplyRow, SupportTemplateRow, Supplier, PurchaseOrder, PurchaseOrderItem, PurchaseOrderStatus, NotificationPrefs, PushDeliveryRecord, PushDeliverySummary } from './repository';
import { bundleDiscountMinor, markInStock } from './repository';
import { DEFAULT_PREFS, FALLBACK_TZ } from '../notifications/gate.js';
import { gestationalWeekOn, utcMidnightOf } from '../pregnancy/overrides.js';
import { BROADCAST_MIN_GAP_DAYS, matchesSegment, type AudienceRow } from '../admin/broadcasts.js';
import { normalizePhone } from '../phone.js';
import type { BpCalibration, ChildLocationFix, Geofence, GeofenceEvent } from '@fcs/shared';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { MAX_CODE_ATTEMPTS } from '../routes/phoneAuth.js';
import { normalizeSerial } from '../deviceSerial.js';
import { computeChildrenStats } from '../analytics/childStats.js';
import { emergencyReason } from '../emergency/reason.js';
import { buildSyntheticPopulation } from '../analytics/syntheticPopulation.js';

export const DEMO_USER = '11111111-1111-1111-1111-111111111111';
export const DEMO_CHILD = '33333333-3333-3333-3333-333333333333';

/**
 * The sign-in a developer uses against the in-memory database.
 *
 * Not a secret and not treated as one: this repository is chosen only when
 * there is no Postgres to talk to, and it forgets everything on restart.
 * Production has DATABASE_URL and never constructs this repository. Written
 * down in docs/DEPLOY.md next to the real seeding command.
 */
export const DEV_STAFF_PHONE = '77000000000';
export const DEV_STAFF_PASSWORD = 'dev-password';

/**
 * The dev account's id — a UUID, because staff ids ARE uuids everywhere else.
 *
 * It used to be the string `staff-dev`, and new colleagues got `staff-2`,
 * `staff-3`. Every route that takes a staff id as INPUT validates it as a uuid
 * (`PATCH /admin/support/:id` sets `assignee_id`, which is
 * `UUID REFERENCES staff_accounts(id)`), so in memory mode those routes refused
 * every id this repository could produce: taking a support ticket could not be
 * exercised, demoed or tested at all without Postgres. The fake, not the route,
 * was wrong.
 */
export const DEV_STAFF_ID = '55555555-5555-4555-8555-555555555555';

export function createMemoryRepository(): Repository {
  const home: Geofence = {
    id: '44444444-4444-4444-4444-444444444444',
    name: 'Home',
    shape: 'circle',
    center: { lat: 43.238949, lng: 76.889709 },
    radiusM: 100,
  };

  // Children carry their OWNER. childOwner used to answer DEMO_USER for any
  // child that existed, which made ownership fictional in development: an IDOR
  // regression would pass every dev test, because every caller looked like the
  // owner. The fake now models the thing the real repository enforces.
  const children: Array<{ id: string; name: string; userId: string; gender?: string | null; dateOfBirth?: string | null }> = [
    { id: DEMO_CHILD, name: 'Sultan', userId: DEMO_USER, gender: 'boy', dateOfBirth: '2019-03-08' },
    // A small demo cohort so the admin "Дети" dashboard has a distribution to
    // show in memory mode (real child sync from the app is the follow-up).
    { id: 'demo-c2', name: 'Aruzhan', userId: DEMO_USER, gender: 'girl', dateOfBirth: '2024-09-01' },
    { id: 'demo-c3', name: 'Alikhan', userId: DEMO_USER, gender: 'boy', dateOfBirth: '2023-02-15' },
    { id: 'demo-c4', name: 'Madina', userId: DEMO_USER, gender: 'girl', dateOfBirth: '2021-06-20' },
    { id: 'demo-c5', name: 'Nurai', userId: DEMO_USER, gender: 'girl', dateOfBirth: '2025-11-10' },
    { id: 'demo-c6', name: 'Yerlan', userId: DEMO_USER, gender: 'boy', dateOfBirth: '2017-01-05' },
    { id: 'demo-c7', name: 'Baby', userId: DEMO_USER, gender: null, dateOfBirth: null },
  ];
  // Devices carry their OWNER, for the same reason children do: without it
  // every account in this process shares one fleet, and an authorisation
  // regression passes every dev check.
  //
  // The liveness columns are on the row, exactly as in Postgres: `last_seen`,
  // `battery_pct` and `firmware` are written by touchDevice on the ingest path
  // and by nothing else. A fake that kept them somewhere else — or, as it did,
  // answered `lastSeen: null` for every row — cannot fail on the defect this
  // whole frame exists to fix.
  //
  // `rowId` mirrors devices.id: `id` here is the physical MAC (what the app and
  // the ingest payload carry), and the defect write is addressed by the row,
  // because one MAC can exist under two accounts.
  const devices: Array<{
    id: string; name: string; kind: string; childId: string | null; userId: string;
    rowId: string;
    lastSeen: string | null; batteryPct: number | null; firmware: string | null;
    defectAt: string | null; defectBy: string | null; defectNote: string | null;
  }> = [];

  // ---- Support (frame 12) ----
  // Seeded with one open ticket so the queue is not empty on a dev box: an
  // operator board that looks identical whether it works or not is how a broken
  // one ships.
  const tickets: SupportTicketRow[] = [
    {
      id: 'sup-seed-1', userId: DEMO_USER, phone: '+7 707 345 22 44',
      customerName: 'Айгерім', channel: 'whatsapp',
      subject: 'Не приходит код при входе', body: 'Жду уже 10 минут, кода нет.',
      status: 'new', assigneeId: null,
      createdAt: new Date(Date.now() - 5 * 3600_000).toISOString(),
      updatedAt: new Date(Date.now() - 5 * 3600_000).toISOString(),
      answeredAt: null, closedAt: null,
      appContext: 'Приложение: 0.1.0 · Связь: есть',
      lastCustomerAt: null,
      customerReadAt: null,
    },
  ];
  const replies: SupportReplyRow[] = [];
  /**
   * Stamp on when SHE last wrote, the same way the SQL lateral does.
   *
   * Computed on READ rather than stored on the ticket, so the two
   * implementations cannot disagree about a thread that has just been appended
   * to — the in-memory one is what every route test runs against, and a stale
   * copy here would let a broken SLA clock pass the suite.
   */
  const withLastCustomer = (t: SupportTicketRow): SupportTicketRow => {
    let last: string | null = null;
    for (const r of replies) {
      if (r.ticketId !== t.id || r.author !== 'customer') continue;
      if (last == null || r.at > last) last = r.at;
    }
    return { ...t, lastCustomerAt: last };
  };
  const supportTemplates: SupportTemplateRow[] = [
    { id: 'where_order', title: 'Где мой заказ', sort: 10,
      bodyRu: 'Здравствуйте! Проверила ваш заказ — он {status}. Ожидаемая доставка: {eta}.',
      bodyKk: 'Сәлеметсіз бе! Тапсырысыңызды тексердім — ол {status}. Күтілетін жеткізу: {eta}.' },
    { id: 'pair_device', title: 'Не подключается трекер', sort: 20,
      bodyRu: 'Давайте попробуем заново: выключите трекер, зажмите кнопку 5 секунд и откройте «Устройства».',
      bodyKk: 'Қайтадан көрейік: трекерді өшіріп, түймені 5 секунд басып тұрыңыз да, «Құрылғылар» бөлімін ашыңыз.' },
  ];

  const geofences = new Map<string, Geofence[]>([[DEMO_CHILD, [home]]]);
  const appointments: Array<{ id: string; title: string; at: string; note: string; userId: string }> = [];
  const medications: Array<{ id: string; name: string; dose: string; perDay: number; userId: string }> = [];
  const events: GeofenceEvent[] = [];
  /** Latest fix per child — what lastLocation reads back. */
  const locations = new Map<string, ChildLocationFix>();
  /**
   * The whole trail per child, oldest first — not just the newest fix.
   *
   * It used to be newest-only, which was honest while nothing could read a
   * trail. «История дня» reads one, and a fake that cannot hold two points
   * would let the screen pass its tests against a repository that can never
   * feed it.
   */
  const locationTrail = new Map<string, ChildLocationFix[]>();
  /** Family grants, keyed `owner|member` like the UNIQUE constraint. */
  const familyGrants = new Map<string, {
    ownerUserId: string; memberUserId: string; level: string;
    label: string; createdAt: string;
  }>();
  /** Invitations, keyed by token hash. The token itself is never stored. */
  const familyInviteRows = new Map<string, {
    tokenHash: string; ownerUserId: string; level: string; label: string;
    createdAt: string; expiresAt: string;
    usedAt: string | null; usedBy: string | null; revokedAt: string | null;
  }>();

  /** App sign-in: normalised phone → user id, and that user's name. */
  const usersByPhone = new Map<string, string>();
  const userNames = new Map<string, string>();
  /**
   * When each account appeared — `users.created_at` in Postgres.
   *
   * It exists for one reason: `dashboardSnapshot` reported newToday/new7d/new30d
   * as a hard-coded 0 here while pgRepository counted them, so «сколько людей
   * пришло сегодня» could not be exercised, demoed or tested against the memory
   * repository at all. A fake that answers 0 to a question the real one answers
   * is worse than one that throws — it looks like a working feature nobody is
   * using.
   *
   * DEMO_USER is stamped far in the past on purpose: it is seed data, not
   * somebody who signed up, and dating it "now" would make every memory-mode
   * dashboard claim an arrival today that never happened. A real sign-up
   * through createUserWithPhone is what moves these counters.
   */
  const SEEDED_AT = '2024-01-01T00:00:00.000Z';
  const userCreatedAt = new Map<string, string>([[DEMO_USER, SEEDED_AT]]);
  const userSessions = new Map<
    string,
    { tokenHash: string; userId: string; expiresAt: Date; userAgent: string }
  >();
  const phoneClaims: Array<{ phone: string; at: Date }> = [];
  /// serial -> what we know about that unit. Mirrors device_registry.
  const registry = new Map<string, DeviceRegistryRow>();
  /// phone -> the one live sign-in code, hashed. Mirrors the phone_codes table.
  const phoneCodes = new Map<string, { codeHash: string; expiresAt: Date; attempts: number }>();

  /** Staff sign-in, keyed by normalised phone. */
  const staffAccounts = new Map<string, StaffAccount>();

  // A sign-in that works out of the box, so `npm run dev` reaches the panel
  // through the real login form rather than through the x-staff-role header
  // shortcut. This repository is the in-memory one: it is selected only by
  // USE_MEMORY_DB or a missing DATABASE_URL, and it forgets everything on
  // restart, so a fixed password here is a fixed password to a database that
  // holds nothing. Any deployment has Postgres and never reaches this line.
  {
    const salt = randomBytes(16);
    staffAccounts.set(DEV_STAFF_PHONE, {
      id: DEV_STAFF_ID,
      phone: DEV_STAFF_PHONE,
      passwordHash: `scrypt$${salt.toString('hex')}$${scryptSync(DEV_STAFF_PASSWORD, salt, 64).toString('hex')}`,
      role: 'admin',
      displayName: 'Разработка',
      disabled: false,
    });
  }
  const staffSessions = new Map<
    string,
    { tokenHash: string; staffId: string; expiresAt: Date; userAgent: string }
  >();
  const loginAttempts: Array<{ phone: string; succeeded: boolean; at: Date }> = [];
  /** Dates the account row itself does not carry in this map-of-accounts. */
  const staffMeta = new Map<string, { createdAt: string; lastLoginAt: string | null }>();
  const healthRows: unknown[] = [];
  // Idempotency for telemetry ingest, mirroring the pg phm_unique_reading
  // constraint: (userId, deviceId, recordedAt) seen before → duplicate resend.
  const seenReadings = new Set<string>();
  // Emergency acknowledgements, keyed by the derived emergency id. An overlay —
  // the emergencies themselves are still derived from the health rows, so
  // acknowledging one needs no change to the ingest/triage path.
  const emergencyAcks = new Map<string, { staffId: string; at: string }>();
  const audit: Array<{ staffId: string; action: string; target: string | null; reason: string | null; at: string }> = [];
  const sleep: SleepNight[] = [];
  // Keyed by (user, device, day), exactly like the pg PRIMARY KEY. The userId
  // was dropped on the way in and ignored on the way out, so every account in
  // the process shared one watch history — a fake more permissive than
  // production cannot fail on an authorisation regression.
  const wearableDays: Array<WearableDayRow & { userId: string }> = [];
  // Keyed by (user, at), exactly like the pg PRIMARY KEY. The userId used to be
  // dropped on the way in and ignored on the way out, so every account in the
  // process shared one cry history — the same defect that was fixed for
  // wearableDays above, and the reason a verdict could be applied to somebody
  // else's analysis without anything failing.
  const cryResults: Array<CryRow & { userId: string }> = [];
  /** `cry_settings` — absent until somebody sets a threshold (frame 17c). */
  let cryThresholdRow: CryThresholdRow | null = null;
  const weights: WeightRow[] = [];
  const kickSessions: KickSessionRow[] = [];
  const contractionSessions: ContractionSessionRow[] = [];
  const childEmergency = new Map<string, MedicalIdRow>();
  const newbornEvents = new Map<string, NewbornEventRow[]>();
  const growth = new Map<string, GrowthRow[]>();
  const doses: Array<DoseRow & { userId: string }> = [];
  const vaccines = new Map<string, Set<string>>(); // childId → done vaccine keys
  type BpCalRow = BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number };
  const bpCalibrations: Array<BpCalRow & { userId: string }> = [];
  const dayLogs = new Map<string, DayLogRow>();
  /** `${userId}|${id}` → screening. Keyed like the pg table's primary key. */
  const epds = new Map<string, EpdsRow>();
  const alerts: SafetyAlertRow[] = [];
  /** Profiles by user id — what the pg repository stores on `users`. */
  const profiles = new Map<string, ProfileRow>();
  /** Edited pregnancy weeks, by week — `pregnancy_week_overrides`. */
  const pregWeekOverrides = new Map<number, PregnancyWeekOverride>();
  /**
   * Frame 16b — the editable emergency-help scenarios (app screen 37).
   *
   * Seeded EMPTY, like the two calendars next door: a seeded row would put
   * first-aid instructions nobody wrote in front of somebody deciding whether
   * to call an ambulance, and the editor already has nine scenarios to show
   * from the contract.
   */
  const emergencyOverrides = new Map<string, EmergencyHelpOverride>();
  /**
   * Frames 15 / 15a / 15b — the editable immunisation calendar.
   *
   * Seeded EMPTY, deliberately, exactly like the pregnancy weeks next door: a
   * seeded row would put an age or a label into a clinical calendar that nobody
   * decided, and the editor already has sixteen entries to show from the
   * contract. Empty is the honest starting state.
   */
  const vaccOverrides = new Map<string, VaccinationOverride>();
  let vaccSettings: VaccinationSettings | null = null;
  const vaccLog: VaccinationLogEntry[] = [];
  /**
   * Frame 06 — рассылки and the ledger of who received them.
   *
   * Seeded EMPTY. A demo broadcast would be a message this product claims to
   * have sent to somebody, and the panel's whole job here is to say honestly
   * what went out.
   */
  const broadcasts = new Map<string, Omit<BroadcastRow, 'delivered'>>();
  const broadcastDeliveries: Array<{ broadcastId: string; userId: string; at: string }> = [];
  /**
   * notification_prefs — frame 25.
   *
   * Seeded EMPTY, and that is the state the product spends most of its life in:
   * a woman who has never opened the screen has no row, and no row means
   * everything on. Seeding a row would hide the branch every real account uses.
   */
  const notificationPrefs = new Map<string, NotificationPrefs & { updatedAt: string }>();
  /**
   * users.timezone, which this fake has no users table for.
   *
   * Defaulted to the same 'Asia/Almaty' as the column rather than to UTC:
   * quiet hours read in the wrong zone are the defect the timezone exists to
   * prevent, and a fake that is five hours out would let it through green.
   */
  const userTimezones = new Map<string, string>();
  /** push_deliveries — one row per attempt, held ones included. */
  const pushDeliveries: Array<PushDeliveryRecord & { at: string }> = [];
  let profile: ProfileRow | null = {
    displayName: 'Aigerim',
    phone: '+77001112233',
    dueDate: null,
    locale: 'ru-KZ',
    // Seeded as null on purpose: declining these is the common case, and the
    // back-office has to render "not provided" rather than an empty cell.
    birthDate: null,
    city: null,
    address: null,
    doctorPhone: null,
    avgCycleLength: null,
    avgPeriodLength: null,
  };
  let idSeq = 1;

  // Timeline content, edited through /admin/content. Seeded with a couple of
  // stages so the CMS has something to show before anything is authored.
  const content = new Map<string, ContentItemRow[]>([
    [
      'w20',
      [
        {
          id: 'w20-nutrition',
          kind: 'lesson',
          title: { ru: 'Питание на 20-й неделе', kk: '20-аптадағы тамақтану', en: 'Nutrition at week 20' },
          summary: { ru: 'Что важно есть сейчас.', kk: 'Қазір не жеу маңызды.', en: 'What matters to eat now.' },
          durationMin: 6,
        },
        {
          id: 'w20-cream',
          kind: 'product',
          title: { ru: 'Крем от растяжек', kk: 'Созылу іздеріне қарсы крем', en: 'Stretch-mark cream' },
          summary: { ru: 'Подобрано для 20-й недели.', kk: '20-аптаға таңдалған.', en: 'Chosen for week 20.' },
          priceMinor: 990000,
          currency: 'KZT',
        },
      ],
    ],
    [
      'm4',
      [
        {
          id: 'm4-sleep',
          kind: 'lesson',
          title: { ru: 'Сон в 4 месяца', kk: '4 айдағы ұйқы', en: 'Sleep at 4 months' },
          summary: { ru: 'Режим и укладывание.', kk: 'Режим және ұйықтату.', en: 'Routine and settling.' },
          durationMin: 8,
        },
      ],
    ],
  ]);
  /// Set by deleteAccount. Postgres simply has no row after a delete; this fake
  /// has to remember, or its seeded fallbacks would resurrect erased data.
  let accountDeleted = false;

  // ---- Shop (mirrors migrations/009_shop.sql seed) ----
  // Mirrors migration 021: each product carries its own price, and the combo is
  // a BUNDLE whose stock is derived from its parts rather than stored.
  interface ShopProdRow {
    id: string; name: string; priceMinor: number; sort: number;
    sku?: string | null; costMinor?: number | null;
    kind?: 'simple' | 'bundle'; lowStockThreshold?: number; active?: boolean;
    /** What fulfilling an order for this product unlocks in the app (migration 025). */
    grantsFeature?: string | null;
    // Catalogue (migration 033). Undefined here means the column is NULL —
    // seeded partly on purpose, so the panel's «не указан» filter has
    // something to find on a dev box.
    category?: string | null;
    stage?: ProductStage | null;
    nameKk?: string | null;
    descriptionRu?: string | null;
    descriptionKk?: string | null;
    ageMinMonths?: number | null;
    ageMaxMonths?: number | null;
    photoUrl?: string | null;
    seoSlug?: string | null;
    seoTitle?: string | null;
    seoDescription?: string | null;
  }
  const shopCategories: ShopCategoryRow[] = [
    { id: 'watch', nameRu: 'Смарт-часы', nameKk: 'Смарт-сағат', sort: 10 },
    { id: 'tracker', nameRu: 'Детские трекеры', nameKk: 'Балалар трекері', sort: 20 },
    { id: 'bundle', nameRu: 'Комплекты', nameKk: 'Жинақтар', sort: 30 },
    { id: 'other', nameRu: 'Прочее', nameKk: 'Басқа', sort: 90 },
  ];
  const shopProds: ShopProdRow[] = [
    { id: 'watch', name: 'Смарт-часы Ana-Bala', priceMinor: 2490000, sort: 1, kind: 'simple',
      category: 'watch', stage: 'pregnancy', nameKk: 'Ana-Bala смарт-сағаты' },
    // Deliberately left uncategorised and with no Kazakh name: the panel must
    // show real gaps on a dev box, not a catalogue that looks finished.
    { id: 'tracker', name: 'Детский трекер Ana-Bala', priceMinor: 490000, sort: 2, kind: 'simple',
      ageMinMonths: 24, ageMaxMonths: 120 },
    // The two devices PLUS the Ма!Ма! course, which the landing presents as a
    // 40 000 ₸ gift — so it costs MORE than the hardware sum, not less. A
    // bundle here is an upsell carrying content, not a volume discount.
    { id: 'combo', name: 'Комплект «Мама и ребёнок»', priceMinor: 3900000, sort: 3, kind: 'bundle', grantsFeature: 'mama_course' },
  ];
  const bundleItems: Array<{ bundleId: string; partId: string; qty: number }> = [
    { bundleId: 'combo', partId: 'watch', qty: 1 },
    { bundleId: 'combo', partId: 'tracker', qty: 1 },
  ];
  /** The Ма!Ма! course, added one lesson at a time from the panel. */
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  const lessons: CourseLesson[] = [];
  /// Keyed phone|lessonId, the primary key of course_progress.
  const progress = new Map<string, CourseProgress & { phone: string }>();

  /**
   * The dashboard's course numbers, mirroring the SQL exactly — including the
   * parts that are easy to get subtly wrong.
   *
   * Progress against an UNPUBLISHED lesson does not count (the JOIN in the
   * query filters it), and nobody is "finished" while nothing is published to
   * finish. A fake more forgiving than the query would let a test bless a
   * number the real dashboard never shows.
   */
  /**
   * Where the users are, in the CMS's stage keys.
   *
   * Mirrors the SQL, including the two rules that keep the numbers honest: a
   * due date in the PAST is a birth nobody recorded rather than "week 41" —
   * counting it would pile every stale account onto w40 — and one account can
   * stand in more than one stage, because a mother expecting her second reads
   * her week and her toddler's month both.
   */
  function stageDistribution(): Record<string, number> {
    const out: Record<string, number> = {};
    const bump = (k: string) => { out[k] = (out[k] ?? 0) + 1; };

    // Whole DAYS, both sides, like Postgres subtracting two `date` columns.
    //
    // Comparing a yyyy-MM-dd parsed as UTC midnight against `new Date()` mixes
    // a date with a timestamp: a due date seventy days out came back sixty-nine
    // and a bit, floored to sixty-nine, and put her in week 31 where the query
    // says week 30. A fake that is a week off is worse than no fake — it blesses
    // an answer production never gives.
    const ymd = (s: string): number | null => {
      const [y, m, d] = s.split('-').map(Number);
      return Number.isFinite(y) && Number.isFinite(m) && Number.isFinite(d)
        ? Date.UTC(y, m - 1, d) : null;
    };
    const n = new Date();
    const today = Date.UTC(n.getFullYear(), n.getMonth(), n.getDate());

    const due = profile?.dueDate ? ymd(profile.dueDate) : null;
    if (due != null && due >= today) {
      const daysLeft = Math.round((due - today) / 86400_000);
      bump('w' + Math.max(1, Math.min(40, 40 - Math.floor(daysLeft / 7))));
    }
    for (const c of children) {
      if (!c.dateOfBirth) continue;
      const dob = ymd(c.dateOfBirth);
      if (dob == null || dob > today) continue;
      const b = new Date(dob), t = new Date(today);
      let months = (t.getUTCFullYear() - b.getUTCFullYear()) * 12
          + (t.getUTCMonth() - b.getUTCMonth());
      // age() counts whole months: the day of the month has to have come round.
      if (t.getUTCDate() < b.getUTCDate()) months -= 1;
      bump('m' + Math.max(0, Math.min(60, months)));
    }
    return out;
  }

  function courseSnapshot(asOf: string) {
    const published = new Set(
      lessons.filter((l) => l.course === 'mama' && l.published).map((l) => l.id));
    const per = new Map<string, { started: number; done: number; lastAt: string }>();
    for (const p of progress.values()) {
      // The row exists as soon as she has progress on ANY lesson — the query's
      // GROUP BY does the same — but only published lessons are counted. That
      // difference is exactly why "finished" has to be guarded below: somebody
      // whose only progress is on a draft has a row of zeros, and 0 >= 0 would
      // otherwise declare her finished.
      const row = per.get(p.phone) ?? { started: 0, done: 0, lastAt: '' };
      if (published.has(p.lessonId)) {
        row.started += 1;
        if (p.completed) row.done += 1;
      }
      if (p.updatedAt > row.lastAt) row.lastAt = p.updatedAt;
      per.set(p.phone, row);
    }
    const rows = [...per.values()];
    const weekAgo = new Date(Date.parse(asOf) - 7 * 86400_000).toISOString();
    return {
      lessons: published.size,
      granted: [...entitlements.values()].filter((e) => e.feature === 'mama_course').length,
      started: rows.filter((r) => r.started > 0).length,
      finished: published.size === 0
        ? 0 : rows.filter((r) => r.done >= published.size).length,
      lessonsCompleted: rows.reduce((t, r) => t + r.done, 0),
      active7d: rows.filter((r) => r.lastAt >= weekAgo).length,
    };
  }

  /**
   * Everybody a рассылка could reach, assembled from the rows this fake holds.
   *
   * Mirrors the pg query: one row per user, carrying `users.locale`,
   * `users.due_date` and every `children.date_of_birth` under her. A woman with
   * a profile but no children is here; so is a woman known only through her
   * children, because that is exactly what a LEFT JOIN answers.
   *
   * The pg query starts `FROM users u`, so this starts from the same place: the
   * sign-in map, which is this fake's `users` table. A profile is an UPDATE of
   * that row in Postgres, not a second table — so building the audience out of
   * `profiles` alone dropped every woman who had signed up by phone and not yet
   * saved a profile. She is the most common kind of new account there is, the
   * panel counted her as nobody, and publishing skipped her.
   */
  function audienceRows(): AudienceRow[] {
    const rows = new Map<string, AudienceRow>();
    const ensure = (userId: string): AudienceRow => {
      let r = rows.get(userId);
      if (!r) rows.set(userId, (r = { userId, locale: null, dueDate: null, childCount: 0, childDobs: [] }));
      return r;
    };
    // `FROM users u` — every signed-up account, profile or no profile. Locale
    // and due date stay null for her until she saves one, which is what the
    // columns hold in Postgres too, and «Все» reaches her either way.
    for (const userId of usersByPhone.values()) ensure(userId);
    for (const [userId, p] of profiles) {
      const r = ensure(userId);
      r.locale = p.locale ?? null;
      r.dueDate = p.dueDate ?? null;
    }
    // The seeded demo account, for everything that runs without signing in —
    // the same fallback getProfile uses, so the two cannot disagree about who
    // exists.
    if (!profiles.has(DEMO_USER) && profile) {
      const r = ensure(DEMO_USER);
      r.locale = profile.locale ?? null;
      r.dueDate = profile.dueDate ?? null;
    }
    for (const c of children) {
      const r = ensure(c.userId);
      r.childCount += 1;
      if (c.dateOfBirth) r.childDobs.push(c.dateOfBirth);
    }
    return [...rows.values()];
  }

  /** Written to inside the last [BROADCAST_MIN_GAP_DAYS] days — skip her. */
  function inWeeklyGap(userId: string, now: Date): boolean {
    const floor = now.getTime() - BROADCAST_MIN_GAP_DAYS * 86_400_000;
    return broadcastDeliveries.some(
      (d) => d.userId === userId && Date.parse(d.at) >= floor,
    );
  }

  /** What a phone owns: normalised phone + feature → how it was granted. */
  const entitlements = new Map<string, { phone: string; feature: string; orderId: string | null; grantedBy: string | null; note: string | null; at: string }>();

  /** The stock ledger. Every change, with its reason — never edited, never deleted. */
  const stockMoves: Array<{
    id: number; variantId: string; delta: number; reason: StockMoveReason;
    note: string | null; staffId: string | null; orderId: string | null; at: string;
  }> = [];
  const shopVars: Array<{ id: string; productId: string; color: string; colorHex: string; stock: number; sort: number }> = [
    { id: 'v-w-black', productId: 'watch', color: 'Чёрный', colorHex: '#1C1E2A', stock: 0, sort: 1 },
    { id: 'v-w-rose', productId: 'watch', color: 'Розовое золото', colorHex: '#E8B4A0', stock: 0, sort: 2 },
    { id: 'v-w-violet', productId: 'watch', color: 'Сиреневый', colorHex: '#B9A8F0', stock: 0, sort: 3 },
    { id: 'v-t-teal', productId: 'tracker', color: 'Бирюзовый', colorHex: '#12B3A6', stock: 0, sort: 1 },
    { id: 'v-t-blue', productId: 'tracker', color: 'Синий', colorHex: '#3B82F6', stock: 0, sort: 2 },
    { id: 'v-t-pink', productId: 'tracker', color: 'Розовый', colorHex: '#E85C8A', stock: 0, sort: 3 },
  ];
  /**
   * Кто нам возит, и что уже едет (migration 045, frames 07a / 07g).
   *
   * Shaped exactly like the Postgres rows, not like the API answer: a fake that
   * stores the joined result is a fake whose tests pass while the real join is
   * wrong. The supplier name and the product name are looked up on read here,
   * the same way the SQL joins them.
   */
  const suppliers: Array<{
    id: string; name: string; contact: string | null;
    leadTimeDays: number | null; active: boolean; createdAt: string;
  }> = [];
  const purchaseOrders: Array<{
    id: string; supplierId: string | null; status: PurchaseOrderStatus;
    placedAt: string | null; expectedAt: string | null; note: string | null;
    createdBy: string | null; createdAt: string; updatedAt: string;
  }> = [];
  const purchaseOrderItems: Array<{
    poId: string; variantId: string; qtyOrdered: number;
    unitCostMinor: number | null; qtyReceived: number; receivedAt: string | null;
  }> = [];

  /** The join the SQL does: order + supplier + lines + the product each line names. */
  function hydratePurchaseOrder(po: (typeof purchaseOrders)[number]): PurchaseOrder {
    const supplier = suppliers.find((s) => s.id === po.supplierId) ?? null;
    const items: PurchaseOrderItem[] = purchaseOrderItems
      .filter((it) => it.poId === po.id)
      .map((it) => {
        const v = shopVars.find((x) => x.id === it.variantId);
        return {
          variantId: it.variantId,
          productId: v?.productId ?? '',
          productName: shopProds.find((p) => p.id === v?.productId)?.name ?? '',
          color: v?.color ?? '',
          qtyOrdered: it.qtyOrdered,
          qtyReceived: it.qtyReceived,
          unitCostMinor: it.unitCostMinor,
          receivedAt: it.receivedAt,
        };
      });
    return {
      id: po.id, supplierId: po.supplierId, supplierName: supplier?.name ?? null,
      supplierLeadTimeDays: supplier?.leadTimeDays ?? null,
      status: po.status, placedAt: po.placedAt, expectedAt: po.expectedAt,
      note: po.note, createdBy: po.createdBy,
      createdAt: po.createdAt, updatedAt: po.updatedAt, items,
    };
  }

  type ShopOrderRow = { bundleId?: string | null; phoneNormalized?: string; id: string; customerName: string; phone: string; city: string; address: string; note: string | null; totalMinor: number; discountMinor: number; status: string; createdAt: string; items: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number }> };
  const shopOrders: ShopOrderRow[] = [];
  /**
   * The status history frame 03 draws (migration 039).
   *
   * A flat array, appended to by setShopOrderStatus and read back in insertion
   * order — the same guarantee the pg index gives, so a test that passes here
   * describes what production does.
   */
  type ShopOrderEventRow = {
    id: number; orderId: string; fromStatus: string | null; toStatus: string;
    staffId: string | null; at: string;
  };
  const shopOrderEventRows: ShopOrderEventRow[] = [];
  type ShopLeadRow = { id: string; customerName: string; phone: string; package: string; locale: ShopLeadLocale; status: ShopLeadStatus; createdAt: string };
  const shopLeads: ShopLeadRow[] = [];
  type AudioRow = { track: string; day: number; locale: string; title: string | null; mime: string; bytes: Buffer; updatedAt: string };
  const dailyAudio = new Map<string, AudioRow>(); // key: `${track}|${day}|${locale}`
  // key: `${productId}|${color}` — '' colour is the product's own photo.
  const productPhotos = new Map<string, { mime: string; bytes: Buffer; uploadedAt: string }>();
  const shopSettings = new Map<string, string>();

  // Named rather than returned anonymously so a method can call a sibling —
  // the dashboard snapshot reuses adminBiMetrics and adminProducts instead of
  // restating how "active" and "low stock" are defined.
  const repository: Repository = {
    // Health
    insertHealthMetric: async (m) => {
      const key = `${m.userId}|${m.deviceId}|${m.recordedAt}`;
      if (seenReadings.has(key)) return true; // duplicate resend — do not store again
      seenReadings.add(key);
      // The whole reading is kept, including `deviceTempC` — the watch's
      // site-less temperature, which pg writes to its own `device_temp_c`
      // column. Retained here so a test can show the value survived the wire
      // schema; NOT copied into `coreTempC`, and `adminUserHealth` below still
      // reads temperature from `coreTempC` alone, exactly as the pg SELECT
      // does. A fake that merged them would report a fever the product has
      // ruled it may not claim.
      healthRows.push(m);
      return false;
    },
    listManualVitals: async (userId) => {
      const num = (v: unknown) => (typeof v === 'number' ? v : null);
      return (healthRows as Array<Record<string, unknown>>)
        .filter((r) => r.userId === userId && !r.deviceId) // device-less = hand-entered
        .slice(-200)
        .reverse()
        .map((r) => ({
          recordedAt: String(r.recordedAt),
          heartRateBpm: num(r.heartRateBpm), spo2Pct: num(r.spo2Pct), systolicMmHg: num(r.systolicMmHg),
          diastolicMmHg: num(r.diastolicMmHg), coreTempC: num(r.coreTempC), glucoseMmol: num(r.glucoseMmol),
          // Not read off the row — asserted by the filter above, exactly as the
          // pg `device_id IS NULL` asserts it. Emitting whatever the stored row
          // happened to say would make this fake disagree with production for
          // the one row shape that matters: a reading stored before the field
          // existed. See the interface for what an absent label costs.
          source: 'manual' as const,
        }));
    },
    insertBpCalibration: async (userId, cal) => void bpCalibrations.push({ ...cal, userId }),
    latestBpCalibration: async (userId) => {
      const mine = bpCalibrations.filter((c) => c.userId === userId);
      if (!mine.length) return null;
      // Newest by calibratedAt — the same "latest wins" the pg ORDER BY gives.
      const latest = mine.reduce((a, b) => (a.calibratedAt >= b.calibratedAt ? a : b));
      const { userId: _omit, ...row } = latest;
      return row;
    },
    // ---- App sign-in (phone number) ----
    userByPhone: async (phone) => {
      const id = usersByPhone.get(phone);
      return id ? { id, displayName: userNames.get(id) ?? '' } : null;
    },
    createUserWithPhone: async (a) => {
      const existing = usersByPhone.get(a.phone);
      if (existing) return { id: existing, displayName: userNames.get(existing) ?? '' };
      const id = randomUUID();
      usersByPhone.set(a.phone, id);
      userNames.set(id, a.displayName);
      // Same instant the row would carry in Postgres — see userCreatedAt.
      userCreatedAt.set(id, new Date().toISOString());
      return { id, displayName: a.displayName };
    },
    createUserSession: async (s) => void userSessions.set(s.tokenHash, s),
    userBySessionToken: async (tokenHash) => {
      const s = userSessions.get(tokenHash);
      if (!s || s.expiresAt.getTime() <= Date.now()) return null;
      return { userId: s.userId };
    },
    deleteUserSession: async (tokenHash) => void userSessions.delete(tokenHash),
    recentPhoneClaims: async (phone, since) =>
      phoneClaims.filter((c) => c.phone === phone && c.at >= since).length,
    // ---- Which devices are ours ----
    deviceRegistryEntry: async (serial) => registry.get(normalizeSerial(serial)) ?? null,

    addDeviceSerials: async (rows) => {
      let added = 0;
      for (const r of rows) {
        const serial = normalizeSerial(r.serial);
        // Skipped, not overwritten: receiving the same shipment twice must not
        // reset a sold unit back to stock and hand it to whoever pairs next.
        if (!serial || registry.has(serial)) continue;
        registry.set(serial, {
          serial,
          status: 'stock',
          kind: r.kind ?? null,
          activationCode: r.activationCode ? normalizeSerial(r.activationCode) : null,
          orderId: null,
          receivedAt: new Date().toISOString(),
          activatedByPhone: null,
          activatedAt: null,
          note: r.note ?? null,
        });
        added += 1;
      }
      return { added, skipped: rows.length - added };
    },

    markDeviceActivated: async (serial, phone) => {
      const row = registry.get(normalizeSerial(serial));
      if (!row) return false;
      // Already hers is success: re-pairing after a reinstall has to work.
      if (row.activatedByPhone === phone) return true;
      // Anything else claimed, or blocked, is refused — this is what makes an
      // activation code worth exactly one redemption.
      if (row.status !== 'stock' || row.activatedByPhone != null) return false;
      row.status = 'sold';
      row.activatedByPhone = phone;
      row.activatedAt = new Date().toISOString();
      return true;
    },

    setDeviceRegistryStatus: async (serial, status) => {
      const row = registry.get(normalizeSerial(serial));
      if (row) row.status = status;
    },

    assignDevicesToOrder: async (orderId, serials) => {
      const linked: string[] = [];
      const unknown: string[] = [];
      for (const raw of serials) {
        const serial = normalizeSerial(raw);
        if (!serial) continue;
        const row = registry.get(serial);
        // Reported back rather than swallowed: an unrecognised serial is almost
        // always a typo on the packing slip, and catching it at dispatch is the
        // difference between a correction and a support case.
        if (!row) { unknown.push(serial); continue; }
        row.orderId = orderId;
        linked.push(serial);
      }
      return { linked, unknown };
    },

    devicesForOrder: async (orderId) => [...registry.values()]
        .filter((r) => r.orderId === orderId)
        .sort((a, b) => a.serial.localeCompare(b.serial)),

    listDeviceRegistry: async (limit) => [...registry.values()]
        .sort((a, b) => b.receivedAt.localeCompare(a.receivedAt))
        .slice(0, limit),

    deviceByActivationCode: async (code) => {
      const c = normalizeSerial(code);
      if (!c) return null;
      return [...registry.values()].find((r) => r.activationCode === c) ?? null;
    },

    recordPhoneClaim: async (phone) => void phoneClaims.push({ phone, at: new Date() }),

    putPhoneCode: async (c) => void phoneCodes.set(c.phone, {
      codeHash: c.codeHash, expiresAt: c.expiresAt, attempts: 0,
    }),

    /// Mirrors the SQL exactly, including the order of the checks: a code that
    /// is BOTH expired and out of attempts answers 'too_many', and a wrong
    /// guess is counted before the answer is returned, so firing guesses in
    /// parallel cannot outrun the counter.
    usePhoneCode: async (phone, codeHash, now) => {
      const row = phoneCodes.get(phone);
      if (!row) return 'none';
      if (row.attempts >= MAX_CODE_ATTEMPTS) return 'too_many';
      if (row.expiresAt <= now) return 'expired';
      if (row.codeHash !== codeHash) {
        row.attempts += 1;
        return 'wrong';
      }
      // Consumed: a correct code is worth exactly one sign-in.
      phoneCodes.delete(phone);
      return 'ok';
    },

    // ---- Staff sign-in ----
    staffByPhone: async (phone) => staffAccounts.get(phone) ?? null,
    staffById: async (id) => [...staffAccounts.values()].find((a) => a.id === id) ?? null,
    upsertStaffAccount: async (a) => {
      const existing = staffAccounts.get(a.phone);
      staffAccounts.set(a.phone, {
        id: existing?.id ?? `staff-${staffAccounts.size + 1}`,
        phone: a.phone,
        passwordHash: a.passwordHash,
        role: a.role,
        displayName: a.displayName ?? '',
        disabled: false,
      });
    },
    createStaffAccount: async (a) => {
      if (staffAccounts.has(a.phone)) return null;
      // A uuid, like the column — see DEV_STAFF_ID.
      const id = randomUUID();
      staffAccounts.set(a.phone, { id, ...a, disabled: false });
      staffMeta.set(id, { createdAt: new Date().toISOString(), lastLoginAt: null });
      return { id };
    },
    listStaffAccounts: async () =>
      [...staffAccounts.values()]
        .map((a) => ({
          id: a.id, phone: a.phone, role: a.role,
          displayName: a.displayName, disabled: a.disabled,
          createdAt: staffMeta.get(a.id)?.createdAt ?? new Date(0).toISOString(),
          lastLoginAt: staffMeta.get(a.id)?.lastLoginAt ?? null,
        }))
        // Same order as pg: everyone still working, then the disabled.
        .sort((x, y) => Number(x.disabled) - Number(y.disabled) || x.createdAt.localeCompare(y.createdAt)),
    updateStaffAccount: async (id, patch) => {
      const acct = [...staffAccounts.values()].find((a) => a.id === id);
      if (!acct) return;
      if (patch.role !== undefined) acct.role = patch.role;
      if (patch.displayName !== undefined) acct.displayName = patch.displayName;
      if (patch.passwordHash !== undefined) acct.passwordHash = patch.passwordHash;
      if (patch.disabled !== undefined) acct.disabled = patch.disabled;
    },
    deleteStaffSessionsFor: async (staffId) => {
      let n = 0;
      for (const [hash, s] of staffSessions) if (s.staffId === staffId) { staffSessions.delete(hash); n++; }
      return n;
    },
    touchStaffLogin: async (staffId) => {
      const meta = staffMeta.get(staffId) ?? { createdAt: new Date().toISOString(), lastLoginAt: null };
      meta.lastLoginAt = new Date().toISOString();
      staffMeta.set(staffId, meta);
    },
    createStaffSession: async (s) => void staffSessions.set(s.tokenHash, s),
    staffBySessionToken: async (tokenHash) => {
      const s = staffSessions.get(tokenHash);
      if (!s || s.expiresAt.getTime() <= Date.now()) return null;
      const acct = [...staffAccounts.values()].find((a) => a.id === s.staffId);
      if (!acct || acct.disabled) return null;
      return {
        staffId: acct.id, role: acct.role,
        displayName: acct.displayName ?? '', phone: acct.phone,
      };
    },
    deleteStaffSession: async (tokenHash) => void staffSessions.delete(tokenHash),
    recentFailedLogins: async (phone, since) =>
      loginAttempts.filter((a) => a.phone === phone && !a.succeeded && a.at >= since).length,
    recordLoginAttempt: async (phone, succeeded) =>
      void loginAttempts.push({ phone, succeeded, at: new Date() }),

    // Child / geofence
    loadGeofences: async (childId) => geofences.get(childId) ?? [],
    insertGeofenceEvent: async (e) => void events.push(e),
    // Kept, not discarded: lastLocation is the DB fallback for the location
    // cache, and a repo that threw the fix away could not exercise it.
    insertLocation: async (fix) => {
      locations.set(fix.childId, fix);
      const trail = locationTrail.get(fix.childId) ?? [];
      trail.push(fix);
      // Kept sorted on insert: fixes arrive out of order after an offline
      // tracker flushes its buffer, and a trail drawn in arrival order is a
      // line that doubles back on itself.
      trail.sort((a, b) => a.observedAt.localeCompare(b.observedAt));
      locationTrail.set(fix.childId, trail);
    },
    lastLocation: async (childId) => locations.get(childId) ?? null,
    // ---- Family access (screen 40) ----

    familyMembers: async (ownerUserId) =>
      [...familyGrants.values()]
        .filter((g) => g.ownerUserId === ownerUserId)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .map((g) => ({
          memberUserId: g.memberUserId,
          label: g.label,
          // The dev fake has one profile, so a member's own name is only
          // known when the member happens to be that profile.
          displayName: g.memberUserId === DEMO_USER ? profile?.displayName ?? null : null,
          phone: g.memberUserId === DEMO_USER ? profile?.phone ?? null : null,
          level: g.level,
          createdAt: g.createdAt,
        })),
    familyMemberships: async (memberUserId) =>
      [...familyGrants.values()]
        .filter((g) => g.memberUserId === memberUserId)
        .map((g) => ({ ownerUserId: g.ownerUserId, level: g.level })),
    familyLevel: async (ownerUserId, memberUserId) =>
      familyGrants.get(`${ownerUserId}|${memberUserId}`)?.level ?? null,
    upsertFamilyAccess: async (g) => {
      // Keyed on the pair, like the UNIQUE constraint: accepting twice
      // re-levels rather than granting twice, so one revoke really revokes.
      const key = `${g.ownerUserId}|${g.memberUserId}`;
      familyGrants.set(key, {
        ...g,
        createdAt: familyGrants.get(key)?.createdAt ?? new Date().toISOString(),
      });
    },
    removeFamilyAccess: async (ownerUserId, memberUserId) =>
      familyGrants.delete(`${ownerUserId}|${memberUserId}`),

    createFamilyInvite: async (i) => {
      familyInviteRows.set(i.tokenHash, {
        ...i,
        createdAt: new Date().toISOString(),
        usedAt: null,
        usedBy: null,
        revokedAt: null,
      });
    },
    familyInviteByHash: async (tokenHash) => familyInviteRows.get(tokenHash) ?? null,
    familyInvites: async (ownerUserId, limit) =>
      [...familyInviteRows.values()]
        .filter((i) => i.ownerUserId === ownerUserId)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit),
    claimFamilyInvite: async (tokenHash, byUserId, atIso) => {
      // The same conditions Postgres puts in the WHERE clause, checked and
      // applied without an await between them. A fake that read, decided and
      // then wrote would let two people accept one «одноразовая» link and
      // still pass — which is the bug this is guarding.
      const row = familyInviteRows.get(tokenHash);
      if (!row) return false;
      if (row.usedAt || row.revokedAt) return false;
      if (Date.parse(row.expiresAt) <= Date.parse(atIso)) return false;
      row.usedAt = atIso;
      row.usedBy = byUserId;
      return true;
    },
    revokeFamilyInvite: async (ownerUserId, tokenHash) => {
      const row = familyInviteRows.get(tokenHash);
      if (!row || row.ownerUserId !== ownerUserId) return false;
      if (row.usedAt || row.revokedAt) return false;
      row.revokedAt = new Date().toISOString();
      return true;
    },

    /** The day's trail, half-open on [fromIso, toIso) as Postgres reads it. */
    locationHistory: async (childId, fromIso, toIso, limit) =>
      (locationTrail.get(childId) ?? [])
        .filter((f) => f.observedAt >= fromIso && f.observedAt < toIso)
        .slice(0, limit),
    /**
     * Drop every fix observed before the cutoff, and report how many went.
     *
     * Not a pretend implementation: what a caller can OBSERVE is the same as
     * against Postgres — ask for a fix older than the retention window and it
     * is gone, and the count is one per fix. A fake that returned 0 and kept
     * the rows would let the sweep's wiring pass a test while deleting nothing
     * in production, which is the failure this whole feature is.
     */
    pruneLocationHistory: async (cutoffIso) => {
      let removed = 0;
      for (const [childId, trail] of [...locationTrail.entries()]) {
        const kept = trail.filter((f) => f.observedAt >= cutoffIso);
        removed += trail.length - kept.length;
        if (kept.length) locationTrail.set(childId, kept);
        else locationTrail.delete(childId);
      }
      // The newest-fix cache is a VIEW of the trail, not a second row, so
      // dropping an aged entry here must not add to the count — Postgres
      // deletes one row per fix and the fake has to report the same number.
      for (const [childId, fix] of [...locations.entries()]) {
        if (fix.observedAt < cutoffIso) locations.delete(childId);
      }
      return removed;
    },
    // Push / AI / emergency
    guardianPushTokens: async () => ({ tokens: [], childName: children[0]?.name ?? '', locale: profile?.locale ?? null }),
    guardianPushTokensForUser: async () => ({ tokens: [], locale: profile?.locale ?? null }),
    deletePushToken: async () => {},
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Ambulance', tel: '103' }],
    // The device's real owner — the same correction childOwner already had.
    //
    // This answered DEMO_USER for any device that existed, so ownership was
    // fiction: a signed-in mother was never the owner of her own tracker and
    // could not reassign it (403), while an IDOR regression would have passed
    // every test in the suite. A fake that agrees with whatever the code does
    // cannot fail on the thing it is there to check.
    deviceOwner: async (id) => {
      const d = devices.find((x) => x.id === id);
      return d ? { userId: d.userId } : null;
    },
    childOwner: async (id) => {
      const c = children.find((x) => x.id === id);
      return c ? { userId: c.userId } : null;
    },
    geofenceOwner: async (id) => {
      // Find the child that carries this geofence, then that child's guardian.
      for (const [childId, list] of geofences) {
        if (list.some((g) => g.id === id)) {
          const child = children.find((c) => c.id === childId);
          return child ? { userId: child.userId } : null;
        }
      }
      return null;
    },
    // CRUD
    listChildren: async (userId) =>
      children.filter((c) => c.userId === userId).map((c) => ({
        id: c.id, name: c.name, gender: (c.gender as 'boy' | 'girl' | null) ?? null, dateOfBirth: c.dateOfBirth ?? null,
      })),
    upsertChild: async (userId, c) => {
      const row = {
        id: c.id,
        name: c.name,
        userId,
        gender: c.gender ?? null,
        dateOfBirth: c.dateOfBirth ?? null,
      };
      const i = children.findIndex((x) => x.id === c.id);
      if (i >= 0) children[i] = row;
      else children.push(row);
    },
    deleteChild: async (id) => {
      const i = children.findIndex((c) => c.id === id);
      if (i >= 0) children.splice(i, 1);
    },
    // Appointments
    listAppointments: async (userId) =>
      appointments
        .filter((a) => a.userId === userId)
        .sort((x, y) => x.at.localeCompare(y.at))
        .map(({ id, title, at, note }) => ({ id, title, at, note })),
    upsertAppointment: async (userId, a) => {
      const i = appointments.findIndex((x) => x.id === a.id);
      const row = { ...a, note: a.note ?? '', userId };
      if (i >= 0) appointments[i] = row; else appointments.push(row);
    },
    appointmentOwner: async (id) => {
      const a = appointments.find((x) => x.id === id);
      return a ? { userId: a.userId } : null;
    },
    deleteAppointment: async (id) => {
      const i = appointments.findIndex((a) => a.id === id);
      if (i >= 0) appointments.splice(i, 1);
    },
    // Medications
    listMedications: async (userId) =>
      medications.filter((m) => m.userId === userId).map(({ id, name, dose, perDay }) => ({ id, name, dose, perDay })),
    upsertMedication: async (userId, m) => {
      const i = medications.findIndex((x) => x.id === m.id);
      const row = { ...m, userId };
      if (i >= 0) medications[i] = row; else medications.push(row);
    },
    medicationOwner: async (id) => {
      const m = medications.find((x) => x.id === id);
      return m ? { userId: m.userId } : null;
    },
    deleteMedication: async (id) => {
      const i = medications.findIndex((m) => m.id === id);
      if (i >= 0) medications.splice(i, 1);
    },
    // Scoped to the OWNER, like the real one.
    //
    // This ignored userId and handed back every device in the process, so in
    // memory mode each account saw every other account's trackers. A fake that
    // is more permissive than production cannot fail on an authorisation
    // regression — it agrees with whatever the code does.
    // Only the four fields the interface promises: the liveness and defect
    // columns are back-office data, and spreading the whole row would ship
    // them to every phone that syncs.
    listDevices: async (userId) =>
      devices.filter((d) => d.userId === userId)
        .map((d) => ({ id: d.id, name: d.name, kind: d.kind, childId: d.childId })),
    createDevice: async (userId, d) => {
      // A device id is physical: the same tracker registered twice is one
      // tracker. pg does this with ON CONFLICT (user_id, ble_mac) DO NOTHING,
      // and without it here a re-sync doubled the fleet.
      if (devices.some((x) => x.userId === userId && x.id === d.id)) return;
      devices.push({
        ...d, childId: d.childId ?? null, userId,
        // Postgres mints this; here it is derived, and it has to be unique
        // across accounts because the defect write addresses it.
        rowId: `dev-${userId}-${d.id}`,
        // Never seen, nothing reported — which is NOT the same as "reported
        // nothing", and the panel says so in words.
        lastSeen: null, batteryPct: null, firmware: null,
        defectAt: null, defectBy: null, defectNote: null,
      });
    },
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
    },
    // The write that did not exist anywhere in this codebase. Keyed on the
    // physical id, like the pg one, because that is what the payload carries.
    touchDevice: async (deviceId, seen) => {
      const d = devices.find((x) => x.id === deviceId);
      if (!d) return;
      // GREATEST, like the SQL: a late batch from an offline phone must not
      // drag «последний сигнал» backwards.
      if (!d.lastSeen || seen.at > d.lastSeen) d.lastSeen = seen.at;
      if (seen.batteryPct != null) d.batteryPct = seen.batteryPct;
      if (seen.firmware != null && seen.firmware !== '') d.firmware = seen.firmware;
    },
    markDeviceDefect: async (deviceId, mark) => {
      const d = devices.find((x) => x.rowId === deviceId);
      if (!d) return false;
      d.defectAt = mark?.at ?? null;
      d.defectBy = mark?.by ?? null;
      d.defectNote = mark?.note ?? null;
      return true;
    },
    upsertGeofence: async (childId, g) => {
      const list = geofences.get(childId) ?? [];
      const i = list.findIndex((x) => x.id === g.id);
      if (i >= 0) list[i] = g; else list.push(g);
      geofences.set(childId, list);
    },
    deleteGeofence: async (id) => {
      for (const [k, list] of geofences) geofences.set(k, list.filter((g) => g.id !== id));
    },
    recordNewbornEvent: async (childId, e) => {
      const list = newbornEvents.get(childId) ?? [];
      const i = list.findIndex((x) => x.at === e.at && x.kind === e.kind);
      if (i >= 0) list[i] = e; else list.push(e);
      newbornEvents.set(childId, list);
    },
    listNewbornEvents: async (userId, limit) => {
      const out: Array<{ childId: string; childName: string } & NewbornEventRow> = [];
      for (const c of children) {
        if (c.userId !== userId) continue;
        for (const e of newbornEvents.get(c.id) ?? []) out.push({ childId: c.id, childName: c.name, ...e });
      }
      out.sort((a, b) => b.at.localeCompare(a.at));
      return out.slice(0, limit);
    },
    upsertGrowth: async (childId, g) => {
      const list = growth.get(childId) ?? [];
      const i = list.findIndex((x) => x.at === g.at); // one per day → replace
      if (i >= 0) list[i] = g; else list.push(g);
      growth.set(childId, list);
    },
    listGrowth: async (userId) => {
      const out: Array<{ childId: string; childName: string } & GrowthRow> = [];
      for (const c of children) {
        if (c.userId !== userId) continue;
        for (const g of growth.get(c.id) ?? []) out.push({ childId: c.id, childName: c.name, ...g });
      }
      out.sort((a, b) => a.at.localeCompare(b.at)); // oldest-first, like the app
      return out;
    },
    upsertDose: async (userId, d) => {
      const i = doses.findIndex((x) => x.medId === d.medId && x.date === d.date);
      if (i >= 0) doses[i] = { ...d, userId }; else doses.push({ ...d, userId });
    },
    listDoses: async (userId) =>
      doses.filter((d) => d.userId === userId)
        .map(({ userId: _o, ...d }) => d)
        .sort((a, b) => b.date.localeCompare(a.date)),
    setVaccine: async (childId, vaccineKey, done) => {
      const set = vaccines.get(childId) ?? new Set<string>();
      if (done) set.add(vaccineKey); else set.delete(vaccineKey);
      if (set.size) vaccines.set(childId, set); else vaccines.delete(childId);
    },
    listVaccines: async (userId) => {
      const out: Array<{ childId: string; childName: string; vaccineKey: string }> = [];
      for (const c of children) {
        if (c.userId !== userId) continue;
        for (const key of vaccines.get(c.id) ?? []) out.push({ childId: c.id, childName: c.name, vaccineKey: key });
      }
      return out;
    },
    upsertChildEmergency: async (childId, m) => void childEmergency.set(childId, m),
    getChildEmergency: async (childId) => childEmergency.get(childId) ?? null,
    listMedicalIds: async (userId) => {
      const out: Array<{ childId: string; childName: string } & MedicalIdRow> = [];
      for (const c of children) {
        if (c.userId !== userId) continue;
        const m = childEmergency.get(c.id);
        if (m) out.push({ childId: c.id, childName: c.name, ...m });
      }
      return out;
    },
    queryMetrics: async () => [],
    listGeofenceEvents: async (childId, limit, fromIso, toIso) =>
      events
        // Filtered BEFORE the slice, exactly as the SQL's WHERE runs before its
        // LIMIT. Slicing first and filtering after is the bug this parameter
        // exists to remove: it answers "yesterday's crossings" out of the newest
        // 200 of all time, so a child with a long history gets a confident
        // empty list for every older day.
        .filter((e) => e.childId === childId
          && (!fromIso || e.at >= fromIso)
          && (!toIso || e.at < toIso))
        // Sorted rather than trusting insertion order: an offline tracker
        // flushes its buffer out of order, and the database orders by
        // occurred_at. A fake that returned the last N INSERTED would drop
        // different rows than the LIMIT does.
        .sort((a, b) => b.at.localeCompare(a.at))
        .slice(0, limit),
    // Sleep
    recordSleep: async (_u, s) => {
      const i = sleep.findIndex((x) => x.night === s.night);
      if (i >= 0) sleep[i] = s; else sleep.push(s);
    },
    listSleep: async (_u, limit) => [...sleep].sort((a, b) => b.night.localeCompare(a.night)).slice(0, limit),
    // Watch activity/wellbeing days — upsert on (device, day), exactly as the
    // pg repository's ON CONFLICT does, so a fake that "works" here cannot hide
    // a duplicate-row bug that only appears against a real database.
    upsertWearableDay: async (row) => {
      const i = wearableDays.findIndex(
        (x) => x.userId === row.userId && x.deviceId === row.deviceId && x.day === row.day);
      if (i >= 0) wearableDays[i] = { ...row }; else wearableDays.push({ ...row });
    },
    // Hers, not everybody's — and without the userId field, which is implied by
    // the question and is not part of the row the interface promises.
    listWearableDays: async (userId, limit) =>
      wearableDays
        .filter((d) => d.userId === userId)
        .sort((a, b) => b.day.localeCompare(a.day))
        .slice(0, limit)
        .map(({ userId: _u, ...day }) => ({ ...day })),
    // Baby cry-analysis history
    recordCry: async (userId, c) => {
      const i = cryResults.findIndex((x) => x.userId === userId && x.at === c.at);
      // An upsert of the ANALYSIS must not silently drop a verdict already
      // recorded against it: the app re-pushes its whole history on sign-in,
      // and «это было верно?» would be answered once and then forgotten.
      const kept = i >= 0 ? { verdict: cryResults[i].verdict ?? null, actualReason: cryResults[i].actualReason ?? null } : {};
      const row = { userId, verdict: null, actualReason: null, ...kept, ...c };
      if (i >= 0) cryResults[i] = row; else cryResults.push(row);
    },
    listCry: async (userId, limit) =>
      cryResults
        .filter((c) => c.userId === userId)
        .sort((a, b) => b.at.localeCompare(a.at))
        .slice(0, limit)
        .map(({ userId: _u, ...row }) => ({ ...row })),
    recordCryVerdict: async (userId, at, verdict, actualReason) => {
      const i = cryResults.findIndex((x) => x.userId === userId && x.at === at);
      if (i < 0) return false;
      cryResults[i] = { ...cryResults[i], verdict, actualReason };
      return true;
    },
    cryStats: async (days) => {
      // The window is computed the same way as the pg query below: rows at or
      // after (now - days). Both count only what is inside it, so the panel's
      // «за 30 дней» means the same thing whichever repository answers.
      const from = new Date(Date.now() - days * 86_400_000).toISOString();
      const rows = cryResults.filter((c) => c.at >= from);
      const threshold = cryThresholdRow?.minConfidence ?? CRY_MIN_CONFIDENCE_DEFAULT;
      const byReason = new Map<string, { reason: string; count: number; sum: number; belowThreshold: number; correct: number; wrong: number }>();
      for (const r of rows) {
        let e = byReason.get(r.reason);
        if (!e) byReason.set(r.reason, (e = { reason: r.reason, count: 0, sum: 0, belowThreshold: 0, correct: 0, wrong: 0 }));
        e.count++;
        e.sum += r.confidence;
        if (r.confidence < threshold) e.belowThreshold++;
        if (r.verdict === 'correct') e.correct++;
        if (r.verdict === 'wrong') e.wrong++;
      }
      return {
        analyses: rows.length,
        byReason: [...byReason.values()]
          .map(({ sum, ...e }) => ({ ...e, avgConfidence: e.count ? sum / e.count : 0 }))
          .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason)),
        unrated: rows.filter((r) => r.verdict !== 'correct' && r.verdict !== 'wrong').length,
        lastAt: rows.length ? rows.reduce((m, r) => (r.at > m ? r.at : m), rows[0].at) : null,
        firstAt: rows.length ? rows.reduce((m, r) => (r.at < m ? r.at : m), rows[0].at) : null,
      };
    },
    getCryThreshold: async () => (cryThresholdRow ? { ...cryThresholdRow } : null),
    setCryThreshold: async (v) => {
      cryThresholdRow = {
        minConfidence: v.minConfidence,
        updatedAt: new Date().toISOString(),
        updatedBy: v.updatedBy,
      };
    },
    // Weight (upsert on the date)
    recordWeight: async (_u, w) => {
      const i = weights.findIndex((x) => x.date === w.date);
      if (i >= 0) weights[i] = w; else weights.push(w);
    },
    listWeight: async (_u, limit) => [...weights].sort((a, b) => b.date.localeCompare(a.date)).slice(0, limit),
    // Timed sessions (upsert on ended_at, newest-first out)
    recordKickSession: async (_u, s) => {
      const i = kickSessions.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) kickSessions[i] = s; else kickSessions.push(s);
    },
    listKickSessions: async (_u, limit) => [...kickSessions].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    recordContractionSession: async (_u, s) => {
      const i = contractionSessions.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) contractionSessions[i] = s; else contractionSessions.push(s);
    },
    listContractionSessions: async (_u, limit) => [...contractionSessions].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    // Day logs
    upsertDayLog: async (_u, log) => void dayLogs.set(log.date, log),
    listDayLogs: async (_u, from, to) =>
      [...dayLogs.values()].filter((d) => d.date >= from && d.date <= to).sort((a, b) => a.date.localeCompare(b.date)),
    // Screening results: upsert on (user, id), newest first. Scoped by user id
    // even though this fake models one account — the moment it does not, a test
    // that passes here would be reading another woman's screening in
    // production, and this is the one table where that must be impossible.
    upsertEpds: async (userId, row) => void epds.set(`${userId}|${row.id}`, row),
    listEpds: async (userId, limit) =>
      [...epds.entries()]
        .filter(([k]) => k.startsWith(`${userId}|`))
        .map(([, r]) => r)
        .sort((a, b) => b.takenAt.localeCompare(a.takenAt))
        .slice(0, limit),
    // Safety alerts
    // ---- Support (frame 12) ----
    listSupportTickets: async (limit) =>
      [...tickets].sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit).map(withLastCustomer),
    listSupportTicketsForUser: async (userId, limit) =>
      // user_id ONLY — never a phone match. A ticket with no account belongs to
      // nobody's app, which is the whole point of the constraint.
      tickets.filter((t) => t.userId === userId)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit).map(withLastCustomer),
    getSupportTicket: async (id) => {
      const t = tickets.find((x) => x.id === id);
      return t ? withLastCustomer(t) : null;
    },
    createSupportTicket: async (t) => {
      const id = `sup-${tickets.length + 1}`;
      const now = new Date().toISOString();
      tickets.push({
        id,
        userId: t.userId ?? null,
        phone: t.phone ?? null,
        customerName: t.customerName ?? null,
        channel: t.channel ?? 'whatsapp',
        subject: t.subject,
        body: t.body ?? '',
        status: 'new',
        assigneeId: null,
        createdAt: now,
        updatedAt: now,
        answeredAt: null,
        closedAt: null,
        appContext: t.appContext ?? null,
        lastCustomerAt: null,
        customerReadAt: null,
      });
      return id;
    },
    updateSupportTicket: async (id, patch) => {
      const t = tickets.find((x) => x.id === id);
      if (!t) return false;
      // Only the keys PRESENT, matching the SQL: closing must not clear the
      // assignee, and assigning must not reopen.
      for (const k of Object.keys(patch) as Array<keyof typeof patch>) {
        (t as unknown as Record<string, unknown>)[k] = patch[k] as unknown;
      }
      t.updatedAt = new Date().toISOString();
      return true;
    },
    listSupportReplies: async (ticketId) =>
      replies.filter((r) => r.ticketId === ticketId).sort((a, b) => a.at.localeCompare(b.at)),
    addSupportReply: async (r) => {
      replies.push({
        id: `rep-${replies.length + 1}`,
        ticketId: r.ticketId,
        author: r.author,
        staffId: r.staffId ?? null,
        body: r.body,
        at: new Date().toISOString(),
      });
    },
    markSupportTicketRead: async (id, at) => {
      const t = tickets.find((x) => x.id === id);
      if (!t) return false;
      // customer_read_at and nothing else — no status, no updatedAt. The SQL
      // does exactly this, and a fake that also bumped updatedAt would let a
      // "reading her thread reorders the operator's board" regression pass.
      t.customerReadAt = at;
      return true;
    },
    listSupportTemplates: async () => [...supportTemplates].sort((a, b) => a.sort - b.sort),

    recordAlert: async (_u, a) => void alerts.unshift(a),
    listAlerts: async (_u, limit, fromIso, toIso) =>
      alerts
        // Before the slice, like the SQL's WHERE before its LIMIT.
        .filter((a) => (!fromIso || a.at >= fromIso) && (!toIso || a.at < toIso))
        // recordAlert unshifts, so insertion order is usually newest-first —
        // usually. An offline tracker flushing a buffer records out of order,
        // and the database sorts on `at`. Stable, so equal instants keep the
        // order they were recorded in.
        .sort((a, b) => b.at.localeCompare(a.at))
        .slice(0, limit),
    setAlertOutcome: async (_u, childId, at, outcome) => {
      const row = alerts.find(
        (a) => a.childId === childId && a.kind === 'sos' && Date.parse(a.at) === Date.parse(at));
      if (!row) return false;
      row.outcome = outcome;
      return true;
    },
    // Profile + device reassignment
    // Per USER, like the real one.
    //
    // This returned a single global profile whatever userId it was handed, so
    // in memory mode everybody was Aigerim on +7 700 111 22 33. The pg version
    // selects from `users WHERE id = $1` and the phone it returns is
    // `phone_e164` — the number she signed in with, which is the key an
    // entitlement is stored under. With one shared profile a locally-signed-in
    // account looked up somebody else's number, so a комплект bought and
    // shipped in dev never opened the course and the bug looked like it was in
    // the entitlement.
    getProfile: async (userId) => {
      const own = profiles.get(userId);
      if (own) return { ...own };
      // A user created by phone sign-in has no profile row yet; the phone
      // itself is what identifies the account, so answer with it.
      const phone = [...usersByPhone.entries()].find(([, id]) => id === userId)?.[0];
      if (phone) {
        return {
          displayName: userNames.get(userId) ?? '',
          phone,
          dueDate: null, locale: 'ru-KZ', birthDate: null, city: null,
          address: null, doctorPhone: null, avgCycleLength: null, avgPeriodLength: null,
        };
      }
      // The seeded demo account, for everything that runs without signing in.
      return profile ? { ...profile } : null;
    },
    upsertProfile: async (userId, p) => {
      // The phone is not in [ProfileEdit] and is not taken from the caller: it
      // is whatever sign-in recorded for this user, which is the same thing the
      // pg repository does by leaving `phone_e164` out of its UPDATE. Reading
      // it back off `usersByPhone` keeps the two implementations honest — in
      // memory mode there is no column to leave alone, so the lookup IS the
      // guard.
      const phone = profiles.get(userId)?.phone
        ?? [...usersByPhone.entries()].find(([, id]) => id === userId)?.[0]
        ?? (userId === DEMO_USER ? profile?.phone ?? null : null);
      const next = { ...p, phone };
      profiles.set(userId, next);
      profile = { ...next };
    },
    reassignDevice: async (id, childId) => {
      const d = devices.find((x) => x.id === id);
      if (d) d.childId = childId;
    },
    // Admin
    adminStats: async () => ({
      activeUsers: 1,
      // Devices that have actually reported inside the same 15-minute window
      // the pg query uses — not `devices.length`, which counted a tracker
      // nobody has switched on since it was paired as "online".
      devicesOnline: devices.filter(
        (d) => d.lastSeen != null && Date.now() - new Date(d.lastSeen).getTime() < 15 * 60_000,
      ).length,
      alertsToday: alerts.length,
      ingestLastHour: healthRows.length,
    }),
    childrenStats: async (asOf) =>
      computeChildrenStats(
        children.map((c) => ({ gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null })),
        asOf,
      ),
    recentEmergencies: async (limit) => {
      const rows = (healthRows as Array<Record<string, unknown>>)
        .filter((r) => r.triageSeverity === 'emergency')
        .slice(-limit)
        .reverse();
      const num = (v: unknown) => (typeof v === 'number' ? v : null);
      return rows.map((r) => {
        const userId = String(r.userId ?? DEMO_USER);
        const at = String(r.recordedAt ?? '');
        const id = `${userId}|${at}`; // stable per emergency metric
        const ack = emergencyAcks.get(id);
        // Through the same helper the SQL one uses, over the same stored
        // fields. A fake that answered `code: 'EMERGENCY'` while production
        // named the finding would let the whole feed regress green.
        const reason = emergencyReason({
          heartRateBpm: num(r.heartRateBpm),
          spo2Pct: num(r.spo2Pct),
          systolicMmHg: num(r.systolicMmHg),
          diastolicMmHg: num(r.diastolicMmHg),
          coreTempC: num(r.coreTempC),
          duringSleep: r.duringSleep === true,
        });
        return {
          id,
          userId,
          displayName: userNames.get(userId) ?? profile?.displayName ?? 'Ana-Bala user',
          ...reason,
          severity: 'emergency',
          at,
          acknowledgedAt: ack?.at ?? null,
          acknowledgedBy: ack?.staffId ?? null,
        };
      });
    },
    acknowledgeEmergency: async (id, staffId, at) => {
      if (emergencyAcks.has(id)) return false; // already acknowledged
      emergencyAcks.set(id, { staffId, at });
      return true;
    },
    // Takes its arguments, at last.
    //
    // This was `adminListUsers: async () => …` — no parameters at all. It
    // ignored `q`, `limit` and `offset` and always returned one user, so the
    // panel's search, its paging and its total were exercised ONLY in
    // production. That is why nobody noticed that Postgres searched
    // display_name and email while the box promised «по имени или телефону»:
    // no test could reach the difference, because the fake had no search to be
    // wrong about.
    //
    // An unfaithful fake is worse than no fake — it turns a whole feature into
    // green tests.
    adminListUsers: async (q, limit, offset) => {
      const digits = String(q ?? '').replace(/\D+/g, '');
      const needle = String(q ?? '').trim().toLowerCase();
      // ONE list, assembled from the three places a user can exist in here.
      //
      // Production has a single `users` table. This fake has three stores:
      // `profiles` (what an edit writes), `userNames`/`usersByPhone` (what
      // signing in with a phone creates), and the standalone `profile` variable
      // holding the demo account until something updates it. They are disjoint
      // — so a woman who signed in by phone, which is the ONLY way a real user
      // comes to exist, never appeared in the admin list at all, and no test
      // could see it because the list ignored its arguments anyway.
      const rows = new Map<string, { displayName: string; phone: string | null; dueDate: string | null }>();
      const put = (id: string, v: Partial<{ displayName: string; phone: string | null; dueDate: string | null }>) => {
        const cur = rows.get(id) ?? { displayName: '', phone: null, dueDate: null };
        rows.set(id, {
          displayName: v.displayName ?? cur.displayName,
          phone: v.phone ?? cur.phone,
          dueDate: v.dueDate ?? cur.dueDate,
        });
      };
      if (profile) put(DEMO_USER, { displayName: profile.displayName ?? '', phone: profile.phone ?? null, dueDate: profile.dueDate ?? null });
      for (const [id, name] of userNames) put(id, { displayName: name });
      for (const [ph, id] of usersByPhone) put(id, { phone: ph });
      for (const [id, p] of profiles) put(id, { displayName: p.displayName ?? '', phone: p.phone ?? null, dueDate: p.dueDate ?? null });
      const everyone = [...rows.entries()].map(([id, p]) => ({ id, p }));
      const matches = everyone.filter(({ p }) => {
        if (!needle) return true;
        const name = (p.displayName ?? '').toLowerCase();
        if (name.includes(needle)) return true;
        // Digits both sides, like the pg query: she pastes «+7 701 118 90 12»
        // and the stored value is E.164.
        if (digits.length >= 4) {
          const stored = String(p.phone ?? '').replace(/\D+/g, '');
          if (stored.includes(digits)) return true;
        }
        return false;
      });
      const page = matches.slice(offset ?? 0, (offset ?? 0) + (limit ?? matches.length));
      return {
        // The FILTERED total, as Postgres returns — the footer says «Показано N
        // из M» about the search, not about the table.
        total: matches.length,
        users: page.map(({ id, p }) => {
          // Surface each user's latest reading, like the pg LATERAL: the time
          // (the "last measurement" column) and its triage severity.
          const mine = (healthRows as Array<Record<string, unknown>>).filter((r) => r.userId === id);
          const last = mine[mine.length - 1];
          return {
            id, displayName: p.displayName ?? '', phone: p.phone ?? null, dueDate: p.dueDate ?? null,
            lastMetricAt: last ? String(last.recordedAt) : null,
            latestSeverity: last ? (last.triageSeverity as string) : null,
          };
        }),
      };
    },
    /// The newest reading actually ingested, falling back to the seed.
    ///
    /// This returned a fixed object, so a reading posted to /ingest/batch
    /// vanished from the one view meant to show it. That made the dev stack
    /// unable to answer "did my reading arrive?" — the exact question anyone
    /// wiring the app to the backend is asking — and it hid a real defect for
    /// as long as it existed: hand-entered readings were being rejected
    /// outright, and this view looked healthy throughout.
    adminUserHealth: async (userId) => {
      // An erased account has no health view at all. Falling through to the
      // seed below would show a clinician plausible vitals for someone who had
      // just deleted themselves — making a deletion that worked look like one
      // that had not.
      if (accountDeleted) return null;
      const mine = (healthRows as Array<Record<string, unknown>>).filter(
        (r) => r.userId === userId,
      );
      const last = mine[mine.length - 1];
      if (!last) {
        return { latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7, glucose: 5.4 }, triage: [] };
      }
      const num = (v: unknown) => (typeof v === 'number' ? v : null);
      return {
        latest: {
          hr: num(last.heartRateBpm),
          spo2: num(last.spo2Pct),
          systolic: num(last.systolicMmHg),
          diastolic: num(last.diastolicMmHg),
          temp: num(last.coreTempC),
          glucose: num(last.glucoseMmol),
        },
        triage: mine
          .filter((r) => r.triageSeverity === 'emergency' || r.triageSeverity === 'warning')
          .slice(-10)
          .map((r) => ({
            code: 'SERVER_TRIAGE',
            severity: String(r.triageSeverity),
            at: String(r.recordedAt ?? ''),
          })),
      };
    },

    adminUserDetail: async (userId) => {
      // Same reasoning as adminUserHealth: an erased account has no drilldown.
      if (userId !== DEMO_USER || accountDeleted) return null;
      return {
        id: DEMO_USER,
        displayName: profile?.displayName ?? '',
        phone: profile?.phone ?? null,
        dueDate: profile?.dueDate ?? null,
        locale: profile?.locale ?? null,
        birthDate: profile?.birthDate ?? null,
        city: profile?.city ?? null,
        // Parity with pgRepository.adminUserDetail — the admin drilldown renders
        // "Контакт врача" and "Цикл (база)" from these; the in-memory repo (the
        // one that runs today) was dropping them, blanking a staff-callable
        // doctor number that the feature is documented to surface.
        doctorPhone: profile?.doctorPhone ?? null,
        avgCycleLength: profile?.avgCycleLength ?? null,
        avgPeriodLength: profile?.avgPeriodLength ?? null,
        children: children.map((c) => ({
          id: c.id,
          name: c.name,
          dateOfBirth: c.dateOfBirth ?? null,
          zones: (geofences.get(c.id) ?? []).length,
        })),
        devices: devices.map((d) => ({
          id: d.id,
          name: d.name,
          kind: d.kind,
          childId: d.childId,
          batteryPct: d.batteryPct,
        })),
        latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7, glucose: 5.4 },
        triage: [],
        alerts: alerts.slice(0, 20).map((a) => ({
          kind: a.kind,
          childName: children.find((c) => c.id === a.childId)?.name ?? '',
          zoneName: a.zoneName,
          at: a.at,
        })),
        sleepNights: sleep.length,
        loggedDays: dayLogs.size,
      };
    },

    adminDevices: async (limit) =>
      // Newest signal first, like the pg ORDER BY, and a device that has never
      // reported sorts last rather than being dropped.
      [...devices]
        .sort((a, b) => String(b.lastSeen ?? '').localeCompare(String(a.lastSeen ?? '')))
        .slice(0, limit)
        .map((d) => ({
          id: d.id,
          deviceId: d.rowId,
          name: d.name,
          kind: d.kind,
          // The device's real owner, not a constant. Answering DEMO_USER for
          // every row made the fleet view's "whose device is this" column
          // fiction, and fiction that always agrees with the code.
          userId: d.userId,
          displayName: userNames.get(d.userId) ?? profile?.displayName ?? '',
          childName: children.find((c) => c.id === d.childId)?.name ?? null,
          // Read off the device row, written by touchDevice. This used to be a
          // battery from a Map nothing ever set and a hardcoded `lastSeen:
          // null` — the fake agreed exactly with the missing feature.
          batteryPct: d.batteryPct,
          lastSeen: d.lastSeen,
          firmware: d.firmware,
          defectAt: d.defectAt,
          defectBy: d.defectBy,
          defectNote: d.defectNote,
        })),

    adminSafetyEvents: async (limit) =>
      alerts.slice(0, limit).map((a) => ({
        userId: DEMO_USER,
        displayName: profile?.displayName ?? '',
        childName: children.find((c) => c.id === a.childId)?.name ?? '',
        kind: a.kind,
        zoneName: a.zoneName,
        at: a.at,
        // What the mother chose when she closed it, exactly as setAlertOutcome
        // stored it — and null while she has not. The SQL side reads the
        // `outcome` column; leaving it out here would let a fake agree with a
        // panel that shows every closed SOS as open.
        outcome: a.kind === 'sos' ? (a.outcome ?? null) : null,
        phone: profile?.phone ?? null,
      })),

    deleteAccount: async (userId) => {
      if (userId !== DEMO_USER || accountDeleted) return false;
      accountDeleted = true;
      // Everything this repository holds for the demo user. Postgres does the
      // same through ON DELETE CASCADE; here it has to be spelled out, so the
      // list is kept exhaustive rather than convenient — leaving one behind
      // would make the fake say "erased" while still holding her data.
      profile = null;
      children.length = 0;
      devices.length = 0;
      geofences.clear();
      appointments.length = 0;
      medications.length = 0;
      events.length = 0;
      emergencyAcks.clear();
      weights.length = 0;
      kickSessions.length = 0;
      contractionSessions.length = 0;
      childEmergency.clear();
      newbornEvents.clear();
      healthRows.length = 0;
      seenReadings.clear();
      sleep.length = 0;
      // Hers, by user id — the rows are keyed like the pg table now, and a
      // blanket truncate would be a fake that erases more than the cascade does.
      for (let i = cryResults.length - 1; i >= 0; i--) {
        if (cryResults[i].userId === userId) cryResults.splice(i, 1);
      }
      dayLogs.clear();
      // Her screenings cascade with the account (epds_results.user_id), and
      // this is the last table that may survive an erasure.
      for (const k of [...epds.keys()]) {
        if (k.startsWith(`${userId}|`)) epds.delete(k);
      }
      alerts.length = 0;
      // The watch's activity days go with the account, exactly as
      // wearable_days does through ON DELETE CASCADE. Leaving them behind
      // would let the fake say «стёрто» while still holding her step counts.
      wearableDays.length = 0;
      // Her notification switches cascade too (notification_prefs.user_id).
      // push_deliveries does NOT: its user_id is ON DELETE SET NULL, so the
      // count of what we sent survives the erasure while the name does not —
      // and this fake anonymises rather than deletes, for the same reason.
      notificationPrefs.delete(userId);
      userTimezones.delete(userId);
      for (const r of pushDeliveries) if (r.userId === userId) r.userId = null;
      return true;
    },

    adminBiMetrics: async () => {
      // The memory repo models one user, which would render the overview as
      // "1 user, 0% retention" — a dashboard with nothing to check. Real
      // endpoints are not wired yet, so this is the test data it is developed
      // against; deterministic, so a chart can be verified twice. With
      // DATABASE_URL set, pgRepository computes the same shape from real rows.
      const now = new Date();
      const pop = buildSyntheticPopulation(now);
      // The one genuine account this process knows about joins the population,
      // so a locally exercised flow actually moves the numbers.
      pop.users.push({ id: DEMO_USER, createdAt: new Date(now.getTime() - 45 * 86400000).toISOString() });
      for (const a of alerts) {
        pop.events.push({ userId: DEMO_USER, at: a.at, kind: 'alert' });
      }
      for (const h of healthRows as Array<{ userId?: string }>) {
        pop.events.push({ userId: h.userId ?? DEMO_USER, at: now.toISOString(), kind: 'telemetry' });
      }
      return computeBiMetrics({ ...pop, now });
    },

    dashboardSnapshot: async (asOf) => {
      // Everything below is counted off the rows this process actually holds,
      // EXCEPT the activity figures, which come from adminBiMetrics and are
      // synthetic here (one account cannot produce a retention curve). Keeping
      // the counts real means an order placed in development moves the revenue
      // on the screen, which is the whole point of having this in memory mode.
      const bi = await repository.adminBiMetrics();
      const n = (v: number) => v;
      const kidsByUser = new Map<string, number>();
      for (const c of children) kidsByUser.set(c.userId, (kidsByUser.get(c.userId) ?? 0) + 1);

      const today = asOf.slice(0, 10);
      const users = [...new Set([...usersByPhone.values(), DEMO_USER])];
      const dueDate = profile?.dueDate ?? null;
      const isPregnant = !!dueDate && dueDate >= today;
      const hasKids = (kidsByUser.get(DEMO_USER) ?? 0) > 0;

      const revenue = shopOrders
        .filter((o) => o.status === 'shipped' || o.status === 'delivered')
        .reduce((t, o) => t + o.totalMinor, 0);
      const shipped = shopOrders.filter((o) => o.status === 'shipped' || o.status === 'delivered').length;
      const countStatus = (s: string) => shopOrders.filter((o) => o.status === s).length;

      // Bundles hold no stock of their own; counting them double-counts parts.
      const simpleIds = new Set(shopProds.filter((p) => (p.kind ?? 'simple') !== 'bundle').map((p) => p.id));
      let units = 0, retail = 0, cost = 0, unitsNoCost = 0;
      for (const v of shopVars) {
        if (!simpleIds.has(v.productId)) continue;
        const p = shopProds.find((x) => x.id === v.productId)!;
        units += v.stock;
        retail += v.stock * p.priceMinor;
        if (p.costMinor != null) cost += v.stock * p.costMinor;
        else unitsNoCost += v.stock;
      }

      const cityOf = (profile?.city ?? '').trim();
      // Newcomers, over the same three windows the SQL counts and against the
      // same `asOf` the rest of this snapshot uses. «Сегодня» is from midnight,
      // like `date_trunc('day', now())`; the other two are rolling 7 and 30
      // days, like `now() - interval '7 days'`. Accounts with no recorded
      // creation instant are counted in none of them rather than in all.
      //
      // Bounded at both ends: an account created AFTER the moment the snapshot
      // is taken is not news from that moment, and in Postgres it could not
      // exist at all. Without the upper bound a snapshot dated last week counts
      // everybody who has signed up since as having arrived that day.
      const asOfMs = new Date(asOf).getTime();
      const midnight = new Date(`${today}T00:00:00.000Z`).getTime();
      const createdIn = (fromMs: number) => users.filter((id) => {
        const at = userCreatedAt.get(id);
        if (!at) return false;
        const ms = new Date(at).getTime();
        return ms >= fromMs && ms <= asOfMs;
      }).length;
      return {
        asOf,
        users: {
          total: users.length,
          newToday: createdIn(midnight),
          new7d: createdIn(asOfMs - 7 * 86_400_000),
          new30d: createdIn(asOfMs - 30 * 86_400_000),
          dau: bi.dau, wau: bi.wau, mau: bi.mau,
          retentionD7: bi.retention.d7.cohort > 0 ? bi.retention.d7.rate : null,
        },
        mothers: {
          pregnant: isPregnant ? 1 : 0,
          mothers: hasKids ? 1 : 0,
          both: isPregnant && hasKids ? 1 : 0,
          unknown: !isPregnant && !hasKids ? users.length : Math.max(0, users.length - 1),
        },
        children: computeChildrenStats(
          children.map((c) => ({ gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null })),
          asOf,
        ),
        devices: {
          total: devices.length,
          online: 0,
          watches: devices.filter((d) => d.kind === 'band').length,
          trackers: devices.filter((d) => d.kind === 'tag').length,
          unassigned: devices.filter((d) => d.kind === 'tag' && !d.childId).length,
          // Normalised on both sides, exactly like the query: a device counted
          // as grey-market over punctuation sends somebody hunting a problem
          // that does not exist.
          unregistered: devices.filter((d) => !registry.has(normalizeSerial(d.id))).length,
        },
        cities: cityOf ? [{ city: cityOf, users: 1 }] : [],
        citiesUnknown: cityOf ? Math.max(0, users.length - 1) : users.length,
        commerce: {
          leads: { total: shopLeads.length, new: shopLeads.filter((l) => l.status === 'new').length },
          orders: {
            total: shopOrders.length, new: countStatus('new'), confirmed: countStatus('confirmed'),
            shipped: countStatus('shipped'), delivered: countStatus('delivered'),
            cancelled: countStatus('cancelled'),
          },
          revenueMinor: revenue,
          pipelineMinor: shopOrders
            .filter((o) => o.status === 'new' || o.status === 'confirmed')
            .reduce((t, o) => t + o.totalMinor, 0),
          avgOrderMinor: shipped > 0 ? Math.round(revenue / shipped) : null,
          stock: { units: n(units), retailMinor: retail, costMinor: cost, unitsWithoutCost: unitsNoCost },
          lowStock: (await repository.adminProducts()).filter((p) => p.lowStock).map((p) => p.id),
        },
        course: courseSnapshot(asOf),
      };
    },

    adminAnalytics: async () => {
      let items = 0, linked = 0;
      for (const list of content.values()) {
        items += list.length;
        linked += list.filter((i) => (i.url ?? '').trim().length > 0).length;
      }
      return {
        totalUsers: 1,
        pregnant: profile?.dueDate ? 1 : 0,
        withChildren: children.length > 0 ? 1 : 0,
        devices: devices.length,
        alerts7d: alerts.length,
        // SafetyAlertRow only carries zone transitions today; SOS arrives via
        // the ingest path, so this stays 0 until that is persisted here.
        sosAllTime: 0,
        stageDistribution: stageDistribution(),
        contentStages: content.size,
        contentStageKeys: [...content.keys()],
        contentItems: items,
        contentLinked: linked,
      };
    },

    // ---- Pregnancy calendar overrides (frames 14a / 14b) ----
    //
    // Seeded EMPTY, deliberately. Every other collection here carries demo rows
    // so a screen has something to show, but a seeded override would put words
    // into a clinical calendar that nobody wrote — and the week editor already
    // has 40 weeks to show from the contract. Empty is the honest starting
    // state: nothing has been edited yet.
    pregnancyWeekOverrides: async () =>
      [...pregWeekOverrides.values()]
        .sort((a, b) => a.week - b.week)
        .map((o) => ({ ...o, ru: { ...o.ru }, kk: { ...o.kk }, review: o.review ? { ...o.review } : null })),

    putPregnancyWeekOverride: async (v) => {
      const prev = pregWeekOverrides.get(v.week);
      pregWeekOverrides.set(v.week, {
        week: v.week,
        lengthCm: v.lengthCm,
        hcg: v.hcg,
        ru: { ...v.ru },
        kk: { ...v.kk },
        draft: v.draft,
        review: v.review ? { ...v.review } : null,
        // Increment, exactly like the pg UPSERT. A fake that resets the counter
        // would let the served version go backwards in dev and nowhere else,
        // which is the kind of difference that is found in production.
        rev: (prev?.rev ?? 0) + 1,
        updatedAt: new Date().toISOString(),
        updatedBy: v.updatedBy,
      });
    },

    // ---- Emergency-help overrides (frame 16b → app screen 37) ----
    emergencyHelpOverrides: async () =>
      [...emergencyOverrides.values()]
        .sort((a, b) => a.id.localeCompare(b.id))
        .map((o) => ({ ...o, ru: { ...o.ru }, kk: { ...o.kk }, review: o.review ? { ...o.review } : null })),

    putEmergencyHelpOverride: async (v) => {
      const prev = emergencyOverrides.get(v.id);
      emergencyOverrides.set(v.id, {
        id: v.id,
        severity: v.severity,
        sort: v.sort,
        ru: { ...v.ru },
        kk: { ...v.kk },
        draft: v.draft,
        review: v.review ? { ...v.review } : null,
        // Increment, exactly like the pg UPSERT. A fake that reset the counter
        // would let the served version go backwards in dev and nowhere else,
        // which is the kind of difference that is found in production.
        rev: (prev?.rev ?? 0) + 1,
        updatedAt: new Date().toISOString(),
        updatedBy: v.updatedBy,
      });
    },

    // ---- Vaccination schedule overrides (frames 15 / 15a / 15b) ----
    vaccinationOverrides: async () =>
      [...vaccOverrides.values()]
        .sort((a, b) => a.key.localeCompare(b.key))
        .map((o) => ({ ...o, ru: { ...o.ru }, kk: { ...o.kk }, review: o.review ? { ...o.review } : null })),

    putVaccinationOverride: async (v) => {
      const prev = vaccOverrides.get(v.key);
      const row: VaccinationOverride = {
        key: v.key,
        // Identity, and only settable at creation — exactly like the pg UPSERT,
        // whose ON CONFLICT list omits these three columns. A fake that let a
        // save move `dose` would re-key a row in dev and nowhere else.
        id: prev?.id ?? v.id,
        dose: prev ? prev.dose : v.dose,
        added: prev ? prev.added : v.added,
        atMonth: v.atMonth,
        ru: { ...v.ru },
        kk: { ...v.kk },
        draft: v.draft,
        review: v.review ? { ...v.review } : null,
        // Increment, exactly like the pg UPSERT. A fake that reset the counter
        // would let the served version go backwards in dev and nowhere else,
        // which is the kind of difference that is found in production.
        rev: (prev?.rev ?? 0) + 1,
        updatedAt: new Date().toISOString(),
        updatedBy: v.updatedBy,
      };
      vaccOverrides.set(v.key, row);
      // Written in the same call as the row, because in pg it is one statement
      // and frame 15b is the only record of what the schedule used to say.
      vaccLog.push({
        id: vaccLog.length + 1,
        key: v.key,
        before: prev
          ? {
            key: prev.key, id: prev.id, atMonth: prev.atMonth, dose: prev.dose,
            ru: { ...prev.ru }, kk: { ...prev.kk },
            added: prev.added, draft: prev.draft, review: prev.review,
          }
          : null,
        after: {
          key: row.key, id: row.id, atMonth: row.atMonth, dose: row.dose,
          ru: { ...row.ru }, kk: { ...row.kk },
          added: row.added, draft: row.draft, review: row.review,
        },
        actor: v.updatedBy,
        at: row.updatedAt,
      });
    },

    vaccinationSettings: async () => (vaccSettings ? { ...vaccSettings } : null),

    putVaccinationSettings: async (v) => {
      const before = vaccSettings ? { dueWindowMonths: vaccSettings.dueWindowMonths } : null;
      vaccSettings = {
        dueWindowMonths: v.dueWindowMonths,
        rev: (vaccSettings?.rev ?? 0) + 1,
        updatedAt: new Date().toISOString(),
        updatedBy: v.updatedBy,
      };
      vaccLog.push({
        id: vaccLog.length + 1,
        key: '@settings',
        before,
        after: { dueWindowMonths: v.dueWindowMonths },
        actor: v.updatedBy,
        at: vaccSettings.updatedAt,
      });
    },

    vaccinationScheduleLog: async (limit) =>
      [...vaccLog].reverse().slice(0, limit).map((e) => ({ ...e })),

    vaccinationCoverage: async () => {
      // Same arithmetic as pgRepository's GROUP BY — whole completed months,
      // with the day of the month having to come round — so the two cannot
      // drift on how old a child is.
      const now = new Date();
      const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
      // A yyyy-MM-dd is a DATE; comparing it against `new Date()` mixes a date
      // with a timestamp and lands a child a day — and near a month boundary a
      // whole month — out.
      const asUtc = (s: string): number | null => {
        const [y, m, d] = s.split('-').map(Number);
        return Number.isFinite(y) && Number.isFinite(m) && Number.isFinite(d)
          ? Date.UTC(y, m - 1, d) : null;
      };
      const ages = new Map<number, number>();
      const ticks = new Map<string, Map<number, number>>();
      let withoutDob = 0;
      for (const c of children) {
        const dobMs = c.dateOfBirth ? asUtc(c.dateOfBirth) : null;
        if (dobMs == null || dobMs > today) { withoutDob++; continue; }
        const b = new Date(dobMs), t = new Date(today);
        let months = (t.getUTCFullYear() - b.getUTCFullYear()) * 12
          + (t.getUTCMonth() - b.getUTCMonth());
        if (t.getUTCDate() < b.getUTCDate()) months -= 1;
        months = Math.max(0, months);
        ages.set(months, (ages.get(months) ?? 0) + 1);
        for (const key of vaccines.get(c.id) ?? []) {
          const byAge = ticks.get(key) ?? new Map<number, number>();
          byAge.set(months, (byAge.get(months) ?? 0) + 1);
          ticks.set(key, byAge);
        }
      }
      return {
        childAges: [...ages].map(([ageMonths, n]) => ({ ageMonths, n }))
          .sort((a, b) => a.ageMonths - b.ageMonths),
        ticks: [...ticks].flatMap(([key, byAge]) =>
          [...byAge].map(([ageMonths, n]) => ({ key, ageMonths, n }))),
        childrenWithoutDob: withoutDob,
      };
    },

    pregnancyWeekMotherCounts: async () => {
      // Same arithmetic as pgRepository's GROUP BY, in pregnancy/overrides.ts so
      // the two cannot drift on what "week 22" means.
      //
      // The population is every profile this process holds, plus the seeded demo
      // account when it has not been overwritten — the same set adminListUsers
      // reports. One process cannot produce «312 мам», and it does not pretend
      // to: with one pregnant profile the editor reads «1 мама», which is true.
      const today = utcMidnightOf(new Date());
      const out: Record<number, number> = {};
      const dues: Array<string | null> = [...profiles.values()].map((p) => p.dueDate ?? null);
      if (!profiles.has(DEMO_USER) && profile?.dueDate) dues.push(profile.dueDate);
      for (const due of dues) {
        if (!due) continue;
        const w = gestationalWeekOn(due, today);
        if (w == null) continue;
        out[w] = (out[w] ?? 0) + 1;
      }
      return out;
    },

    // ---- Broadcasts (frame 06 «Маркетинг») ----
    //
    // The audience is assembled from the same rows the rest of this fake
    // serves: profiles (users.locale / users.due_date) and children
    // (children.date_of_birth). One process cannot produce «312 получателей»
    // and does not pretend to — with one seeded mother the panel reads «1», and
    // that number is true.
    listBroadcasts: async (limit) => {
      const delivered = new Map<string, number>();
      for (const d of broadcastDeliveries) {
        delivered.set(d.broadcastId, (delivered.get(d.broadcastId) ?? 0) + 1);
      }
      return [...broadcasts.values()]
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit)
        .map((b) => ({ ...b, segment: { ...b.segment }, delivered: delivered.get(b.id) ?? 0 }));
    },

    saveBroadcast: async (v) => {
      const prev = broadcasts.get(v.id);
      // A published broadcast is on somebody's phone. Editing the row would
      // change what the panel says we sent without changing what we sent.
      if (prev && prev.status === 'published') {
        throw new Error('broadcast_already_published');
      }
      const now = new Date().toISOString();
      broadcasts.set(v.id, {
        id: v.id,
        titleRu: v.titleRu,
        bodyRu: v.bodyRu,
        titleKk: v.titleKk,
        bodyKk: v.bodyKk,
        segment: { ...v.segment },
        status: 'draft',
        createdBy: prev?.createdBy ?? v.createdBy,
        createdAt: prev?.createdAt ?? now,
        updatedAt: now,
        publishedAt: null,
      });
    },

    broadcastAudience: async (segment) => {
      const now = new Date();
      const rows = audienceRows().filter((r) => matchesSegment(r, segment, now));
      const excluded = rows.filter((r) => inWeeklyGap(r.userId, now)).length;
      return { matched: rows.length, excluded };
    },

    publishBroadcast: async (id) => {
      const b = broadcasts.get(id);
      if (!b) return null;
      const now = new Date();
      const matched = audienceRows().filter((r) => matchesSegment(r, b.segment, now));
      // «Не чаще раза в неделю», ACROSS broadcasts — see admin/broadcasts.ts.
      const recipients = matched.filter((r) => !inWeeklyGap(r.userId, now));
      const at = now.toISOString();
      for (const r of recipients) {
        // Idempotent per person, exactly like the composite primary key.
        if (broadcastDeliveries.some((d) => d.broadcastId === id && d.userId === r.userId)) continue;
        broadcastDeliveries.push({ broadcastId: id, userId: r.userId, at });
      }
      b.status = 'published';
      b.publishedAt = at;
      b.updatedAt = at;
      return {
        matched: matched.length,
        excluded: matched.length - recipients.length,
        delivered: recipients.length,
        userIds: recipients.map((r) => r.userId),
      };
    },

    listAnnouncements: async (userId, limit) => {
      const out: AnnouncementRow[] = [];
      for (const d of [...broadcastDeliveries].reverse()) {
        if (d.userId !== userId) continue;
        const b = broadcasts.get(d.broadcastId);
        if (!b || b.status !== 'published') continue;
        out.push({
          id: b.id,
          at: d.at,
          ru: { title: b.titleRu, body: b.bodyRu },
          // Never null on the wire: publication is refused without the Kazakh
          // half, so a published row always has one. The `?? ru` is the belt
          // for a row written before that rule existed.
          kk: { title: b.titleKk ?? b.titleRu, body: b.bodyKk ?? b.bodyRu },
        });
        if (out.length >= limit) break;
      }
      return out;
    },

    // ---- Notifications (frame 25 «Уведомления») ----
    getNotificationPrefs: async (userId) => {
      const own = notificationPrefs.get(userId);
      return {
        ...(own ? { ...own } : DEFAULT_PREFS),
        timezone: userTimezones.get(userId) ?? FALLBACK_TZ,
        // Null when these are the defaults rather than something she chose —
        // the panel counts «сколько мам настроили» off exactly this.
        updatedAt: own?.updatedAt ?? null,
      };
    },
    putNotificationPrefs: async (userId, prefs) => {
      notificationPrefs.set(userId, {
        zoneEvents: prefs.zoneEvents,
        checkIn: prefs.checkIn,
        lowBattery: prefs.lowBattery,
        updates: prefs.updates,
        // Half a window is no window, exactly as the app and the gate treat it.
        quietStart: prefs.quietStart != null && prefs.quietEnd != null ? prefs.quietStart : null,
        quietEnd: prefs.quietStart != null && prefs.quietEnd != null ? prefs.quietEnd : null,
        updatedAt: new Date().toISOString(),
      });
    },
    /// The write side of users.timezone. This map used to be populated by
    /// nothing and only ever deleted, so the fake always answered FALLBACK_TZ
    /// and no HTTP-level test could carry a mother who lives anywhere else.
    setUserTimezone: async (userId, timezone) => {
      userTimezones.set(userId, timezone);
    },
    recordPushDelivery: async (row) => {
      pushDeliveries.push({ ...row, at: new Date().toISOString() });
    },
    pushDeliverySummary: async (days) => {
      const floor = Date.now() - Math.max(1, days) * 86_400_000;
      const rows = pushDeliveries.filter((r) => Date.parse(r.at) >= floor);
      const byKind = new Map<string, PushDeliverySummary['kinds'][number]>();
      for (const r of rows) {
        const k = byKind.get(r.kind) ?? {
          kind: r.kind, attempts: 0, delivered: 0, failed: 0,
          noTokens: 0, held: 0, heldMuted: 0, heldQuiet: 0, errors: 0, dead: 0,
        };
        k.attempts += 1;
        k.delivered += r.sent;
        k.failed += r.failed;
        k.dead += r.dead;
        if (r.heldReason) {
          k.held += 1;
          if (r.heldReason === 'muted') k.heldMuted += 1;
          else k.heldQuiet += 1;
        }
        // «Нет устройства» is not a failure of ours and is counted apart from
        // one: lumping them together turns «она не установила приложение» into
        // «наш пуш сломан».
        if (r.error === 'no_tokens') k.noTokens += 1;
        else if (r.error) k.errors += 1;
        byKind.set(r.kind, k);
      }
      const prefs = [...notificationPrefs.values()];
      return {
        windowDays: days,
        kinds: [...byKind.values()].sort((a, b) => a.kind.localeCompare(b.kind)),
        deadTokens: rows.reduce((n, r) => n + r.dead, 0),
        muted: {
          zoneEvents: prefs.filter((p) => !p.zoneEvents).length,
          checkIn: prefs.filter((p) => !p.checkIn).length,
          lowBattery: prefs.filter((p) => !p.lowBattery).length,
          updates: prefs.filter((p) => !p.updates).length,
          quietHours: prefs.filter((p) => p.quietStart != null && p.quietEnd != null && p.quietStart !== p.quietEnd).length,
          configured: prefs.length,
        },
        lastAt: rows.length ? rows[rows.length - 1].at : null,
      };
    },

    contentCatalog: async () => Object.fromEntries([...content.entries()].map(([k, v]) => [k, v.map((i) => ({ ...i }))])),
    putStageContent: async (stageKey, items) => {
      // An empty list means "this stage has nothing" — remove the key rather
      // than leaving an empty array that reads as content in every count.
      if (items.length === 0) {
        content.delete(stageKey);
      } else {
        content.set(stageKey, items.map((i) => ({ ...i })));
      }
    },

    writeAudit: async (e) => void audit.push({ ...e, target: e.target ?? null, reason: e.reason ?? null, at: new Date().toISOString() }),
    listAudit: async (limit) => {
      const byId = new Map([...staffAccounts.values()].map((a) => [a.id, a]));
      return audit.slice(-limit).reverse().map((e) => ({
        ...e,
        staffName: byId.get(e.staffId)?.displayName ?? null,
        staffPhone: byId.get(e.staffId)?.phone ?? null,
        targetName: e.target ? byId.get(e.target)?.displayName ?? null : null,
      }));
    },

    // ---- Shop ----
    // Bundles included, marked as such and carrying their parts: the storefront
    // has to be able to offer the комплект, and it has no colours of its own.
    //
    // `active` is filtered here exactly as the SQL filters it. It was not, and
    // the fake was therefore more generous than production: a product withdrawn
    // in the panel kept appearing in every test's storefront, so a test could
    // have blessed a shop that shows things nobody can buy.
    shopProducts: async () => markInStock(shopProds
      .slice()
      .filter((p) => p.active ?? true)
      .sort((a, b) => a.sort - b.sort)
      .map((p) => ({
        id: p.id, name: p.name, priceMinor: p.priceMinor, kind: p.kind ?? 'simple',
        variants: shopVars.filter((v) => v.productId === p.id).sort((a, b) => a.sort - b.sort)
          .map((v) => ({ id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock })),
        parts: bundleItems.filter((b) => b.bundleId === p.id).map((b) => ({ partId: b.partId, qty: b.qty })),
        // Catalogue (migration 033). `undefined` on the row means the column is
        // NULL; it must reach the wire as null, not vanish from the JSON.
        nameKk: p.nameKk ?? null,
        descriptionRu: p.descriptionRu ?? null,
        descriptionKk: p.descriptionKk ?? null,
        stage: p.stage ?? null,
        category: p.category ?? null,
        ageMinMonths: p.ageMinMonths ?? null,
        ageMaxMonths: p.ageMaxMonths ?? null,
        photoUrl: p.photoUrl ?? null,
        inStock: false,
      }))),
    placeShopOrder: async (o) => {
      if (!o.items.length) return { ok: false as const, error: 'empty' as const };
      // Two-pass: validate all, then commit — the memory store cannot roll back a
      // partial write, so nothing changes until every line is known good.
      const snap: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number; variant: (typeof shopVars)[number] }> = [];
      const lines: Array<{ productId: string; qty: number }> = [];
      let subtotal = 0;
      for (const it of o.items) {
        const v = shopVars.find((x) => x.id === it.variantId);
        if (!v) return { ok: false as const, error: 'not_found' as const, variantId: it.variantId };
        if (v.stock < it.qty) return { ok: false as const, error: 'out_of_stock' as const, variantId: it.variantId };
        const p = shopProds.find((x) => x.id === v.productId)!;
        subtotal += p.priceMinor * it.qty;
        lines.push({ productId: v.productId, qty: it.qty });
        snap.push({ productName: p.name, color: v.color, qty: it.qty, unitPriceMinor: p.priceMinor, variant: v });
      }
      let discount = bundleDiscountMinor(lines);
      let total = subtotal - discount;

      // Sold as a bundle: the parts are what leaves the warehouse, the PRICE is
      // the bundle's. The lines must really contain the bundle's parts, or
      // "sold as the combo" could be claimed over one tracker and buy the
      // course for 4 900.
      if (o.bundleId) {
        const bundle = shopProds.find((p) => p.id === o.bundleId && p.kind === 'bundle');
        if (!bundle) return { ok: false as const, error: 'not_found' as const, variantId: o.bundleId };
        const parts = bundleItems.filter((x) => x.bundleId === o.bundleId);
        const ordered = new Map<string, number>();
        for (const l of lines) ordered.set(l.productId, (ordered.get(l.productId) ?? 0) + l.qty);
        const complete = parts.length > 0 && parts.every((p) => (ordered.get(p.partId) ?? 0) >= p.qty);
        if (!complete) return { ok: false as const, error: 'incomplete_bundle' as const, variantId: o.bundleId };
        total = bundle.priceMinor;
        // A "discount" only when it is one: the комплект costs MORE than its
        // parts because it carries the course.
        discount = Math.max(0, subtotal - total);
      }
      const id = randomUUID();
      // The sale goes in the ledger with the stock it took. Without it, sales
      // were the one movement that left no trace: the count fell and the
      // history said nothing, so the two disagreed by everything ever sold.
      for (const s of snap) {
        s.variant.stock -= s.qty;
        stockMoves.push({
          id: stockMoves.length + 1, variantId: s.variant.id, delta: -s.qty,
          reason: 'sale', note: null, staffId: null, orderId: id,
          at: new Date().toISOString(),
        });
      }
      shopOrders.push({
        id, customerName: o.customerName, phone: o.phone, city: o.city, address: o.address,
        note: o.note ?? null, totalMinor: total, discountMinor: discount, status: 'new', createdAt: new Date().toISOString(),
        bundleId: o.bundleId ?? null, phoneNormalized: normalizePhone(o.phone),
        items: snap.map((s) => ({ productName: s.productName, color: s.color, qty: s.qty, unitPriceMinor: s.unitPriceMinor })),
      });
      return { ok: true as const, id, totalMinor: total, discountMinor: discount };
    },
    // ---- Catalogue (frames 08 / 08a / 08b) ----
    updateProduct: async (id, patch) => {
      const p = shopProds.find((x) => x.id === id);
      if (!p) return;
      // Only the keys PRESENT, matching the SQL: saving one tab of the product
      // card must not blank another.
      for (const k of Object.keys(patch) as Array<keyof typeof patch>) {
        (p as unknown as Record<string, unknown>)[k] = patch[k] as unknown;
      }
    },
    listShopCategories: async () =>
      [...shopCategories].sort((a, b) => a.sort - b.sort || a.nameRu.localeCompare(b.nameRu)),
    upsertShopCategory: async (c) => {
      const i = shopCategories.findIndex((x) => x.id === c.id);
      if (i >= 0) shopCategories[i] = { ...c };
      else shopCategories.push({ ...c });
    },
    deleteShopCategory: async (id) => {
      if (shopProds.some((p) => p.category === id)) return false;
      const i = shopCategories.findIndex((x) => x.id === id);
      if (i >= 0) shopCategories.splice(i, 1);
      return true;
    },
    adminShopVariants: async () => shopVars.map((v) => ({
      id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock,
      productId: v.productId, productName: shopProds.find((p) => p.id === v.productId)?.name ?? v.productId,
    })),
    setShopVariantStock: async (variantId, stock, by) => {
      const v = shopVars.find((x) => x.id === variantId);
      if (!v) return;
      const target = Math.max(0, Math.trunc(stock));
      const delta = target - v.stock;
      v.stock = target;
      // The ledger gets the delta even for an absolute set, so the running
      // total and the history cannot drift apart.
      if (delta !== 0) {
        stockMoves.push({
          id: stockMoves.length + 1, variantId, delta, reason: 'correction',
          note: by?.note ?? null, staffId: by?.staffId ?? null, orderId: null,
          at: new Date().toISOString(),
        });
      }
    },

    // ---- The Ма!Ма! course ----
    courseLessons: async (course, publishedOnly) =>
      lessons
        .filter((l) => l.course === course && (!publishedOnly || l.published))
        .sort((a, b) => a.sort - b.sort || a.createdAt.localeCompare(b.createdAt)),

    upsertCourseLesson: async (l) => {
      const existing = l.id ? lessons.find((x) => x.id === l.id) : undefined;
      if (existing) {
        Object.assign(existing, {
          titleRu: l.titleRu, titleKk: l.titleKk ?? null, youtubeUrl: l.youtubeUrl,
          summaryRu: l.summaryRu ?? null, summaryKk: l.summaryKk ?? null,
          sort: l.sort ?? existing.sort, published: l.published ?? existing.published,
        });
        return { id: existing.id };
      }
      const row = {
        id: randomUUID(), course: l.course, titleRu: l.titleRu,
        titleKk: l.titleKk ?? null, youtubeUrl: l.youtubeUrl,
        summaryRu: l.summaryRu ?? null, summaryKk: l.summaryKk ?? null,
        sort: l.sort ?? 0, published: l.published ?? false,
        createdAt: new Date().toISOString(),
      };
      lessons.push(row);
      return { id: row.id };
    },

    courseLessonWatchers: async (lessonId) =>
      [...progress.keys()].filter((k) => k.endsWith('|' + lessonId)).length,

    deleteCourseLesson: async (id) => {
      const i = lessons.findIndex((x) => x.id === id);
      if (i >= 0) lessons.splice(i, 1);
      // The real table cascades. A fake that kept orphan progress rows would
      // hide a deleted lesson still counting towards somebody's "12 started".
      for (const k of [...progress.keys()]) {
        if (k.endsWith('|' + id)) progress.delete(k);
      }
    },

    courseProgress: async (phone) =>
      [...progress.values()].filter((p) => p.phone === phone).map(({ phone: _p, ...rest }) => rest),

    saveCourseProgress: async (p) => {
      // Postgres rejects a non-UUID lesson id outright; a fake that accepted
      // one would let a test pass against production behaviour it never has.
      if (!UUID_RE.test(p.lessonId)) return;
      const key = p.phone + '|' + p.lessonId;
      const now = new Date().toISOString();
      const seconds = Math.max(0, Math.round(p.positionSeconds));
      const duration = p.durationSeconds == null
        ? null : Math.max(0, Math.round(p.durationSeconds));
      const existing = progress.get(key);
      if (!existing) {
        progress.set(key, {
          phone: p.phone, lessonId: p.lessonId, positionSeconds: seconds,
          durationSeconds: duration, completed: p.completed ?? false, updatedAt: now,
        });
        return;
      }
      // Same three rules as the ON CONFLICT clause: the position never goes
      // backwards, a known duration is never replaced by null, and completed
      // never returns to false.
      existing.positionSeconds = Math.max(existing.positionSeconds, seconds);
      existing.durationSeconds = duration ?? existing.durationSeconds;
      existing.completed = existing.completed || (p.completed ?? false);
      existing.updatedAt = now;
    },

    courseProgressSummary: async (limit) => {
      const byPhone = new Map<string, {
        phone: string; started: number; completed: number;
        lastLessonId: string | null; lastLessonTitle: string | null; lastAt: string;
      }>();
      for (const p of progress.values()) {
        const row = byPhone.get(p.phone) ?? {
          phone: p.phone, started: 0, completed: 0,
          lastLessonId: null, lastLessonTitle: null, lastAt: '',
        };
        row.started += 1;
        if (p.completed) row.completed += 1;
        if (p.updatedAt >= row.lastAt) {
          row.lastAt = p.updatedAt;
          row.lastLessonId = p.lessonId;
          row.lastLessonTitle = lessons.find((l) => l.id === p.lessonId)?.titleRu ?? null;
        }
        byPhone.set(p.phone, row);
      }
      return [...byPhone.values()]
        .sort((a, b) => b.lastAt.localeCompare(a.lastAt))
        .slice(0, limit);
    },

    // ---- Entitlements ----
    hasEntitlement: async (phone, feature) => entitlements.has(phone + '|' + feature),
    grantEntitlement: async (e) => {
      const key = e.phone + '|' + e.feature;
      // Idempotent, and the FIRST grant keeps its provenance: re-granting must
      // not overwrite who gave it and why.
      if (entitlements.has(key)) return;
      entitlements.set(key, {
        phone: e.phone, feature: e.feature, orderId: e.orderId ?? null,
        grantedBy: e.grantedBy ?? null, note: e.note ?? null,
        at: new Date().toISOString(),
      });
    },
    revokeEntitlement: async (phone, feature) => void entitlements.delete(phone + '|' + feature),
    listEntitlements: async (feature, limit) =>
      [...entitlements.values()].filter((x) => x.feature === feature).slice(-limit).reverse(),

    // ---- Inventory ----
    adminProducts: async () => {
      const products: InventoryProduct[] = shopProds.map((p) => {
        const variants = shopVars
          .filter((v) => v.productId === p.id)
          .map((v) => ({ id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock }));
        return {
          id: p.id, name: p.name, sku: p.sku ?? null, priceMinor: p.priceMinor,
          costMinor: p.costMinor ?? null, kind: p.kind ?? 'simple',
          active: p.active ?? true, sort: p.sort,
          lowStockThreshold: p.lowStockThreshold ?? 3,
          stock: variants.reduce((n, v) => n + v.stock, 0),
          lowStock: false, variants,
          nameKk: p.nameKk ?? null, stage: p.stage ?? null, category: p.category ?? null,
          descriptionRu: p.descriptionRu ?? null, descriptionKk: p.descriptionKk ?? null,
          ageMinMonths: p.ageMinMonths ?? null, ageMaxMonths: p.ageMaxMonths ?? null,
          photoUrl: p.photoUrl ?? null,
          seoSlug: p.seoSlug ?? null, seoTitle: p.seoTitle ?? null,
          seoDescription: p.seoDescription ?? null,
        };
      });
      // A bundle can be assembled as many times as its scarcest part allows.
      const stockOf = new Map(products.map((p) => [p.id, p.stock]));
      for (const p of products) {
        if (p.kind !== 'bundle') continue;
        const mine = bundleItems.filter((b) => b.bundleId === p.id);
        p.stock = mine.length === 0
          ? 0
          : Math.min(...mine.map((b) => Math.floor((stockOf.get(b.partId) ?? 0) / b.qty)));
      }
      for (const p of products) p.lowStock = p.active && p.stock <= p.lowStockThreshold;
      return products;
    },

    upsertProduct: async (p) => {
      const existing = shopProds.find((x) => x.id === p.id);
      const row = {
        id: p.id, name: p.name, priceMinor: Math.max(0, Math.trunc(p.priceMinor)),
        costMinor: p.costMinor ?? null, sku: p.sku ?? null, kind: p.kind ?? 'simple',
        lowStockThreshold: p.lowStockThreshold ?? 3, active: p.active ?? true,
        sort: p.sort ?? shopProds.length + 1,
      };
      if (existing) Object.assign(existing, row);
      else shopProds.push(row);
    },

    bundleParts: async (bundleId) =>
      bundleItems.filter((b) => b.bundleId === bundleId).map((b) => ({
        partId: b.partId, qty: b.qty,
        partName: shopProds.find((p) => p.id === b.partId)?.name ?? b.partId,
      })),

    setBundleParts: async (bundleId, parts) => {
      for (let i = bundleItems.length - 1; i >= 0; i--) {
        if (bundleItems[i].bundleId === bundleId) bundleItems.splice(i, 1);
      }
      for (const part of parts) {
        if (part.partId === bundleId) continue; // a bundle cannot contain itself
        bundleItems.push({ bundleId, partId: part.partId, qty: Math.max(1, Math.trunc(part.qty)) });
      }
    },

    moveStock: async (m) => {
      const delta = Math.trunc(m.delta);
      if (delta === 0) return { ok: false as const, error: 'insufficient_stock' as const };
      const v = shopVars.find((x) => x.id === m.variantId);
      if (!v) return { ok: false as const, error: 'unknown_variant' as const };
      const next = v.stock + delta;
      // The ledger must never describe an impossible state.
      if (next < 0) return { ok: false as const, error: 'insufficient_stock' as const };
      v.stock = next;
      stockMoves.push({
        id: stockMoves.length + 1, variantId: m.variantId, delta, reason: m.reason,
        note: m.note ?? null, staffId: m.staffId ?? null, orderId: m.orderId ?? null,
        at: new Date().toISOString(),
      });
      return { ok: true as const, stock: next };
    },

    soldUnitsSince: async (sinceIso) => {
      const out: Record<string, number> = {};
      for (const m of stockMoves) {
        if (m.reason !== 'sale' || m.at < sinceIso) continue;
        const productId = shopVars.find((v) => v.id === m.variantId)?.productId;
        if (!productId) continue;
        // The ledger stores a sale as a negative delta; callers want a count.
        out[productId] = (out[productId] ?? 0) + Math.max(0, -m.delta);
      }
      return out;
    },

    stockMoves: async (limit, variantId, sinceIso) =>
      stockMoves
        // Filtered BEFORE the slice, like the SQL's WHERE runs before its
        // LIMIT: filtering the last hundred rows would return "today's moves"
        // that silently stop at yesterday on a busy day.
        .filter((m) => (!variantId || m.variantId === variantId)
          && (!sinceIso || m.at >= sinceIso))
        .slice(-limit)
        .reverse()
        .map((m) => {
          const v = shopVars.find((x) => x.id === m.variantId);
          return {
            ...m,
            color: v?.color ?? '',
            productName: shopProds.find((p) => p.id === v?.productId)?.name ?? '',
          };
        }),
    // ---- Поставки (migration 045, frames 07a / 07g) ----
    listSuppliers: async (): Promise<Supplier[]> => suppliers.map((s) => ({ ...s })),

    upsertSupplier: async (s) => {
      const name = s.name.trim();
      const byName = suppliers.find((x) => x.name.toLowerCase() === name.toLowerCase());
      // lower(name) is UNIQUE in Postgres. Matching the same way here is the
      // difference between a fake that agrees with production and one that
      // lets a test create two «Shenzhen Ltd» the real database refuses.
      const existing = s.id ? suppliers.find((x) => x.id === s.id) : byName;
      if (existing) {
        // Renaming onto somebody else's name is what the unique index refuses.
        // Without this the memory repo happily produces two rows called «Beta»
        // and every test written against it passes on a state production
        // cannot hold.
        if (byName && byName !== existing) return { ok: false as const, error: 'name_taken' as const };
        existing.name = name;
        existing.contact = s.contact ?? null;
        existing.leadTimeDays = s.leadTimeDays ?? null;
        // Absent means "leave it alone", exactly as the pg UPDATE's
        // COALESCE($5, active) does: the panel's add form sends no `active`,
        // and it must not resurrect an archived supplier.
        if (s.active != null) existing.active = s.active;
        return { ok: true as const, id: existing.id };
      }
      // An id that matches nothing falls through to the name, and then to a
      // fresh row with a NEW id — pg's UPDATE ... WHERE id = $1 affects no rows
      // and its INSERT mints its own uuid. Keeping the caller's id here would
      // make the fake accept a state production never produces.
      if (byName) {
        byName.name = name;
        byName.contact = s.contact ?? null;
        byName.leadTimeDays = s.leadTimeDays ?? null;
        if (s.active != null) byName.active = s.active;
        return { ok: true as const, id: byName.id };
      }
      const id = randomUUID();
      suppliers.push({
        id, name, contact: s.contact ?? null,
        leadTimeDays: s.leadTimeDays ?? null, active: s.active ?? true,
        createdAt: new Date().toISOString(),
      });
      return { ok: true as const, id };
    },

    listPurchaseOrders: async (limit): Promise<PurchaseOrder[]> =>
      purchaseOrders.slice(-limit).reverse().map(hydratePurchaseOrder),

    purchaseOrderById: async (id): Promise<PurchaseOrder | null> => {
      const po = purchaseOrders.find((p) => p.id === id);
      return po ? hydratePurchaseOrder(po) : null;
    },

    createPurchaseOrder: async (po) => {
      // All or nothing. Half an order looks like a placed shipment.
      if (!po.items.length) return { ok: false as const, error: 'no_items' as const };
      for (const it of po.items) {
        if (!shopVars.some((v) => v.id === it.variantId)) {
          return { ok: false as const, error: 'unknown_variant' as const };
        }
      }
      const now = new Date().toISOString();
      const id = randomUUID();
      purchaseOrders.push({
        id, supplierId: po.supplierId ?? null, status: 'draft',
        placedAt: null, expectedAt: po.expectedAt ?? null, note: po.note ?? null,
        createdBy: po.createdBy ?? null, createdAt: now, updatedAt: now,
      });
      // PRIMARY KEY (po_id, variant_id): the same colour twice in one order is
      // one line, summed, not two rows Postgres would refuse outright.
      for (const it of po.items) {
        const line = purchaseOrderItems.find((x) => x.poId === id && x.variantId === it.variantId);
        if (line) { line.qtyOrdered += Math.trunc(it.qtyOrdered); continue; }
        purchaseOrderItems.push({
          poId: id, variantId: it.variantId, qtyOrdered: Math.trunc(it.qtyOrdered),
          unitCostMinor: it.unitCostMinor ?? null, qtyReceived: 0, receivedAt: null,
        });
      }
      return { ok: true as const, id };
    },

    setPurchaseOrderStatus: async (id, status) => {
      const po = purchaseOrders.find((p) => p.id === id);
      if (!po) return false;
      po.status = status;
      // The first half of the pair that will one day measure a real lead time.
      if (status === 'placed' && !po.placedAt) po.placedAt = new Date().toISOString();
      po.updatedAt = new Date().toISOString();
      return true;
    },

    receivePurchaseOrderLine: async (poId, variantId, qtyReceived) => {
      const po = purchaseOrders.find((p) => p.id === poId);
      const line = purchaseOrderItems.find((x) => x.poId === poId && x.variantId === variantId);
      if (!po || !line) return { ok: false, status: po?.status ?? null, qtyOrdered: null };
      line.qtyReceived += Math.max(0, Math.trunc(qtyReceived));
      // Closed even when short: the shortfall is already a claim on the receipt,
      // and holding the order open over two missing units would show them as
      // "in transit" for ever.
      line.receivedAt = new Date().toISOString();
      const open = purchaseOrderItems.filter((x) => x.poId === poId && !x.receivedAt);
      if (!open.length && po.status !== 'cancelled') po.status = 'received';
      po.updatedAt = new Date().toISOString();
      return { ok: true, status: po.status, qtyOrdered: line.qtyOrdered };
    },

    inTransitByVariant: async () => {
      const out: Record<string, number> = {};
      const placed = new Set(purchaseOrders.filter((p) => p.status === 'placed').map((p) => p.id));
      for (const it of purchaseOrderItems) {
        // A draft is not on the water, a cancelled order is not on the water,
        // and a closed line has already landed.
        if (!placed.has(it.poId) || it.receivedAt) continue;
        out[it.variantId] = (out[it.variantId] ?? 0) + it.qtyOrdered;
      }
      return out;
    },

    addShopVariant: async (productId, color, colorHex, stock) => {
      const existing = shopVars.find((v) => v.productId === productId && v.color === color);
      if (existing) { existing.colorHex = colorHex; existing.stock = Math.max(0, Math.trunc(stock)); return; }
      shopVars.push({ id: randomUUID(), productId, color, colorHex, stock: Math.max(0, Math.trunc(stock)), sort: shopVars.length });
    },
    adminShopOrders: async (limit) => shopOrders.slice(-limit).reverse().map((o) => ({ ...o, status: o.status as ShopOrderStatus })),

    adminShopOrderPage: async ({ limit, offset, status }) => {
      // Newest first, like `ORDER BY created_at DESC`. The tie-break on
      // insertion order is not cosmetic: a test that places three orders in one
      // millisecond would otherwise page them in an order that has nothing to
      // do with what Postgres returns, and the paging test would be testing the
      // fake.
      const newestFirst = shopOrders
        .map((o, i) => ({ o, i }))
        .sort((a, b) => b.o.createdAt.localeCompare(a.o.createdAt) || b.i - a.i)
        .map((x) => x.o);

      const counts: Record<ShopOrderStatus, number> = {
        new: 0, confirmed: 0, shipped: 0, delivered: 0, cancelled: 0,
      };
      // Over EVERY order, not the filtered set: these numbers sit on the filter
      // chips, and a counter that changes when you click it is worthless.
      for (const o of shopOrders) {
        counts[o.status as ShopOrderStatus] = (counts[o.status as ShopOrderStatus] ?? 0) + 1;
      }

      const matching = status ? newestFirst.filter((o) => o.status === status) : newestFirst;
      const from = Math.max(0, Math.trunc(offset));
      return {
        orders: matching.slice(from, from + limit).map((o) => ({ ...o, status: o.status as ShopOrderStatus })),
        total: matching.length,
        counts,
      };
    },

    shopOrderById: async (id) => {
      const o = shopOrders.find((x) => x.id === id);
      return o ? { ...o, status: o.status as ShopOrderStatus } : null;
    },

    shopOrderEvents: async (orderId) => {
      const byId = new Map([...staffAccounts.values()].map((a) => [a.id, a]));
      return shopOrderEventRows
        .filter((e) => e.orderId === orderId)
        .map((e) => ({
          id: e.id,
          orderId: e.orderId,
          fromStatus: e.fromStatus as ShopOrderStatus | null,
          toStatus: e.toStatus as ShopOrderStatus,
          staffId: e.staffId,
          // Same rule as listAudit: the name where we have it, the id kept
          // either way, and a removed account does not delete the entry.
          staffName: (e.staffId ? byId.get(e.staffId)?.displayName : null) ?? null,
          at: e.at,
        }));
    },
    shopOrdersByPhone: async (phone, limit) =>
      shopOrders
        // phoneNormalized, like the pg query. Filtering on the raw `phone`
        // would make this fake answer where Postgres answers nothing, and the
        // screen would pass its tests and show an empty list in production.
        .filter((o) => o.phoneNormalized === phone)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit)
        .map((o) => ({ ...o, status: o.status as ShopOrderStatus })),
    setShopOrderStatus: async (orderId, status, staffId) => {
      const o = shopOrders.find((x) => x.id === orderId);
      if (!o) return;
      const was = o.status;
      o.status = status;

      // The timeline row, written with the move (migration 039). Only on a real
      // transition — re-selecting the status a row already has would fill frame
      // 03 with «Отправлен → Отправлен».
      if (was !== status) {
        shopOrderEventRows.push({
          id: shopOrderEventRows.length + 1,
          orderId,
          fromStatus: was,
          toStatus: status,
          staffId: staffId ?? null,
          at: new Date().toISOString(),
        });
      }

      // What the sale promised is handed over when the goods are — not when the
      // order is placed. A 'new' order is a promise that may never be
      // collected; unlocking a 40 000 ₸ course on one would be giving it away.
      if ((status === 'shipped' || status === 'delivered') && was !== 'shipped' && was !== 'delivered') {
        const bundle = o.bundleId ? shopProds.find((p) => p.id === o.bundleId) : undefined;
        const phone = o.phoneNormalized ?? normalizePhone(o.phone);
        if (bundle?.grantsFeature && phone) {
          const key = phone + '|' + bundle.grantsFeature;
          if (!entitlements.has(key)) {
            entitlements.set(key, {
              phone, feature: bundle.grantsFeature, orderId, grantedBy: null,
              note: 'выдано автоматически при отправке заказа', at: new Date().toISOString(),
            });
          }
        }
      }

      // Cancelling puts the goods back on the shelf. Only on the transition
      // INTO cancelled, so cancelling twice cannot return the stock twice.
      if (status === 'cancelled' && was !== 'cancelled') {
        for (const it of o.items) {
          const v = shopVars.find((x) => x.color === it.color
            && shopProds.find((p) => p.id === x.productId)?.name === it.productName);
          if (!v) continue;
          v.stock += it.qty;
          stockMoves.push({
            id: stockMoves.length + 1, variantId: v.id, delta: it.qty,
            reason: 'return', note: 'заказ отменён', staffId: null, orderId,
            at: new Date().toISOString(),
          });
        }
      }
    },

    recordShopLead: async (lead) => {
      const id = randomUUID();
      shopLeads.push({
        id, customerName: lead.customerName, phone: lead.phone,
        package: lead.package ?? '', locale: lead.locale ?? 'ru',
        status: 'new', createdAt: new Date().toISOString(),
      });
      return { id };
    },
    adminShopLeads: async (limit) => shopLeads.slice(-limit).reverse().map((l) => ({ ...l })),
    setShopLeadStatus: async (leadId, status) => {
      const l = shopLeads.find((x) => x.id === leadId);
      if (l) l.status = status;
    },

    getShopSettings: async () => Object.fromEntries(shopSettings),
    setShopSettings: async (patch) => {
      for (const [k, v] of Object.entries(patch)) shopSettings.set(k, v ?? '');
    },

    listDailyAudio: async (track) =>
      [...dailyAudio.values()]
        .filter((a) => a.track === track)
        .sort((a, b) => a.day - b.day || a.locale.localeCompare(b.locale))
        .map((a) => ({ track: a.track as 'pregnancy' | 'child', day: a.day, locale: a.locale as 'ru' | 'kk', title: a.title, mime: a.mime, size: a.bytes.length, updatedAt: a.updatedAt })),
    getProductPhoto: async (productId, color) => {
      const hit = productPhotos.get(`${productId}|${color ?? ''}`);
      return hit ? { mime: hit.mime, bytes: hit.bytes } : null;
    },
    listProductPhotos: async () => [...productPhotos.entries()]
      .map(([k, v]) => {
        const [productId, color] = k.split('|');
        return { productId, color, uploadedAt: v.uploadedAt };
      })
      .sort((a, b) => (a.productId + a.color).localeCompare(b.productId + b.color)),
    putProductPhoto: async (p) => {
      // Replaces, never accumulates — the same contract as the pg ON CONFLICT.
      productPhotos.set(`${p.productId}|${p.color ?? ''}`, {
        mime: p.mime, bytes: p.bytes, uploadedAt: new Date().toISOString(),
      });
    },
    deleteProductPhoto: async (productId, color) => {
      productPhotos.delete(`${productId}|${color ?? ''}`);
    },
    getDailyAudio: async (track, day, locale) => {
      const a = dailyAudio.get(`${track}|${day}|${locale}`);
      return a ? { mime: a.mime, bytes: a.bytes } : null;
    },
    upsertDailyAudio: async (a) => {
      dailyAudio.set(`${a.track}|${a.day}|${a.locale}`, { track: a.track, day: a.day, locale: a.locale, title: a.title, mime: a.mime, bytes: a.bytes, updatedAt: new Date().toISOString() });
    },
    deleteDailyAudio: async (track, day, locale) => void dailyAudio.delete(`${track}|${day}|${locale}`),
  };
  return repository;
}
