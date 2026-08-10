/**
 * In-memory Repository — lets the backend boot and serve real requests WITHOUT a
 * Postgres/Timescale/PostGIS stack, for local dev and demos on test data.
 * Selected in index.ts when USE_MEMORY_DB=true (or no DATABASE_URL). Not for
 * production: state lives in process memory and is lost on restart.
 */

import { randomBytes, randomUUID, scryptSync } from 'node:crypto';
import type { ContentItemRow, Repository, StaffAccount, SleepNight, CryRow, WeightRow, KickSessionRow, ContractionSessionRow, MedicalIdRow, NewbornEventRow, GrowthRow, DoseRow, DayLogRow, SafetyAlertRow, ProfileRow, ShopOrderStatus, ShopLeadLocale, ShopLeadStatus, InventoryProduct, StockMoveReason, CourseLesson, CourseProgress, DeviceRegistryRow, ProductStage, ShopCategoryRow, SupportTicketRow, SupportReplyRow, SupportTemplateRow } from './repository';
import { bundleDiscountMinor } from './repository';
import { normalizePhone } from '../phone.js';
import type { BpCalibration, ChildLocationFix, Geofence, GeofenceEvent } from '@fcs/shared';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { MAX_CODE_ATTEMPTS } from '../routes/phoneAuth.js';
import { normalizeSerial } from '../deviceSerial.js';
import { computeChildrenStats } from '../analytics/childStats.js';
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
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null; userId: string }> = [];

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
    },
  ];
  const replies: SupportReplyRow[] = [];
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
      id: 'staff-dev',
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
  const cryResults: CryRow[] = [];
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
  const alerts: SafetyAlertRow[] = [];
  /** Profiles by user id — what the pg repository stores on `users`. */
  const profiles = new Map<string, ProfileRow>();
  let profile: ProfileRow | null = {
    displayName: 'Aigerim',
    phone: '+77001112233',
    dueDate: null,
    locale: 'ru-KZ',
    // Seeded as null on purpose: declining these is the common case, and the
    // back-office has to render "not provided" rather than an empty cell.
    birthDate: null,
    city: null,
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
  const batteryByDevice = new Map<string, number>();
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
  type ShopOrderRow = { bundleId?: string | null; phoneNormalized?: string; id: string; customerName: string; phone: string; city: string; address: string; note: string | null; totalMinor: number; discountMinor: number; status: string; createdAt: string; items: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number }> };
  const shopOrders: ShopOrderRow[] = [];
  type ShopLeadRow = { id: string; customerName: string; phone: string; package: string; locale: ShopLeadLocale; status: ShopLeadStatus; createdAt: string };
  const shopLeads: ShopLeadRow[] = [];
  type AudioRow = { track: string; day: number; locale: string; title: string | null; mime: string; bytes: Buffer; updatedAt: string };
  const dailyAudio = new Map<string, AudioRow>(); // key: `${track}|${day}|${locale}`
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
      const id = `staff-${staffAccounts.size + 1}`;
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
    listDevices: async (userId) =>
      devices.filter((d) => d.userId === userId).map(({ userId: _u, ...d }) => ({ ...d })),
    createDevice: async (userId, d) => {
      // A device id is physical: the same tracker registered twice is one
      // tracker. pg does this with ON CONFLICT (user_id, ble_mac) DO NOTHING,
      // and without it here a re-sync doubled the fleet.
      if (devices.some((x) => x.userId === userId && x.id === d.id)) return;
      devices.push({ ...d, childId: d.childId ?? null, userId });
    },
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
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
    listGeofenceEvents: async (childId, limit) =>
      events.filter((e) => e.childId === childId).slice(-limit).reverse(),
    // Sleep
    recordSleep: async (_u, s) => {
      const i = sleep.findIndex((x) => x.night === s.night);
      if (i >= 0) sleep[i] = s; else sleep.push(s);
    },
    listSleep: async (_u, limit) => [...sleep].sort((a, b) => b.night.localeCompare(a.night)).slice(0, limit),
    // Baby cry-analysis history
    recordCry: async (_u, c) => {
      const i = cryResults.findIndex((x) => x.at === c.at);
      if (i >= 0) cryResults[i] = c; else cryResults.push(c);
    },
    listCry: async (_u, limit) => [...cryResults].sort((a, b) => b.at.localeCompare(a.at)).slice(0, limit),
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
    // Safety alerts
    // ---- Support (frame 12) ----
    listSupportTickets: async (limit) =>
      [...tickets].sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, limit),
    getSupportTicket: async (id) => tickets.find((t) => t.id === id) ?? null,
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
    listSupportTemplates: async () => [...supportTemplates].sort((a, b) => a.sort - b.sort),

    recordAlert: async (_u, a) => void alerts.unshift(a),
    listAlerts: async (_u, limit) => alerts.slice(0, limit),
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
          doctorPhone: null, avgCycleLength: null, avgPeriodLength: null,
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
      devicesOnline: devices.length,
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
      return rows.map((r) => {
        const userId = String(r.userId ?? DEMO_USER);
        const at = String(r.recordedAt ?? '');
        const id = `${userId}|${at}`; // stable per emergency metric
        const ack = emergencyAcks.get(id);
        return {
          id,
          userId,
          displayName: profile?.displayName ?? 'Ana-Bala user',
          code: 'EMERGENCY',
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
    adminListUsers: async () => {
      // Surface each user's latest reading in the list, like the pg LATERAL:
      // the time (the "last measurement" column) and its triage severity.
      const mine = (healthRows as Array<Record<string, unknown>>).filter((r) => r.userId === DEMO_USER);
      const last = mine[mine.length - 1];
      return {
        total: 1,
        users: [{
          id: DEMO_USER, displayName: profile?.displayName ?? '', phone: profile?.phone ?? null, dueDate: profile?.dueDate ?? null,
          lastMetricAt: last ? String(last.recordedAt) : null,
          latestSeverity: last ? (last.triageSeverity as string) : null,
        }],
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
          batteryPct: batteryByDevice.get(d.id) ?? null,
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
      devices.slice(0, limit).map((d) => ({
        id: d.id,
        name: d.name,
        kind: d.kind,
        // The device's real owner, not a constant. Answering DEMO_USER for
        // every row made the fleet view's "whose device is this" column
        // fiction, and fiction that always agrees with the code.
        userId: d.userId,
        displayName: userNames.get(d.userId) ?? profile?.displayName ?? '',
        childName: children.find((c) => c.id === d.childId)?.name ?? null,
        batteryPct: batteryByDevice.get(d.id) ?? null,
        lastSeen: null,
      })),

    adminSafetyEvents: async (limit) =>
      alerts.slice(0, limit).map((a) => ({
        userId: DEMO_USER,
        displayName: profile?.displayName ?? '',
        childName: children.find((c) => c.id === a.childId)?.name ?? '',
        kind: a.kind,
        zoneName: a.zoneName,
        at: a.at,
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
      cryResults.length = 0;
      dayLogs.clear();
      alerts.length = 0;
      batteryByDevice.clear();
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
      return {
        asOf,
        users: {
          total: users.length,
          newToday: 0, new7d: 0, new30d: 0,
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
    shopProducts: async () => shopProds
      .slice()
      .sort((a, b) => a.sort - b.sort)
      .map((p) => ({
        id: p.id, name: p.name, priceMinor: p.priceMinor, kind: p.kind ?? 'simple',
        variants: shopVars.filter((v) => v.productId === p.id).sort((a, b) => a.sort - b.sort)
          .map((v) => ({ id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock })),
        parts: bundleItems.filter((b) => b.bundleId === p.id).map((b) => ({ partId: b.partId, qty: b.qty })),
      })),
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

    stockMoves: async (limit, variantId) =>
      stockMoves
        .filter((m) => !variantId || m.variantId === variantId)
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
    addShopVariant: async (productId, color, colorHex, stock) => {
      const existing = shopVars.find((v) => v.productId === productId && v.color === color);
      if (existing) { existing.colorHex = colorHex; existing.stock = Math.max(0, Math.trunc(stock)); return; }
      shopVars.push({ id: randomUUID(), productId, color, colorHex, stock: Math.max(0, Math.trunc(stock)), sort: shopVars.length });
    },
    adminShopOrders: async (limit) => shopOrders.slice(-limit).reverse().map((o) => ({ ...o, status: o.status as ShopOrderStatus })),
    shopOrdersByPhone: async (phone, limit) =>
      shopOrders
        // phoneNormalized, like the pg query. Filtering on the raw `phone`
        // would make this fake answer where Postgres answers nothing, and the
        // screen would pass its tests and show an empty list in production.
        .filter((o) => o.phoneNormalized === phone)
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, limit)
        .map((o) => ({ ...o, status: o.status as ShopOrderStatus })),
    setShopOrderStatus: async (orderId, status) => {
      const o = shopOrders.find((x) => x.id === orderId);
      if (!o) return;
      const was = o.status;
      o.status = status;

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
