/**
 * Repository interface — the single seam between business logic and Postgres.
 * Handlers depend on THIS, not on `pg`, so they are testable with fakes.
 * A thin pg-backed implementation sketch lives in pgRepository.ts.
 */

import type {
  BandTelemetry,
  BpCalibration,
  ChildLocationFix,
  Geofence,
  GeofenceEvent,
  TriageSeverity,
} from '@fcs/shared';
import type { BiMetrics } from '../analytics/biMetrics.js';
import type { SosOutcome } from '../safety/dayHistory.js';
import type { BroadcastSegment } from '../admin/broadcasts.js';
import type {
  VaccinationOverride,
  VaccinationSettings,
  VaccineText as VaccineTextRow,
} from '../vaccination/overrides.js';
import type { VaccinationCoverageData } from '../vaccination/coverage.js';
import type { CryThresholdRow } from '../cry/settings.js';
import type { HoldReason, NotificationPrefs, PushKind } from '../notifications/gate.js';
import type { StoredEmergencyReading } from '../emergency/episode.js';
export type { StoredEmergencyReading };

export type { BiMetrics };
export type { NotificationPrefs };
export type { VaccinationOverride, VaccinationSettings, VaccinationCoverageData };
export type { CryThresholdRow };

export interface CryRow {
  at: string; // ISO timestamp of the analysis
  reason: string; // wire code, e.g. 'hungry'
  confidence: number; // 0..1
  /**
   * Was the answer right — frame 17c. 'correct' | 'wrong', or absent when the
   * mother has not said. Absent is a THIRD state, not «wrong»: this product has
   * no other source of truth about why a baby cried, so an unrated row is
   * unknown and is counted as unknown everywhere.
   */
  verdict?: CryVerdict | null;
  /** What it actually was, when she said «нет» and picked one. */
  actualReason?: string | null;
}

export type CryVerdict = 'correct' | 'wrong';
export const CRY_VERDICTS = ['correct', 'wrong'] as const;

/**
 * The cry detector as the back office sees it — frame 17c. Aggregates only:
 * every figure here is a GROUP BY over `cry_results` and no row names a mother
 * or a child. There is deliberately no per-user list anywhere in this shape.
 */
export interface CryStats {
  /** Analyses in the window. */
  analyses: number;
  byReason: Array<{
    reason: string;
    count: number;
    /** Mean confidence of the analyses the model returned for this reason. */
    avgConfidence: number;
    /** How many of them fell UNDER the served threshold — i.e. named nothing. */
    belowThreshold: number;
    /** Rated by a mother as right / wrong. The only accuracy input that exists. */
    correct: number;
    wrong: number;
  }>;
  /** Analyses nobody rated. The denominator of «оценок пока нет». */
  unrated: number;
  /** The newest analysis in the window, or null when there is none. */
  lastAt: string | null;
  /**
   * The oldest analysis in the window — «собираем с …».
   *
   * Beside `lastAt` because the panel has to answer two different questions
   * while there are no verdicts at all: «работает ли он вообще» (the newest)
   * and «сколько мы уже собираем» (the oldest). Without this the honest empty
   * state has no date in it and reads as an excuse.
   */
  firstAt: string | null;
}

export interface SleepNight {
  night: string; // ISO date (wake day)
  deepMin: number;
  remMin: number;
  lightMin: number;
  awakeMin: number;
  // Provenance. A hand-entered night ('manual') has no measured stage split, so
  // the app stores the whole typed total here rather than inferring deep/REM it
  // could not know. Absent ('band', the default) for device-measured nights and
  // for backups that predate this — so old rows still read exactly as before.
  source?: string;
  manualAsleepMin?: number | null;
}

/**
 * One day of what the watch measured beyond the four triage vitals.
 *
 * Optional fields are optional on purpose: the watch reports 0 for a wellness
 * value it has not measured, and the app maps that to "absent" before it gets
 * here. A missing stress must stay missing — stored as 0 it would read back as
 * a measurement of perfect calm.
 */
export interface WearableDayRow {
  deviceId: string;
  day: string; // yyyy-MM-dd, the wearer's local day
  recordedAt: string; // ISO instant of the last snapshot folded into this day
  steps: number;
  kcal: number;
  meters: number;
  sleepMinutes: number;
  deepSleepMinutes: number;
  lightSleepMinutes: number;
  stress?: number | null;
  breathRate?: number | null;
  met?: number | null;
  batteryPercent?: number | null;
  charging: boolean;
  worn: boolean;
  /**
   * The vitals a DAY of the watch's own stored history carries.
   *
   * The live snapshot could only ever describe the minutes the app was open;
   * the watch keeps about a week of samples on the device and the vendor
   * documents a read command per metric (§5.44–5.53, §5.58). A backfilled day
   * therefore has a heart rate, an SpO2, a blood pressure, a temperature and a
   * blood sugar — averaged over the day's MEASURED samples, plus the extremes
   * that a mean cannot express.
   *
   * All optional and all nullable: absent means the watch measured none that
   * day, which is not the same as zero and must never be stored as zero.
   */
  heartRateAvg?: number | null;
  heartRateMin?: number | null;
  heartRateMax?: number | null;
  spo2Avg?: number | null;
  spo2Min?: number | null;
  systolicAvg?: number | null;
  diastolicAvg?: number | null;
  /** Tenths of a degree Celsius, the device's unit (365 = 36.5 °C). */
  tempAvgTenths?: number | null;
  /** Tenths of a mmol/L. A watch-optical estimate, never a diagnosis. */
  bloodSugarTenths?: number | null;
}

export interface WeightRow {
  date: string; // yyyy-MM-dd
  kg: number;
}

export interface MedicationRow {
  id: string;
  name: string;
  dose: string;
  perDay: number;
}

export interface NewbornEventRow {
  at: string; // ISO instant
  kind: 'feed' | 'diaper' | 'sleep';
  detail: string | null;
  durationMin: number | null;
}

export interface GrowthRow {
  at: string; // yyyy-MM-dd (one measurement per day)
  weightKg: number | null;
  heightCm: number | null;
}

export interface DoseRow {
  medId: string;
  date: string; // yyyy-MM-dd
  count: number; // doses taken that day (0..med.perDay)
}

export interface KickSessionRow {
  endedAt: string; // ISO instant
  count: number;
  durationSec: number;
}

export interface ContractionSessionRow {
  endedAt: string; // ISO instant
  count: number;
  avgDurationSec: number;
  avgIntervalSec: number;
}

export interface MedicalIdRow {
  bloodType: string;
  allergies: string;
  conditions: string;
  medications: string;
  doctorName: string;
  doctorPhone: string;
  contactName: string;
  contactPhone: string;
  notes: string;
}

export interface DayLogRow {
  date: string; // yyyy-MM-dd
  mood: string | null;
  symptoms: string[];
  kicks: number;
  flow: string | null; // light | medium | heavy | null
  note?: string; // free-text note the user typed for the day; '' / absent = none
}

/** The published bands of the EPDS. See app/lib/domain/epds.dart. */
export const EPDS_BANDS = ['low', 'possible', 'high'] as const;
export type EpdsBand = (typeof EPDS_BANDS)[number];

/**
 * One completed postpartum screening: when, how many points, which band.
 *
 * There is no `answers` field, and adding one is not a small change. Item 10 of
 * the scale asks about thoughts of self-harm; the handset totals the sheet and
 * discards it, so this row is all that has ever existed off the phone. The
 * score is enough for the only thing the back office legitimately does with it
 * — see it on the woman's own card, in context, behind an audit line.
 *
 * NOT a diagnosis. Nothing that renders this row may print one.
 */
export interface EpdsRow {
  /** Client-supplied UUID, so a re-push upserts rather than duplicating. */
  id: string;
  takenAt: string; // ISO timestamp
  score: number; // 0–30
  band: EpdsBand;
}

/** The kinds the app's AlertKind sends. See migration 030. */
export const SAFETY_ALERT_KINDS = ['entered', 'left', 'checkIn', 'sos', 'lowBattery'] as const;
export type SafetyAlertKind = (typeof SAFETY_ALERT_KINDS)[number];

export interface SafetyAlertRow {
  childId: string;
  /**
   * Was 'entered' | 'left' here and CHECK IN ('entered','left') in the schema,
   * while the app has sent five kinds all along — so an SOS press, a check-in
   * and a low-battery warning were refused by the constraint on insert. The
   * table meanwhile carried an index and two counters over `kind = 'sos'`,
   * rows it would not accept, which is why every SOS total read zero.
   */
  kind: SafetyAlertKind;
  /** The zone, for a crossing. An SOS happens anywhere, so it may be empty. */
  zoneName: string;
  at: string; // ISO timestamp
  /**
   * Frame 48 «Чем закончилось» — what the parent marked this SOS as, the
   * morning after. Null until somebody closes it, and only ever set on an SOS:
   * a zone crossing has no outcome to record.
   */
  outcome?: SosOutcome | null;
}

// ---- Support (frame 12). See migration 034. ----

export const SUPPORT_STATUSES = ['new', 'open', 'waiting', 'closed'] as const;
export type SupportStatus = (typeof SUPPORT_STATUSES)[number];

export const SUPPORT_CHANNELS = ['whatsapp', 'phone', 'panel', 'app'] as const;
export type SupportChannel = (typeof SUPPORT_CHANNELS)[number];

export interface SupportTicketRow {
  id: string;
  /** Null when she wrote before having an account. */
  userId: string | null;
  phone: string | null;
  customerName: string | null;
  channel: SupportChannel;
  subject: string;
  body: string;
  status: SupportStatus;
  assigneeId: string | null;
  createdAt: string;
  updatedAt: string;
  /** When WE last replied. Null means she is still waiting for a first answer. */
  answeredAt: string | null;
  closedAt: string | null;
  /** What the app knew when she wrote — version, device, offline. */
  appContext: string | null;
  /**
   * When SHE last wrote, if she has written since raising the ticket.
   *
   * DERIVED from support_replies, not a column — there is nothing to migrate
   * and nothing that can fall out of step with the thread it summarises.
   *
   * It exists because the app can now write back. Before that, the ticket's
   * own creation WAS her last message and the SLA could measure from
   * created_at; a ticket she answered a fortnight later would otherwise read
   * as a fortnight of us being slow, and the queue would put her at the top of
   * the screen for a message that arrived a minute ago. Null means she has not
   * spoken since; the board then falls back to createdAt.
   */
  lastCustomerAt: string | null;
  /**
   * When SHE last opened the thread in the app. See migration 035.
   *
   * The «Есть ответ поддержки» badge counts an answer NEWER than this — so
   * reading takes it down and the next reply lights it again. Null means she
   * has never opened it, which is the state every ticket starts in.
   */
  customerReadAt: string | null;
}

export interface NewSupportTicket {
  userId?: string | null;
  phone?: string | null;
  customerName?: string | null;
  channel?: SupportChannel;
  subject: string;
  body?: string;
  appContext?: string | null;
}

export type SupportTicketPatch = Partial<{
  status: SupportStatus;
  assigneeId: string | null;
  /** Set when staff reply, so the SLA measures OUR response and not her reply. */
  answeredAt: string | null;
  closedAt: string | null;
}>;

export interface SupportReplyRow {
  id: string;
  ticketId: string;
  author: 'customer' | 'staff';
  staffId: string | null;
  body: string;
  at: string;
}

export interface NewSupportReply {
  ticketId: string;
  author: 'customer' | 'staff';
  staffId?: string | null;
  body: string;
}

export interface SupportTemplateRow {
  id: string;
  title: string;
  bodyRu: string;
  /** Null means it is not ready to send to a Kazakh speaker. */
  bodyKk: string | null;
  sort: number;
}

/** The stages a product can be FOR. See migration 033. */
export const PRODUCT_STAGES = [
  'planning', 'pregnancy', 'newborn', 'infant', 'toddler', 'any',
] as const;
export type ProductStage = (typeof PRODUCT_STAGES)[number];

export interface ShopCategoryRow {
  id: string;
  nameRu: string;
  nameKk: string | null;
  sort: number;
}

/**
 * A partial update. A key that is ABSENT leaves the column alone; a key set to
 * null clears it. Those are different operations and the panel needs both —
 * saving the SEO tab must not wipe the personalisation tab.
 */
export type ProductPatch = Partial<{
  name: string;
  nameKk: string | null;
  priceMinor: number;
  costMinor: number | null;
  active: boolean;
  sort: number;
  sku: string | null;
  category: string | null;
  stage: ProductStage | null;
  descriptionRu: string | null;
  descriptionKk: string | null;
  ageMinMonths: number | null;
  ageMaxMonths: number | null;
  photoUrl: string | null;
  seoSlug: string | null;
  seoTitle: string | null;
  seoDescription: string | null;
}>;

export interface ProfileRow {
  displayName: string;
  /**
   * E.164. READ-ONLY as far as the app is concerned: this is `users.phone_e164`,
   * the column POST /auth/phone resolves an account by, and it is set exactly
   * once — when the account is created from the number she signed in with.
   *
   * It is therefore NOT a profile field. See [ProfileEdit].
   */
  phone: string | null;
  dueDate: string | null; // yyyy-MM-dd
  locale: string;
  /**
   * Optional details the app collects with a stated reason: age-relevant
   * guidance, and products that can actually be delivered where she lives.
   *
   * Null means she declined, which is a supported answer everywhere it is read
   * — not a missing field to be filled in later.
   */
  birthDate: string | null; // yyyy-MM-dd
  city: string | null;
  /**
   * Where an ambulance is sent — app screen 37's dispatcher card.
   *
   * A HOME address, and the product's only one. `shop_orders.address` is a
   * delivery address attached to one order and may be a workplace or a
   * relative's flat; putting that on the screen somebody reads out to a 103
   * dispatcher sends the ambulance to the wrong door.
   *
   * Null means she has not given one, which the screen states as her city plus
   * «Добавьте адрес» rather than inventing anything.
   */
  address: string | null;
  doctorPhone: string | null; // her own emergency contact
  avgCycleLength: number | null; // women's-health baselines (null = app defaults)
  avgPeriodLength: number | null;
}

/**
 * What a signed-in user may actually change about herself — the profile MINUS
 * the phone number.
 *
 * The number is the sign-in credential. PUT /profile used to accept one and
 * write it to `users.phone_e164`, so anybody with an account could CLAIM a
 * number that was not hers; when the real owner signed in, `userByPhone()`
 * resolved her to the claimant's row and she landed inside a stranger's
 * session — that person's pregnancy, children and live child locations. The
 * same column keys the course entitlement and «Мои заказы», so it also handed
 * over purchases.
 *
 * The type is the guard: a repository method that cannot be passed a phone
 * cannot write one, and a future route that tries will not compile.
 */
export type ProfileEdit = Omit<ProfileRow, 'phone'>;

/** Aggregate demographics of the tracked children, for the admin dashboard. */
export interface ChildrenStats {
  total: number;
  boys: number;
  girls: number;
  unknown: number; // gender not provided
  /** Age buckets in order, each with a label and a count. */
  byAge: Array<{ bucket: string; count: number }>;
  withDob: number; // how many have a date of birth (age buckets are over these)
}

/**
 * The business snapshot behind the Dashboard.
 *
 * Separate from BiMetrics, which answers "how is the product being used" —
 * DAU, retention, funnels. This answers "what is this business", and the two
 * are read by different people for different decisions: one drives what to
 * build next, the other whether to order more stock.
 *
 * Every count here is a count of rows that exist. Nothing is estimated,
 * projected or filled in, so a field reading 0 means zero and can be shown as
 * such rather than dressed up.
 */
export interface DashboardSnapshot {
  asOf: string;
  users: {
    total: number;
    newToday: number;
    new7d: number;
    new30d: number;
    /** Signed in / sent data in the last 1, 7 and 30 days. */
    dau: number;
    wau: number;
    mau: number;
    /** Came back on day 7 out of the cohort that could have. 0..1, null if no cohort yet. */
    retentionD7: number | null;
  };
  /**
   * Who the users are. Pregnant and mothers OVERLAP on purpose — a mother
   * expecting her second child is both, and forcing her into one bucket would
   * misstate whichever number someone happens to read.
   */
  mothers: {
    /** Expecting: a due date that has not passed. */
    pregnant: number;
    /** Has at least one child on the account. */
    mothers: number;
    /** Both — pregnant with a child already. */
    both: number;
    /** Neither recorded. Not "childless": most of these simply filled nothing in. */
    unknown: number;
  };
  children: ChildrenStats;
  devices: {
    total: number;
    /** Seen in the last 24 hours. */
    online: number;
    /** Mother's watch vs child's tracker — the two things we sell. */
    watches: number;
    trackers: number;
    /** Registered but attached to no child, so nothing is watching anyone. */
    unassigned: number;
    /**
     * Paired devices that are NOT in our device registry — the grey-market
     * number, and the one that decides whether enforcement can be switched on.
     *
     * Two very different things look identical here, which is exactly why it
     * has to be visible rather than assumed: units genuinely bought elsewhere,
     * and units we sold whose serial nobody recorded at intake. Turning
     * enforcement on while this number is large refuses paying customers.
     */
    unregistered: number;
  };
  /** Where they are, biggest first. Only users who gave a city. */
  cities: Array<{ city: string; users: number }>;
  citiesUnknown: number;
  commerce: {
    leads: { total: number; new: number };
    orders: { total: number; new: number; confirmed: number; shipped: number; delivered: number; cancelled: number };
    /** Money actually earned: shipped + delivered, cancellations excluded. */
    revenueMinor: number;
    /** Money promised but not yet shipped — new + confirmed. */
    pipelineMinor: number;
    /** Average order value over the orders counted in revenue. Null with none. */
    avgOrderMinor: number | null;
    stock: {
      units: number;
      /** What the shelf is worth at the price we sell it for. */
      retailMinor: number;
      /** What it cost us. Only over products whose cost is recorded. */
      costMinor: number;
      /** Units whose cost is unknown, so costMinor understates the real one. */
      unitsWithoutCost: number;
    };
    /** Product ids at or below their low-stock threshold. */
    lowStock: string[];
  };
  /**
   * The Ма!Ма! course — the thing the комплект charges 9 200 ₸ over the
   * hardware for.
   *
   * The dashboard could say what was sold and never whether it was used, which
   * is the only evidence that the premium is worth paying twice. [granted] and
   * [started] are the pair that matters: the gap between them is customers who
   * bought the course and have never pressed play.
   */
  course: {
    /** Lessons published, i.e. what a buyer can actually watch today. */
    lessons: number;
    /** Phones the course is open to. */
    granted: number;
    /** Of those, how many have opened at least one lesson. */
    started: number;
    /** Of those, how many have finished every published lesson. */
    finished: number;
    /** Lessons watched through, summed over everyone. */
    lessonsCompleted: number;
    /** Watched at least one lesson in the last 7 days. */
    active7d: number;
  };
}

/** A dated appointment/reminder. Mirrors the app's Appointment (domain/appointment.dart). */
export interface Appointment {
  id: string;
  title: string;
  at: string; // ISO 8601
  note: string;
}

/** One lesson or product on the timeline. Mirrors the app's ContentItem. */
export interface ContentItemRow {
  id: string;
  kind: 'lesson' | 'product';
  title: Record<string, string>; // locale → text
  summary: Record<string, string>;
  /// The article itself, per locale — what she actually reads (admin frame
  /// 16a). Absent on everything published before articles existed, which is
  /// why it is optional and why the bilingual rule only applies once one
  /// language of it has been written. See the zod schema in routes/admin.ts.
  body?: Record<string, string>;
  /// «Красный флаг» — its own field so the app can draw it ABOVE the article
  /// and always expanded, per docs/CLAUDE-app-design.md §4.6.
  redFlags?: Record<string, string>;
  url?: string;
  priceMinor?: number; // products, in minor units (tiyn)
  currency?: string;
  imageUrl?: string;
  durationMin?: number; // lessons
  // Where the lesson's video lives; see the zod schema in routes/admin.ts.
  video?: { provider: 'hls' | 'mp4' | 'youtube'; url: string; posterUrl?: string };
  // Targeting; absent means the item is for everyone, which is the usual case.
  cities?: string[];
  minAgeYears?: number;
  maxAgeYears?: number;
  /// Other stages this same item also serves; it is stored once, under the
  /// stage it is filed in. See the zod schema in routes/admin.ts.
  alsoStages?: string[];
  /// Which shelf of the app's guides library this belongs on.
  ///
  /// A fixed vocabulary, not free text: the app draws four topic tiles and a
  /// fifth value would be downloaded and never shown. Optional — an untagged
  /// item is placed by its home stage (weeks → pregnancy, m0-m12 → baby, m13+
  /// → child), which is why the grid is not empty on the day this shipped.
  /// 'mother' has no stage that implies it, so it is only ever set by hand.
  topic?: 'pregnancy' | 'baby' | 'child' | 'mother';
  /// Medical guidance, so it may not be published without a clinician's
  /// sign-off. See content/medicalReview.ts.
  medical?: boolean;
  /// Work in progress; never served to the app.
  draft?: boolean;
  /// Who checked it, when, and what they read. Back-office only — stripped
  /// before the catalogue reaches a phone, because it names a member of staff.
  review?: { by: string; at: string; fingerprint: string };
}

/** One language's half of a calendar week. Mirrors the shared contract. */
export interface PregnancyWeekTextRow {
  baby: string;
  you: string;
  recommend: string;
}

/**
 * One edited gestational week.
 *
 * An OVERRIDE, not the week: the shipped contract stays the baseline the app
 * bundles and works offline from, and rows here patch it. `lengthCm`/`hcg` may
 * be null, meaning "keep what the contract says" — rewriting the prose of week
 * 22 is not a claim about how long the baby is.
 */
export interface PregnancyWeekOverride {
  week: number;
  lengthCm: string | null;
  hcg: string | null;
  ru: PregnancyWeekTextRow;
  kk: PregnancyWeekTextRow;
  /// Stored, never served — the reader keeps seeing the contract text.
  draft: boolean;
  /// A clinician's sign-off on the exact text they read; see medicalReview.ts.
  review: { by: string; at: string; fingerprint: string } | null;
  /// Save counter, so the served calendar's version moves on every edit.
  rev: number;
  updatedAt: string;
  updatedBy: string | null;
}

/** One language's half of an emergency scenario. Mirrors the shared contract. */
export interface EmergencyTextRow {
  title: string;
  what: string;
  do: string;
}

/**
 * One edited emergency-help scenario — frame 16b / app screen 37.
 *
 * An OVERRIDE, not the scenario: the shipped contract
 * (packages/contract/emergency_help.json) stays the baseline the app bundles
 * and works offline from, and rows here patch it. `severity` decides whether
 * the card tells somebody to dial 103 or to call the clinic today, so it is
 * inside the clinician's fingerprint (see emergency/overrides.ts).
 */
export interface EmergencyHelpOverride {
  id: string;
  severity: 'red' | 'amber';
  sort: number;
  ru: EmergencyTextRow;
  kk: EmergencyTextRow;
  /// Stored, never served — the reader keeps seeing the contract text.
  draft: boolean;
  /// A clinician's sign-off on the exact text they read; see medicalReview.ts.
  review: { by: string; at: string; fingerprint: string } | null;
  /// Save counter, so the served list's version moves on every edit.
  rev: number;
  updatedAt: string;
  updatedBy: string | null;
}

/**
 * One entry of the vaccination schedule log — frame 15b «История версий».
 *
 * Append-only. The override row holds only the CURRENT text, so a version list
 * built from it could show what a vaccine says but never what it said before.
 * `before` is null on a vaccine's first edit: there was no row, and the
 * baseline that edit departed from is the shipped contract, which the panel
 * already has and shows instead of this inventing one.
 */
export interface VaccinationLogEntry {
  id: number;
  /// The override key, or '@settings' for a change to the catch-up window.
  key: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown>;
  actor: string | null;
  at: string;
}

/**
 * One рассылка — frame 06.
 *
 * The Kazakh halves are nullable, and that is the publication gate rather than
 * sloppiness: a draft may be half-written, and the route refuses to publish
 * without them.
 */
export interface BroadcastRow {
  id: string;
  titleRu: string;
  bodyRu: string;
  titleKk: string | null;
  bodyKk: string | null;
  segment: import('../admin/broadcasts.js').BroadcastSegment;
  status: 'draft' | 'published';
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
  publishedAt: string | null;
  /**
   * How many phones it actually reached, off the delivery ledger.
   *
   * NOT how many the segment matched. A published broadcast whose audience was
   * entirely inside the weekly gap reads 0 here, which is the truth — and the
   * panel prints «доставлено», never a read rate, because nothing in this
   * product records whether a notification was opened.
   */
  delivered: number;
}

/**
 * Her notification switches, PLUS the timezone they have to be read in.
 *
 * The timezone travels with the preferences rather than being fetched
 * separately because forgetting it is silent: quiet hours evaluated against the
 * server's UTC clock still "work", they just hold the wrong nine hours of her
 * day. One call, one struct, no way to have the switches without the clock.
 */
export interface NotificationPrefsRow extends NotificationPrefs {
  /** `users.timezone` — IANA, 'Asia/Almaty' by default. */
  timezone: string;
  /**
   * When she last changed them, or null when this row is the DEFAULTS rather
   * than something she chose. The panel counts «сколько мам настроили» off
   * rows that exist, so the distinction has to survive the read.
   */
  updatedAt: string | null;
}

/** One attempt to reach a phone — sent or held. See migrations/047. */
export interface PushDeliveryRecord {
  /** Null for a send with no single recipient. */
  userId: string | null;
  kind: PushKind | string;
  sent: number;
  failed: number;
  /** How many tokens FCM told us to forget on this attempt. */
  dead: number;
  /** Null = it went out. Otherwise why it did not. */
  heldReason: HoldReason | null;
  /** Whole-send failure, verbatim; 'no_tokens' means she has no device. */
  error: string | null;
}

/**
 * What the back office reads on frame 25.
 *
 * Every field is COUNTED. There is deliberately no open rate: FCM accepting a
 * message is not a phone showing it and is certainly not a woman reading it,
 * and the moment a percentage appears here somebody will make a decision with
 * it.
 */
export interface PushDeliverySummary {
  windowDays: number;
  /** One row per push kind that actually occurred — never a padded list. */
  kinds: Array<{
    kind: string;
    /** Attempts, held ones included. */
    attempts: number;
    /** Phones FCM accepted the message for. */
    delivered: number;
    failed: number;
    /** Attempts refused because she has no registered device. */
    noTokens: number;
    /** Attempts we did not make, because of her switches. */
    held: number;
    heldMuted: number;
    heldQuiet: number;
    /** Whole-send failures other than «нет устройства». */
    errors: number;
    /** Dead tokens removed on this kind's attempts. */
    dead: number;
  }>;
  /** Dead tokens removed across all kinds in the window. */
  deadTokens: number;
  /** How many mothers have switched each category OFF. */
  muted: {
    zoneEvents: number;
    checkIn: number;
    lowBattery: number;
    updates: number;
    /** …and how many have a quiet-hours window set. */
    quietHours: number;
    /** Rows in notification_prefs — mothers who have touched the screen. */
    configured: number;
  };
  /** The most recent attempt in the window, or null when there were none. */
  lastAt: string | null;
}

/** One рассылка as the app receives it. */
export interface AnnouncementRow {
  id: string;
  /** When it was sent to HER — the ledger row, not the publication instant. */
  at: string;
  ru: { title: string; body: string };
  /** Falls back to the Russian text only in the app; the server sends what it has. */
  kk: { title: string; body: string };
}

/** A whole family, assembled for the back-office drilldown. */
export interface AdminUserDetail {
  id: string;
  displayName: string;
  phone: string | null;
  dueDate: string | null;
  locale: string | null;
  /** Null when she declined — the panel shows that as "not provided". */
  birthDate: string | null;
  city: string | null;
  /**
   * Both repositories return these and the admin drilldown renders them as
   * "Контакт врача" and "Цикл (база)" — they were just missing from the type,
   * so the parity test that guards them could not compile.
   */
  doctorPhone: string | null;
  avgCycleLength: number | null;
  avgPeriodLength: number | null;
  children: Array<{ id: string; name: string; dateOfBirth: string | null; zones: number }>;
  devices: Array<{ id: string; name: string; kind: string; childId: string | null; batteryPct: number | null }>;
  latest: Record<string, number | null>;
  triage: Array<{ code: string; severity: string; at: string }>;
  alerts: Array<{ kind: string; childName: string; zoneName: string; at: string }>;
  sleepNights: number;
  loggedDays: number;
}

export interface AdminDevice {
  /** The identifier printed on the hardware (ble_mac) — what a support call names. */
  id: string;
  /**
   * Our internal row id. The defect action addresses THIS, not the MAC: the
   * same MAC can legitimately exist under two accounts (a resold unit), and a
   * write keyed on it would be ambiguous about whose device was marked.
   */
  deviceId: string;
  name: string;
  kind: string;
  userId: string;
  displayName: string;
  childName: string | null;
  batteryPct: number | null;
  lastSeen: string | null;
  /** NULL = never reported one. Shown as «не сообщалась», never as a dash. */
  firmware: string | null;
  /** «Пометить браком» — when, by whom, and why. All null when unmarked. */
  defectAt: string | null;
  defectBy: string | null;
  defectNote: string | null;
}

export interface AdminSafetyEvent {
  userId: string;
  displayName: string;
  childName: string;
  kind: string; // entered | left | sos | checkIn | lowBattery
  zoneName: string;
  at: string;
  /**
   * How the mother closed this SOS — `false_press` | `scared` | `needed_help` |
   * `unknown` — and null while she has not.
   *
   * The column has existed since migration 032 and NOTHING read it back out:
   * the query did not select it, so the panel's «Чем закончилось» cell printed
   * `undefined` for every row and rendered it as «мама ещё не закрыла». Every
   * closed SOS in the database looked open, and the share of false presses —
   * the one number that says whether these alarms mean anything — could not be
   * computed at all.
   *
   * Always null for a crossing: a zone has nothing to close.
   */
  outcome: SosOutcome | null;
  /**
   * Her number, for «Позвонить маме» — step 1 of the operator instruction the
   * frame prints, which said «Номер — в карточке» while no card on the screen
   * carried one. Null when the account has no phone.
   *
   * PII, and deliberately only on this route: /admin/safety already requires
   * the `health` capability and writes `view_safety_feed` to the audit log.
   */
  phone: string | null;
}

/**
 * One row of the live emergency feed (frame 19).
 *
 * Was an inline anonymous type on the method, which is why `code` could stay a
 * hard-coded literal in both implementations without anything noticing.
 */
export interface AdminEmergency {
  /** `<userId>|<recordedAt ISO>` — the metrics table has no single-column id. */
  id: string;
  userId: string;
  displayName: string;
  /**
   * The triage finding code recomputed from the stored reading — see
   * emergency/reason.ts. '' when the stored vitals no longer explain the row,
   * which the panel says out loud instead of naming a cause it does not have.
   *
   * Was the literal string 'EMERGENCY' in both repositories.
   */
  code: string;
  severity: string;
  at: string;
  /** Which metric crossed, its value and the threshold it crossed. */
  metric: string | null;
  value: number | null;
  threshold: number | null;
  /** Both halves of the blood pressure, so the panel can print 162/108. */
  systolic: number | null;
  diastolic: number | null;
  /** Sub-95 SpO2 asleep and awake are different findings; triage uses this. */
  duringSleep: boolean;
  acknowledgedAt: string | null;
  acknowledgedBy: string | null;
}

export interface AdminAnalytics {
  totalUsers: number;
  pregnant: number;
  withChildren: number;
  devices: number;
  alerts7d: number;
  sosAllTime: number;
  /** Stage key → how many accounts sit there right now. */
  stageDistribution: Record<string, number>;
  contentStages: number;
  /**
   * WHICH stages have at least one item, not just how many.
   *
   * Sent so the panel can put coverage beside [stageDistribution] without
   * reading the catalogue itself — the CMS lives in a different script block
   * and cannot be reached from the analytics one. Deriving it there twice is
   * also how the two counts would drift apart.
   */
  contentStageKeys: string[];
  contentItems: number;
  contentLinked: number;
}

/**
 * Who can sign in to the back office.
 *
 * Defined once, in ../auth/capabilities, together with what each role may
 * actually do. It used to be spelled out here as a three-name union, which is
 * how the storage layer ended up being the thing that decided policy: adding a
 * `seller` meant editing a database module.
 */
export type { StaffRole } from '../auth/capabilities';
import type { StaffRole } from '../auth/capabilities';

/** A staff row as the login path needs it — hash included, so keep it there. */
export interface StaffAccount {
  id: string;
  phone: string;
  passwordHash: string;
  role: StaffRole;
  displayName: string;
  disabled: boolean;
}

/** An account as the panel's roster shows it — everything except the hash. */
export interface StaffSummary {
  id: string;
  phone: string;
  role: StaffRole;
  displayName: string;
  disabled: boolean;
  createdAt: string;
  lastLoginAt: string | null;
}

/**
 * One entry of the back-office audit log, as a reader sees it.
 *
 * staffName/targetName are resolved from the roster where they can be. Null
 * means the account is gone or predates accounts existing — the row still
 * comes back, because a log that hides what it cannot label is worse than one
 * that shows an id.
 */
export interface AuditEntry {
  staffId: string;
  staffName: string | null;
  staffPhone: string | null;
  action: string;
  target: string | null;
  targetName: string | null;
  /**
   * Why the record was opened, for the reads that demand one. Null on
   * everything older than migration 029 and on actions that explain
   * themselves.
   */
  reason: string | null;
  at: string;
}

/**
 * A page of the audit log, and whether there is another one behind it.
 *
 * `hasMore`, deliberately, and NOT a total.
 *
 * `audit_log` is append-only and grows with every back-office action — every
 * sign-in, every order opened, every throttled feed read. Postgres cannot
 * answer `count(*)` from an index, so a total would mean a full scan of a
 * table with no upper bound, on every open of the «Журнал» tab and again after
 * every patient card opened. `hasMore` costs one extra row instead: the page
 * is fetched with `LIMIT n + 1` and the surplus row IS the answer.
 *
 * So the panel prints «Показано 101–200 · есть ещё» rather than «… из 4 812»,
 * and says on screen that the log is not counted. An absent number that admits
 * itself beats a number nobody paid for. See BACKLOG.md §4.4.
 */
export interface AuditPage {
  entries: AuditEntry[];
  /** True when at least one entry exists past this page. Never a guess. */
  hasMore: boolean;
}

export interface Repository {
  // Health
  /**
   * Store one reading. Idempotent on (userId, deviceId, recordedAt): the batcher
   * re-sends a whole batch when a flush's RESPONSE is lost even though the server
   * stored it, so the same reading can arrive twice.
   *
   * Returns `true` when this reading was a DUPLICATE of one already stored (so the
   * caller skips the emergency push and counts it separately), `false` when it was
   * freshly inserted. Fail-safe: an implementation that does not dedup returns
   * `false`, so the worst case is a repeated push (today's behaviour), never a
   * SUPPRESSED real emergency.
   *
   * `BandTelemetry.deviceTempC` — a device temperature with no stated
   * measurement site — is stored in a column of its OWN (`device_temp_c`) and
   * must never be written to `core_temp_c`, merged into it on read, or fed to
   * triage: every reader of `core_temp_c` treats it as an estimate of her core,
   * and this value cannot be converted into one. Carried and stored, never
   * graded — the `glucoseMmol` precedent. See docs/CLINICAL-REVIEW-WATCH.md,
   * "Device temperature — closed 2026-08-13".
   */
  insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }): Promise<boolean>;
  /**
   * The caller's own HAND-ENTERED readings (device_id NULL): typed cuff/glucose
   * values. For restoring a typed vitals history on a new device — band readings
   * are re-supplied by the device, so they are deliberately excluded.
   *
   * Every row carries `source: 'manual'`, and the literal type is the point: the
   * filter is what MAKES them manual (device_id IS NULL), so an implementation
   * has nothing to decide and cannot emit anything else.
   *
   * It was omitted, and omission is not neutral here. `HealthSample.fromJson`
   * reads an absent `source` as a DEVICE reading — deliberately, because an
   * unlabelled stored row cannot be shown to have come off a thermometer. So a
   * woman who changed handsets got every thermometer reading she had ever typed
   * back labelled a wrist estimate: her measured 38.6 stopped escalating (a
   * device temperature is warning-only by ruling), her typed readings dropped
   * out of the visit summary, and the manual-diary card disappeared for exactly
   * the woman using it. Invisible on the phone where she typed them; it only
   * appears on the next one. See docs/CLINICAL-REVIEW-WATCH.md.
   *
   * The word is the APP's wire vocabulary — `BandTelemetry.sourceFromWire`
   * accepts 'manual' and reads everything else, including absent, as a sensor.
   */
  listManualVitals(userId: string): Promise<Array<{
    recordedAt: string; heartRateBpm: number | null; spo2Pct: number | null;
    systolicMmHg: number | null; diastolicMmHg: number | null; coreTempC: number | null; glucoseMmol: number | null;
    source: 'manual';
  }>>;
  /**
   * The user's own EMERGENCY-severity readings whose `recorded_at` falls within
   * [windowMs] either side of [aroundIso] — the evidence for "have we already
   * alerted about this episode?".
   *
   * Read by ingestTelemetry before it pushes. Without it the server had no
   * memory between readings at all: five band frames a minute apart at 145/95
   * produced five critical, DND-bypassing pushes about one condition, and an
   * offline queue draining in a single flush fired the whole backlog at once.
   *
   * `manual` is `device_id IS NULL`, exactly as `listManualVitals` above states
   * it — asserted by the query rather than read off the row. It has to travel,
   * because the caller replays `assessTelemetry` over these values to recover
   * which measurement each emergency was about, and that function's fever
   * branch reads provenance: a thermometer reading replayed as a wrist estimate
   * would come back with no finding at all.
   *
   * BOTH SIDES of the instant, not just before it. Readings do not always
   * arrive in the order they were taken (a requeued batch, two handsets), and
   * an "earlier than" query lets such a pair alert twice — each being the first
   * the server saw. See emergency/episode.ts.
   *
   * Fail-safe direction, the same as insertHealthMetric's: an implementation
   * that returns [] causes an extra push, never a suppressed one.
   *
   * Served by idx_phm_user_time (user_id, recorded_at DESC) — no new index and
   * no migration; the columns and the index already exist.
   */
  recentEmergencyReadings(
    userId: string,
    aroundIso: string,
    windowMs: number,
  ): Promise<StoredEmergencyReading[]>;
  insertBpCalibration(userId: string, cal: BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number }): Promise<void>;
  // The caller's most recent calibration, or null. Powers the admin drawer
  // (is her BP calibrated, and how recently?) and the new-device restore.
  latestBpCalibration(userId: string): Promise<(BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number }) | null>;

  // Child / geofence
  loadGeofences(childId: string): Promise<Geofence[]>;
  insertGeofenceEvent(evt: GeofenceEvent): Promise<void>;
  insertLocation(fix: ChildLocationFix): Promise<void>;
  /// The most recent stored fix — the durable answer behind the Redis cache.
  ///
  /// Every fix is written to location_history on the same request that caches
  /// it, so this is never *less* current than the cache; it is only slower.
  /// Without it, a cache outage turned "where is my child" into a 500, which
  /// is the one question this service exists to answer.
  lastLocation(childId: string): Promise<ChildLocationFix | null>;
  /**
   * Delete location fixes observed before [cutoffIso]. Returns how many went.
   *
   * The privacy promise the app makes — «Маршруты хранятся 90 дней» — and the
   * only one of its promises that has to be kept by DOING something on a
   * schedule rather than by not doing something. db/schema.sql has carried the
   * DELETE as a comment since the Timescale retention policy was dropped, and
   * a comment prunes nothing: every child's trail has been accumulating since
   * the first fix.
   *
   * Deliberately takes the cutoff rather than computing it. A retention window
   * that reads the clock cannot be tested against a fixed set of rows, and
   * "90 days" is exactly the kind of number that has to be exercised at its
   * boundary.
   */
  pruneLocationHistory(cutoffIso: string): Promise<number>;
  /**
   * The rest of the retention sweeps — one method per period, all of them
   * driven from src/privacy/retention.ts, which is the only place a number is
   * written down.
   *
   * Each takes the cutoff rather than computing it, for the same reason
   * pruneLocationHistory does: a window that reads the clock cannot be tested
   * against a fixed set of rows, and over-deleting is the failure that cannot
   * be undone. Each returns how many rows went, so a log line and a test can
   * both check that a sweep did what it claims rather than trusting it.
   *
   * STRICTLY older than the cutoff, in every implementation. A row exactly at
   * the boundary is still inside its window.
   */
  /// geofence_events older than the cutoff — the same 90 days as the trail that
  /// produced them. A crossing is a coarse movement history under another name.
  pruneGeofenceEvents(cutoffIso: string): Promise<number>;
  /// safety_alerts older than the cutoff, SOS rows included. Twelve months.
  pruneSafetyAlerts(cutoffIso: string): Promise<number>;
  /// audit_log older than the cutoff. Three years — the period the security
  /// panel printed for months before anything enforced it.
  pruneAuditLog(cutoffIso: string): Promise<number>;
  /// phone_codes created before the cutoff. A used code is deleted on use; this
  /// is for the abandoned ones, which otherwise keep a phone number for ever.
  prunePhoneCodes(cutoffIso: string): Promise<number>;
  /// BOTH attempt tables — user_login_attempts and staff_login_attempts — at
  /// one period, returning the total. They are one decision, so they are one
  /// method: two would let a later edit move one and forget the other.
  pruneLoginAttempts(cutoffIso: string): Promise<number>;
  /// shop_leads older than the cutoff. A name and a phone from the landing form.
  pruneShopLeads(cutoffIso: string): Promise<number>;
  /**
   * support_tickets whose LAST activity is older than the cutoff, together with
   * the replies hanging off them (support_replies cascades in Postgres; the
   * in-memory repository drops them by hand to match).
   *
   * Last activity, not creation: a thread that ran for two years must not lose
   * its beginning while its end is still live. Returns tickets deleted, not
   * tickets plus replies — one number for one thing, so it can be asserted.
   */
  pruneSupportTickets(cutoffIso: string): Promise<number>;
  /**
   * Every fix for one child between two instants, oldest first.
   *
   * The read side of the trail. `insertLocation` has been writing to
   * location_history since the first fix and `pruneLocationHistory` has been
   * deleting from it, and between the two there was no way to look: the app's
   * «История дня» could not be built because nothing could answer "where was
   * she today". Retaining data nobody can read is the worst of both — the
   * privacy cost without the use.
   *
   * Bounded by [limit] because a tracker reporting every thirty seconds makes
   * 2 880 points a day, and a map drawing all of them is a map of nothing.
   */
  locationHistory(
    childId: string,
    fromIso: string,
    toIso: string,
    limit: number,
  ): Promise<ChildLocationFix[]>;

  // Push
  /// Push targets for a child's guardian, WITH the language they read in.
  ///
  /// The locale travels with the tokens because the copy is written at the
  /// moment of sending and there is nowhere else to get it. Without it every
  /// push went out in English to an app whose default language is Russian.
  guardianPushTokens(
    childId: string,
  ): Promise<{ tokens: string[]; childName: string; locale: string | null }>;
  guardianPushTokensForUser(userId: string): Promise<{ tokens: string[]; locale: string | null }>;

  /// Forget a token FCM has told us is dead.
  ///
  /// Without this a reinstalled app leaves its old token behind for ever, and
  /// every emergency push is delivered to nothing — silently, because a dead
  /// token fails per-token inside a multicast that otherwise succeeds.
  deletePushToken(token: string): Promise<void>;

  // AI grounding
  retrieveRagPassages(query: string, locale: string): Promise<string[]>;

  // Emergency routing
  emergencyContacts(userId: string): Promise<Array<{ label: string; tel: string }>>;
  deviceOwner(deviceId: string): Promise<{ userId: string } | null>;

  // ---- Ownership lookups ----
  // Routes that take an id from the URL must confirm the caller owns it.
  // Being signed in is not the same as being this child's parent, and without
  // these any account could read or delete another family's data by id.
  childOwner(childId: string): Promise<{ userId: string } | null>;

  // ---- Family access (screen 40) ----
  //
  // Note what is NOT here: no method takes or returns anything of the mother's
  // own — no health, no cycle, no appointments. A grant is over her children,
  // and «здоровье и цикл не видит никто» is kept by there being nothing here
  // that could break it. See src/family/access.ts.

  /// Everyone this account has let in, newest first.
  familyMembers(ownerUserId: string): Promise<Array<{
    memberUserId: string;
    /// What the owner calls them — «Папа», «Бабушка».
    label: string;
    /// Their own profile name, so the list can show who actually accepted.
    displayName: string | null;
    phone: string | null;
    level: string;
    createdAt: string;
  }>>;
  /// The accounts whose children this person can see. The inverse direction —
  /// what a father's app asks on launch.
  familyMemberships(memberUserId: string): Promise<Array<{
    ownerUserId: string;
    level: string;
  }>>;
  /// This person's level over that account's children, or null. The guard.
  familyLevel(ownerUserId: string, memberUserId: string): Promise<string | null>;
  /// Grant or update. One row per pair, so accepting twice re-levels rather
  /// than granting twice.
  upsertFamilyAccess(g: {
    ownerUserId: string;
    memberUserId: string;
    level: string;
    label: string;
  }): Promise<void>;
  removeFamilyAccess(ownerUserId: string, memberUserId: string): Promise<boolean>;

  createFamilyInvite(i: {
    ownerUserId: string;
    tokenHash: string;
    level: string;
    label: string;
    expiresAt: string;
  }): Promise<void>;
  /// By hash — the token itself is in the link and never stored.
  familyInviteByHash(tokenHash: string): Promise<{
    tokenHash: string;
    ownerUserId: string;
    level: string;
    label: string;
    createdAt: string;
    expiresAt: string;
    usedAt: string | null;
    usedBy: string | null;
    revokedAt: string | null;
  } | null>;
  familyInvites(ownerUserId: string, limit: number): Promise<Array<{
    tokenHash: string;
    ownerUserId: string;
    level: string;
    label: string;
    createdAt: string;
    expiresAt: string;
    usedAt: string | null;
    usedBy: string | null;
    revokedAt: string | null;
  }>>;
  /// Mark spent. Returns false if somebody got there first — the check and the
  /// claim have to be one step, or two people share one «одноразовая» link.
  claimFamilyInvite(tokenHash: string, byUserId: string, atIso: string): Promise<boolean>;
  revokeFamilyInvite(ownerUserId: string, tokenHash: string): Promise<boolean>;
  geofenceOwner(geofenceId: string): Promise<{ userId: string } | null>;

  // ---- CRUD + history (client API) ----
  // Enough to restore the family on a new device: id, name, gender, DOB.
  listChildren(userId: string): Promise<Array<{ id: string; name: string; gender: 'boy' | 'girl' | null; dateOfBirth: string | null }>>;
  // Client keeps the id (like appointments), so an offline-created child keeps
  // its identity when it syncs and its geofences can reference it without a
  // server round-trip. Carries gender + DOB so the demographics dashboard is
  // built from real children, not just a name.
  upsertChild(
    userId: string,
    c: { id: string; name: string; gender?: 'boy' | 'girl' | null; dateOfBirth?: string | null },
  ): Promise<void>;
  deleteChild(childId: string): Promise<void>;

  listDevices(userId: string): Promise<Array<{ id: string; name: string; kind: string; childId: string | null }>>;
  createDevice(userId: string, d: { id: string; name: string; kind: string; childId?: string | null }): Promise<void>;
  deleteDevice(deviceId: string): Promise<void>;

  /**
   * «Устройство только что говорило с нами» — stamped on every ingested item
   * that a device produced.
   *
   * The fleet view has always SELECTed battery_pct and last_seen, and nothing
   * anywhere wrote them: there was no `UPDATE devices SET last_seen` in the
   * repository at all. So frame 11 printed a battery that never changed and a
   * «последний сигнал» that was empty for every device ever paired, and an
   * operator could not tell a flat watch from one that had never reported.
   *
   * [at] is the moment the payload REACHED us, not the reading's recordedAt: a
   * phone draining a three-day offline queue is talking to us now, and the
   * column is labelled with that rule in the panel.
   *
   * battery and firmware are only written when the payload carries them —
   * `COALESCE(new, old)`, never NULL over a value we already had. A watch that
   * has never reported its firmware keeps a NULL, and the panel says «не
   * сообщалась» rather than printing a dash that reads as "none".
   *
   * Returns nothing and must not throw the caller's item away: this is
   * freshness metadata about a device, not the reading itself.
   */
  touchDevice(
    deviceId: string,
    seen: { at: string; batteryPct?: number | null; firmware?: string | null },
  ): Promise<void>;

  /**
   * Frame 11's «Пометить браком», and taking it back.
   *
   * A support note on one mother's paired device — «часы неисправны» — with
   * who said so and when. NOT device_registry.status='blocked', which stops a
   * serial pairing with any account and belongs to the warehouse screen.
   *
   * Returns false when there is no such device, so the panel can say the mark
   * was NOT saved instead of showing a tick over a write that hit nothing.
   */
  markDeviceDefect(
    deviceId: string,
    mark: { at: string; by: string; note: string | null } | null,
  ): Promise<boolean>;

  // Appointments (prenatal visits, ultrasounds, lab work). User-scoped; the
  // client keeps the id so an offline-created appointment keeps its identity.
  listAppointments(userId: string): Promise<Appointment[]>;
  upsertAppointment(userId: string, a: Appointment): Promise<void>;
  appointmentOwner(id: string): Promise<{ userId: string } | null>;
  deleteAppointment(id: string): Promise<void>;

  // Medications / supplements (client keeps the id). Gives staff visibility of
  // what the mother is taking — a real safety concern in pregnancy.
  listMedications(userId: string): Promise<MedicationRow[]>;
  upsertMedication(userId: string, m: MedicationRow): Promise<void>;
  medicationOwner(id: string): Promise<{ userId: string } | null>;
  deleteMedication(id: string): Promise<void>;

  // Client keeps the geofence id (a UUID) so a zone created offline keeps its
  // identity and re-syncing upserts rather than duplicates.
  upsertGeofence(childId: string, g: Geofence): Promise<void>;
  deleteGeofence(geofenceId: string): Promise<void>;

  // Child emergency medical-ID (one row per child, upsert). listMedicalIds joins
  // the caller's children so the admin drawer can show each child's card.
  upsertChildEmergency(childId: string, m: MedicalIdRow): Promise<void>;
  listMedicalIds(userId: string): Promise<Array<{ childId: string; childName: string } & MedicalIdRow>>;
  // One child's medical-ID, or null if none saved — for restoring it on a new device.
  getChildEmergency(childId: string): Promise<MedicalIdRow | null>;

  // Newborn care events (feed/diaper/sleep), push-only upsert on (child, at, kind).
  // listNewbornEvents joins the caller's children for the admin drawer.
  recordNewbornEvent(childId: string, e: NewbornEventRow): Promise<void>;
  listNewbornEvents(userId: string, limit: number): Promise<Array<{ childId: string; childName: string } & NewbornEventRow>>;

  // Child growth measurements (weight/height), upsert on (child, day). listGrowth
  // joins the caller's children so one call serves both the admin drawer (render
  // per child) and the new-device restore (group by childId).
  upsertGrowth(childId: string, g: GrowthRow): Promise<void>;
  listGrowth(userId: string): Promise<Array<{ childId: string; childName: string } & GrowthRow>>;

  // Medication adherence — doses taken per (medication, day). upsertDose keys on
  // (medId, date); listDoses returns the caller's whole log for the admin
  // adherence view and the new-device restore.
  upsertDose(userId: string, d: DoseRow): Promise<void>;
  listDoses(userId: string): Promise<DoseRow[]>;

  // Child vaccination record (parent-marked). setVaccine adds/removes one
  // (child, key); listVaccines returns the caller's whole record (joined with
  // children) for the admin drawer and the new-device restore.
  setVaccine(childId: string, vaccineKey: string, done: boolean): Promise<void>;
  listVaccines(userId: string): Promise<Array<{ childId: string; childName: string; vaccineKey: string }>>;

  queryMetrics(userId: string, opts: { from: string; to: string; metric: string }): Promise<Array<{ t: string; value: number }>>;
  /**
   * Zone crossings for one child, newest first.
   *
   * [fromIso] is INCLUSIVE and [toIso] EXCLUSIVE — a half-open window, so a
   * crossing recorded at exactly midnight belongs to the day that is starting
   * and to exactly one day.
   *
   * The bound exists because [limit] is applied by the DATABASE, and «История
   * дня» (frame 47) asks for one day. Fetching the newest 200 rows of all time
   * and filtering to a day afterwards spends the whole window on recent
   * history: past 200 lifetime crossings the window no longer reaches
   * yesterday, and every older day answers "no crossings" beside a route that
   * still draws. A day-bounded query cannot do that, and raising the number
   * only moves the cliff.
   */
  listGeofenceEvents(
    childId: string, limit: number, fromIso?: string, toIso?: string,
  ): Promise<GeofenceEvent[]>;

  // ---- Sleep (nightly summaries) ----
  recordSleep(userId: string, s: SleepNight): Promise<void>;
  listSleep(userId: string, limit: number): Promise<SleepNight[]>;

  /**
   * The watch's activity / wellbeing day — steps, distance, calories, stress,
   * breathing rate, MET, battery, wear state.
   *
   * Everything the wrist device measures that is not a triage vital, and the
   * half of it that had no server-side home at all: it reached one panel on one
   * handset and existed nowhere else. Upsert on (user, device, day), because
   * the figures are the watch's own daily running totals.
   */
  upsertWearableDay(row: WearableDayRow & { userId: string }): Promise<void>;
  /** Her watch days, newest first — the clinician's and operator's view. */
  listWearableDays(userId: string, limit: number): Promise<WearableDayRow[]>;

  // Baby cry-analysis results (parent-recorded, newest-first). Pushed so they
  // survive a reinstall and restore on a new device — history was device-local.
  recordCry(userId: string, c: CryRow): Promise<void>;
  listCry(userId: string, limit: number): Promise<CryRow[]>;
  /**
   * «Это было верно?» — frame 17c. Applies a mother's verdict to one of HER
   * analyses, keyed by the instant. False when there is no such row, so the
   * route can answer 404 rather than accept a verdict about nothing.
   */
  recordCryVerdict(
    userId: string,
    at: string,
    verdict: CryVerdict,
    actualReason: string | null,
  ): Promise<boolean>;
  /**
   * The detector's aggregate picture over the last [days] — every user, no
   * user named. `belowThreshold` is counted against the threshold in force,
   * which is why this reads the settings row itself rather than taking one.
   */
  cryStats(days: number): Promise<CryStats>;
  /** The override row, or null when nobody has set one (= shipped default). */
  getCryThreshold(): Promise<CryThresholdRow | null>;
  setCryThreshold(v: { minConfidence: number; updatedBy: string }): Promise<void>;

  // ---- Maternal weight log (one row per day, upsert on the date) ----
  recordWeight(userId: string, w: WeightRow): Promise<void>;
  listWeight(userId: string, limit: number): Promise<WeightRow[]>;

  // ---- Pregnancy timed sessions (append-only, upsert on ended_at) ----
  recordKickSession(userId: string, s: KickSessionRow): Promise<void>;
  listKickSessions(userId: string, limit: number): Promise<KickSessionRow[]>;
  recordContractionSession(userId: string, s: ContractionSessionRow): Promise<void>;
  listContractionSessions(userId: string, limit: number): Promise<ContractionSessionRow[]>;

  // ---- Women's-health day logs (mood / symptoms / kicks / flow) ----
  upsertDayLog(userId: string, log: DayLogRow): Promise<void>;
  listDayLogs(userId: string, from: string, to: string): Promise<DayLogRow[]>;

  // ---- Postpartum screening (EPDS): score + band + date, never the answers ----
  //
  // Read per person, newest first, and never across people: there is no
  // `epdsStats`, no cohort count and no "mothers scoring 13+" list, deliberately
  // — see db/migrations/049_epds.sql.
  upsertEpds(userId: string, row: EpdsRow): Promise<void>;
  listEpds(userId: string, limit: number): Promise<EpdsRow[]>;

  // ---- Child safety alerts (zone enter/exit history) ----
  // ---- Support (frame 12) ----
  //
  // The queue is oldest-unanswered-first, so it is read whole and sorted in the
  // module rather than by a filter here — an operator's board is a few hundred
  // rows at most, and paging it would hide the oldest ticket, which is the one
  // the screen exists to surface.
  listSupportTickets(limit: number): Promise<SupportTicketRow[]>;
  /**
   * Her own tickets, newest first — frame 43, the receiving end of the desk.
   *
   * Filtered by user_id and NEVER by a matching phone. A ticket raised from
   * WhatsApp by somebody who typed the same number, or one an operator recorded
   * against a number that later changed hands, is not hers to read; matching on
   * a phone would hand a stranger's support conversation to whoever signs in
   * with that number next. Tickets with user_id NULL therefore reach nobody's
   * app, which is the correct trade.
   */
  listSupportTicketsForUser(userId: string, limit: number): Promise<SupportTicketRow[]>;
  getSupportTicket(id: string): Promise<SupportTicketRow | null>;
  createSupportTicket(t: NewSupportTicket): Promise<string>;
  /** Patch only the keys present; absent leaves the column alone. */
  updateSupportTicket(id: string, patch: SupportTicketPatch): Promise<boolean>;
  listSupportReplies(ticketId: string): Promise<SupportReplyRow[]>;
  addSupportReply(r: NewSupportReply): Promise<void>;
  /**
   * She opened the thread. Sets customer_read_at and NOTHING else.
   *
   * Separate from updateSupportTicket on purpose, twice over: the status is the
   * operator's queue state and must not move because she looked, and
   * updateSupportTicket bumps updated_at, which the board sorts on — reading
   * would otherwise shuffle her ticket to the top of somebody's screen with
   * nothing new in it.
   */
  markSupportTicketRead(id: string, at: string): Promise<boolean>;
  listSupportTemplates(): Promise<SupportTemplateRow[]>;

  recordAlert(userId: string, a: SafetyAlertRow): Promise<void>;
  /**
   * The user's alert feed, newest first, optionally bounded to one day —
   * [fromIso] INCLUSIVE, [toIso] EXCLUSIVE, like listGeofenceEvents.
   *
   * The bound matters more here than anywhere: alerts are stored per USER, so
   * one row is written for every crossing of every child on the account. «Ис-
   * тория дня» reads this for the day's SOS presses, and a family of three
   * spends an unbounded window three times as fast. Without the bound the
   * screen loses an SOS off an older day — a red mark on the timeline that a
   * parent has already been shown once and would not think to doubt.
   */
  listAlerts(
    userId: string, limit: number, fromIso?: string, toIso?: string,
  ): Promise<SafetyAlertRow[]>;
  /**
   * Close an SOS with the parent's verdict (frame 48). Keyed on child + instant
   * because that pair is what the client has — the alert feed carries no id.
   *
   * Returns false when no such SOS exists, so the screen can say the save
   * failed instead of showing a tick over a write that matched nothing.
   */
  setAlertOutcome(
    userId: string, childId: string, at: string, outcome: SosOutcome,
  ): Promise<boolean>;

  // ---- Profile ----
  getProfile(userId: string): Promise<ProfileRow | null>;
  /**
   * Update the editable half of the profile. The phone is deliberately absent
   * from [ProfileEdit] and MUST be left exactly as sign-in wrote it — see the
   * type for what changing it costs.
   */
  upsertProfile(userId: string, p: ProfileEdit): Promise<void>;

  // ---- Device → child reassignment (tracker tag ownership) ----
  reassignDevice(deviceId: string, childId: string | null): Promise<void>;

  // ---- Admin / back-office ----
  adminStats(): Promise<{ activeUsers: number; devicesOnline: number; alertsToday: number; ingestLastHour: number }>;
  /** Aggregate child demographics (count, gender split, age buckets) as of [asOf] (ISO). */
  childrenStats(asOf: string): Promise<ChildrenStats>;
  recentEmergencies(limit: number): Promise<AdminEmergency[]>;
  // Acknowledge an emergency (staff). Idempotent; returns false if it was
  // already acknowledged. The id is the underlying metric row id, so an ack
  // needs no change to the safety/ingest path — it is an overlay.
  acknowledgeEmergency(id: string, staffId: string, at: string): Promise<boolean>;
  adminListUsers(q: string, limit: number, offset: number): Promise<{ total: number; users: Array<{ id: string; displayName: string; phone: string | null; dueDate: string | null; lastMetricAt: string | null; latestSeverity: string | null }> }>;
  adminUserHealth(userId: string): Promise<{ latest: Record<string, number | null>; triage: Array<{ code: string; severity: string; at: string }> } | null>;
  /// Everything the back-office needs about one family in a single call. The
  /// dashboard used to show a name and some vitals; support answering "what is
  /// going on with this account" needs the children, devices, zones and recent
  /// safety events too.
  adminUserDetail(userId: string): Promise<AdminUserDetail | null>;

  /// Every band and tracker across all accounts, for the fleet view.
  adminDevices(limit: number): Promise<AdminDevice[]>;

  /// Safety events across all families, newest first — the SOS and geofence
  /// feed that a duty operator watches.
  adminSafetyEvents(limit: number): Promise<AdminSafetyEvent[]>;

  /// Engagement and growth counters for the analytics view.
  adminAnalytics(): Promise<AdminAnalytics>;

  /// Erase a user and everything belonging to them.
  ///
  /// The app's reset told her "all data will be erased" while only clearing the
  /// phone; nothing on the server was ever deleted. Every table that references
  /// users(id) cascades, so this single delete removes her profile, her
  /// readings, her children, their location history and their geofences —
  /// which is what the sentence already promised.
  ///
  /// Returns false when there was no such user, so a caller can tell "erased"
  /// from "there was nothing to erase" instead of reporting success either way.
  deleteAccount(userId: string): Promise<boolean>;

  /// Product metrics for the overview: DAU/WAU/MAU, growth, retention,
  /// engagement mix. Definitions live in analytics/biMetrics.ts so this
  /// implementation and the in-memory one cannot drift apart on what
  /// "retention" means.
  adminBiMetrics(): Promise<BiMetrics>;

  /// The business snapshot behind the Dashboard: who the users are, what they
  /// own, where they are, and what the shop has done. One call rather than the
  /// panel stitching six endpoints together, so every number on the screen is
  /// as of the same instant.
  dashboardSnapshot(asOf: string): Promise<DashboardSnapshot>;

  // ---- Timeline content (the CMS) ----
  /// The whole catalogue, keyed by stage (`w1`..`w40`, `m0`..`m60`).
  contentCatalog(): Promise<Record<string, ContentItemRow[]>>;
  /// Replace one stage's items outright. Editing is per stage, so a save can
  /// never partially apply across stages.
  putStageContent(stageKey: string, items: ContentItemRow[]): Promise<void>;

  // ---- Pregnancy calendar overrides (frames 14a / 14b) ----
  /// Every edited week, ascending. Overrides ONLY — the shipped contract
  /// (packages/contract/pregnancy_weeks.json) is the baseline and is not in
  /// here, so an empty list means "nothing has been edited", never "the
  /// calendar is empty". See pregnancy/overrides.ts for the merge.
  pregnancyWeekOverrides(): Promise<PregnancyWeekOverride[]>;
  /// Write one week. `rev` is the store's business — it increments — so the
  /// caller supplies the content and who wrote it, nothing else.
  putPregnancyWeekOverride(v: {
    week: number;
    lengthCm: string | null;
    hcg: string | null;
    ru: PregnancyWeekTextRow;
    kk: PregnancyWeekTextRow;
    draft: boolean;
    review: { by: string; at: string; fingerprint: string } | null;
    updatedBy: string;
  }): Promise<void>;
  /// How many mothers are in each gestational week TODAY, from `users.due_date`.
  ///
  /// This is what turns «поправить неделю 22» into «это увидят N мам» — the
  /// one number that tells an editor whether a change is urgent. Weeks nobody
  /// is in are absent from the map rather than present as zero, so a caller
  /// reporting «0 мам» is reporting a real count and not a missing key.
  pregnancyWeekMotherCounts(): Promise<Record<number, number>>;

  // ---- Emergency-help overrides (frame 16b → app screen 37) ----
  /// Every edited scenario, by id ascending. Overrides ONLY — the shipped
  /// contract (packages/contract/emergency_help.json) is the baseline and is
  /// not in here, so an empty list means "nothing has been edited", never
  /// "there is no first aid". See emergency/overrides.ts for the merge.
  emergencyHelpOverrides(): Promise<EmergencyHelpOverride[]>;
  /// Write one scenario. `rev` is the store's business — it increments — so the
  /// caller supplies the content and who wrote it, nothing else.
  putEmergencyHelpOverride(v: {
    id: string;
    severity: 'red' | 'amber';
    sort: number;
    ru: EmergencyTextRow;
    kk: EmergencyTextRow;
    draft: boolean;
    review: { by: string; at: string; fingerprint: string } | null;
    updatedBy: string;
  }): Promise<void>;

  // ---- Vaccination schedule overrides (frames 15 / 15a / 15b) ----
  /// Every edited or added injection, by key ascending. Overrides ONLY — the
  /// shipped contract (packages/contract/vaccination_schedule.json) is the
  /// baseline and is not in here, so an empty list means "nothing has been
  /// edited", never "there is no schedule". See vaccination/overrides.ts.
  vaccinationOverrides(): Promise<VaccinationOverride[]>;
  /// Write one injection, and record the before/after in the log. `rev` is the
  /// store's business — it increments — so the caller supplies the content and
  /// who wrote it, nothing else.
  ///
  /// `key`, `id` and `dose` are IDENTITY: on an existing row they are not
  /// updated. A mother's tick is filed under `<id>/<dose>`, so re-keying a row
  /// would orphan every tick recorded against it.
  putVaccinationOverride(v: {
    key: string;
    id: string;
    dose: number | null;
    atMonth: number;
    ru: VaccineTextRow;
    kk: VaccineTextRow;
    added: boolean;
    draft: boolean;
    review: { by: string; at: string; fingerprint: string } | null;
    updatedBy: string;
  }): Promise<void>;
  /// The catch-up window, or null when nobody has changed it — which means
  /// "the contract's value", and is a different statement from "1 month".
  vaccinationSettings(): Promise<VaccinationSettings | null>;
  putVaccinationSettings(v: { dueWindowMonths: number; updatedBy: string }): Promise<void>;
  /// Frame 15b, newest first.
  vaccinationScheduleLog(limit: number): Promise<VaccinationLogEntry[]>;
  /// The two histograms behind the coverage column — see
  /// vaccination/coverage.ts for why they are histograms and not rows, and for
  /// the warning that every figure drawn from them is SELF-REPORTED by mothers
  /// in the app rather than read from a clinic.
  vaccinationCoverage(): Promise<VaccinationCoverageData>;

  // ---- Broadcasts (frame 06 «Маркетинг») ----
  /// Every broadcast, newest first, drafts included. `delivered` is read off
  /// the ledger, so it is what actually went out rather than what was hoped
  /// for — a published broadcast whose whole audience was inside the weekly
  /// gap honestly reads 0.
  listBroadcasts(limit: number): Promise<BroadcastRow[]>;
  /// Create or replace a DRAFT. Publishing is its own call: a save must never
  /// be able to send, or an editor fixing a typo would send the message twice.
  /// Implementations refuse to overwrite a published row.
  saveBroadcast(v: {
    id: string;
    titleRu: string;
    bodyRu: string;
    titleKk: string | null;
    bodyKk: string | null;
    segment: BroadcastSegment;
    createdBy: string;
  }): Promise<void>;
  /// How many people the segment covers, and how many of them are inside the
  /// weekly gap and would therefore be skipped. Both numbers, always: a
  /// «получателей: 40» that silently means 12 is the number this feature is
  /// most likely to be wrong about.
  broadcastAudience(segment: BroadcastSegment): Promise<{ matched: number; excluded: number }>;
  /// Send it. Writes one delivery row per recipient, flips the status, and
  /// returns what happened — including [userIds] so the caller can push to
  /// exactly the people who were recorded as delivered. Null when there is no
  /// such broadcast. Already-published rows are the route's business, not this
  /// one's: it is idempotent per person by primary key.
  publishBroadcast(id: string): Promise<{
    matched: number;
    excluded: number;
    delivered: number;
    userIds: string[];
  } | null>;
  /// What this woman has been sent — the app's «Центр уведомлений». Both
  /// languages travel, because she may change hers after the message arrives
  /// and a cached copy in the wrong language is a bug she cannot fix.
  listAnnouncements(userId: string, limit: number): Promise<AnnouncementRow[]>;

  // ---- Notifications (frame 25 «Уведомления» → app screen 39) ----
  /// Her switches and the timezone to read the quiet hours in.
  ///
  /// NEVER throws for a woman who has never opened the screen: no row means
  /// DEFAULT_PREFS, everything on. An install that predates the table must not
  /// lose the alerts it was already receiving because nobody has saved
  /// anything yet — and a missing row must never read as "she muted it".
  getNotificationPrefs(userId: string): Promise<NotificationPrefsRow>;
  /// Save what she chose. Upsert on user_id; the app sends the whole object,
  /// so there is no partial-update path to get wrong.
  putNotificationPrefs(userId: string, prefs: NotificationPrefs): Promise<void>;
  /// Write the clock her quiet hours are read against — `users.timezone`.
  ///
  /// THE OTHER HALF OF getNotificationPrefs. That column was READ by the push
  /// gate and written by nothing: no route accepted a zone, no INSERT supplied
  /// one, so every woman in the product was evaluated as if she were in
  /// Asia/Almaty. For a mother in Berlin that is quiet hours applied three or
  /// four hours early — exactly wrong rather than merely absent, which is the
  /// failure the column exists to prevent.
  ///
  /// [timezone] is an IANA name the caller has already validated; the
  /// repository stores what it is given.
  setUserTimezone(userId: string, timezone: string): Promise<void>;
  /// Record one attempt — INCLUDING the ones the gate held.
  ///
  /// Held attempts are the point. A ledger of only the sends can say how many
  /// went out and can never answer «почему ей не пришло», which is the
  /// question a support desk actually receives.
  recordPushDelivery(row: PushDeliveryRecord): Promise<void>;
  /// The back-office summary over the last [days]. Counted rows only: a kind
  /// nothing happened to is absent rather than printed as a row of zeros.
  pushDeliverySummary(days: number): Promise<PushDeliverySummary>;

  /**
   * Record a back-office action.
   *
   * [reason] is why a person opened somebody's health record or last known
   * location — required by the routes that serve those, optional here because
   * most actions (listing orders, editing a lesson) are self-explaining.
   * Nullable in the column too: rows written before it existed have no reason,
   * and inventing one for them would make the old log look answered.
   */
  writeAudit(entry: { staffId: string; action: string; target?: string; reason?: string }): Promise<void>;
  /**
   * One page of the log, newest first.
   *
   * [offset] skips that many of the newest entries, so a reviewer can walk
   * backwards through time. The ordering is a stable TOTAL order, not merely
   * `at DESC`: two rows written in the same instant — which happens, the
   * column defaults to now() and one request can write twice — would otherwise
   * be free to swap places between two page requests, and a row that swaps
   * across a page boundary is a row shown twice or a row never shown at all.
   * That is not an acceptable failure in an audit log.
   */
  listAudit(limit: number, offset?: number): Promise<AuditPage>;
  /**
   * The reads of health and of a child's whereabouts inside a window.
   *
   * Frame 22 counted protected reads by pulling the newest 5 000 rows of the
   * WHOLE log and filtering them in memory against a window of up to a year.
   * The log is dominated by ordinary traffic — every open of the user list, of
   * the support tab, and the throttled emergency feed from every open tab,
   * writes to it — so 5 000 rows is days, not a year. Whoever answers a
   * regulator set the window to twelve months, read «Защищённых просмотров: 12
   * · без причины: 0», and concluded that no health record had been opened
   * unexplained all year, when the query had never looked past last week.
   * Silent under-reporting, on the one screen whose whole job is to report.
   *
   * Filtered in SQL on both axes instead. [actions] is PROTECTED_ACTIONS, so
   * only special-category rows come back — a small fraction of the table — and
   * a year of those fits where a year of everything cannot.
   *
   * COST: one index scan on (action, at DESC), added by migration 050. Without
   * that index this is a filtered scan of an append-only table with no upper
   * bound, which is why the index ships in the same change.
   *
   * [limit] still applies, and hasMore still means "there is at least one row
   * past this page" — taken as one row past the page, never a count. A caller
   * that discards it is back to the bug this replaced, so the callers SAY on
   * screen when it is true rather than printing a partial count as a total.
   */
  listProtectedAudit(actions: readonly string[], sinceIso: string, limit: number): Promise<AuditPage>;

  // ---- Shop (device store) ----
  /// Active products with every colour variant (in- and out-of-stock), for the
  /// public storefront. Out-of-stock variants are returned too so the page can
  /// show them disabled rather than hiding a colour that will restock.
  ///
  /// Carries the catalogue fields an operator edits in frame 08a — name_kk,
  /// stage, the age band, descriptions — because the app renders them. Never
  /// cost or margin: this feeds an unauthenticated route.
  shopProducts(): Promise<ShopProduct[]>;
  /// Place a COD order. Atomic: each variant row is locked, stock checked and
  /// decremented, then the order + item snapshots are written — all or nothing,
  /// so two buyers cannot oversell the last unit. Returns the order id + total,
  /// or a typed failure (empty cart / unknown variant / insufficient stock).
  placeShopOrder(o: ShopOrderInput): Promise<ShopOrderResult>;
  adminShopVariants(): Promise<Array<ShopVariant & { productId: string; productName: string }>>;

  // ---- Catalogue (frames 08 / 08a / 08b) ----
  //
  // Deliberately NO second product read. adminProducts() already returns every
  // product with its stock and variants, and the catalogue fields are now on
  // InventoryProduct — one answer to "what is a product", rather than two that
  // drift.
  /** Patch only the keys present. Absent ≠ null: absent leaves the column alone. */
  updateProduct(id: string, patch: ProductPatch): Promise<void>;
  listShopCategories(): Promise<ShopCategoryRow[]>;
  upsertShopCategory(c: ShopCategoryRow): Promise<void>;
  /**
   * Returns false when the category still has products — the panel then says
   * which, instead of orphaning them. «Ничего не удаляется» applies to things
   * with history; an empty category has none.
   */
  deleteShopCategory(id: string): Promise<boolean>;
  /// Set an absolute count. Kept because a stocktake genuinely knows the total
  /// rather than the difference; it writes a 'correction' move for the delta so
  /// the ledger and the running total cannot drift apart.
  setShopVariantStock(variantId: string, stock: number, by?: StockMoveAuthor): Promise<void>;
  addShopVariant(productId: string, color: string, colorHex: string, stock: number): Promise<void>;

  // ---- The Ма!Ма! course ----
  /// [publishedOnly] is what the app asks for; the panel asks for everything so
  /// a draft can be worked on without appearing half-finished to a buyer.
  courseLessons(course: string, publishedOnly: boolean): Promise<CourseLesson[]>;
  upsertCourseLesson(l: {
    id?: string;
    course: string;
    titleRu: string;
    titleKk?: string | null;
    youtubeUrl: string;
    summaryRu?: string | null;
    summaryKk?: string | null;
    sort?: number;
    published?: boolean;
  }): Promise<{ id: string }>;
  deleteCourseLesson(id: string): Promise<void>;
  /**
   * How many people have watch history against this lesson.
   *
   * The one question that decides whether a lesson may be deleted at all.
   * «Ничего не удаляется … Полное удаление доступно только для сущностей без
   * истории (неопубликованный урок, черновик)» — and a lesson somebody has
   * watched has history: her progress rows point at it by id, so removing it
   * leaves her course showing a place she got to in a lesson that is gone.
   */
  courseLessonWatchers(lessonId: string): Promise<number>;

  /// How far this phone has got, one row per lesson she has opened.
  ///
  /// Phone-keyed like the entitlement: a reinstall or a new device signs in
  /// with the same number and finds its place again.
  courseProgress(phone: string): Promise<CourseProgress[]>;
  /// Records a position. [completed] only ever goes false→true — rewatching the
  /// opening of a finished lesson must not un-finish it — and the stored
  /// position never moves backwards on its own, so a player that reports 0 while
  /// it is still loading cannot erase where she was.
  saveCourseProgress(p: {
    phone: string;
    lessonId: string;
    positionSeconds: number;
    durationSeconds?: number | null;
    completed?: boolean;
  }): Promise<void>;
  /// The back-office read: everyone who has started the course, most recent
  /// first, with enough to answer "is she actually watching it?".
  courseProgressSummary(limit: number): Promise<Array<{
    phone: string;
    started: number;
    completed: number;
    lastLessonId: string | null;
    lastLessonTitle: string | null;
    lastAt: string;
  }>>;

  // ---- Entitlements (what a purchase unlocks in the app) ----
  /// Does this phone own [feature]? Phone, not user id: an order is placed
  /// before an account exists, and the two are joined by the number.
  hasEntitlement(phone: string, feature: string): Promise<boolean>;
  grantEntitlement(e: {
    phone: string;
    feature: string;
    orderId?: string;
    grantedBy?: string;
    note?: string;
  }): Promise<void>;
  /// Taken back after a refund, or when it was granted by mistake.
  revokeEntitlement(phone: string, feature: string): Promise<void>;
  listEntitlements(feature: string, limit: number): Promise<Array<{
    phone: string;
    feature: string;
    orderId: string | null;
    grantedBy: string | null;
    note: string | null;
    at: string;
  }>>;

  // ---- Inventory ----
  /// Every product with its price, cost, kind and stock — the warehouse view,
  /// including inactive ones, which is where an archived product has to be
  /// visible to be un-archived.
  adminProducts(): Promise<InventoryProduct[]>;
  /**
   * Units SOLD per product since [sinceIso] — how fast the shelf is emptying.
   *
   * Read off the stock ledger's `sale` rows rather than off orders: a unit
   * handed over the counter and booked as a sale counts the same as one
   * shipped against an order, and both are already recorded there.
   *
   * Positive counts. The ledger stores −3 for three sold; a caller asking "how
   * many went out" should not have to remember the sign.
   *
   * Products with no sales in the window are simply absent from the result —
   * absent and zero mean the same thing here, and materialising a row for every
   * product in the catalogue to say "none" is work with no reader.
   */
  soldUnitsSince(sinceIso: string): Promise<Record<string, number>>;
  upsertProduct(p: {
    id: string;
    name: string;
    priceMinor: number;
    costMinor?: number | null;
    sku?: string | null;
    kind?: 'simple' | 'bundle';
    lowStockThreshold?: number;
    active?: boolean;
    sort?: number;
  }): Promise<void>;
  /// What a bundle is made of. Empty for a simple product.
  bundleParts(bundleId: string): Promise<Array<{ partId: string; partName: string; qty: number }>>;
  setBundleParts(bundleId: string, parts: Array<{ partId: string; qty: number }>): Promise<void>;
  /// Move stock by a signed delta, writing the ledger row. Refuses to take a
  /// variant below zero — the ledger must never describe an impossible state.
  moveStock(m: {
    variantId: string;
    delta: number;
    reason: StockMoveReason;
    note?: string;
    staffId?: string;
    orderId?: string;
  }): Promise<{ ok: true; stock: number } | { ok: false; error: 'insufficient_stock' | 'unknown_variant' }>;
  /**
   * The ledger, newest first, optionally for one variant.
   *
   * [sinceIso] bounds it from below, INCLUSIVE — «движения за день» (frame 07)
   * needs the day's rows and the day's totals, and a caller that asks for "the
   * last 100" and adds them up prints a total for a period it cannot name. The
   * bound is an instant, not a date: the operator's midnight is theirs, and a
   * server that decides where the day starts gets it wrong for half the year.
   */
  stockMoves(limit: number, variantId?: string, sinceIso?: string): Promise<StockMove[]>;

  // ---- Поставки (migration 045, frames 07a / 07g) ----
  //
  // The warehouse could answer "what is on the shelf" and "how long will it
  // last". It could not answer the third question, which is the one that
  // decides whether to order today: "what is already coming". Without it the
  // panel printed «пора заказывать» beside goods ordered a fortnight ago.

  /// Everyone who supplies us, newest last. Includes archived ones — an
  /// archived supplier still owns the history of the orders placed with them.
  listSuppliers(): Promise<Supplier[]>;
  /**
   * Add or edit one. Returns the id, so the caller can order from a supplier
   * it has just created without a second read.
   *
   * [leadTimeDays] is the term the SUPPLIER DECLARED, not one derived from
   * history: no placed→received pair exists in this database yet, and an
   * average computed from nothing would be a number a buyer plans money
   * against. Null means "did not say", and the panel falls back to the
   * warehouse's standing 14 days and labels it as such.
   *
   * [active] absent means "leave it as it is". The panel's add form sends no
   * `active`, and an add that silently un-archived a supplier somebody
   * deliberately retired would put them back in the order dropdown.
   *
   * `name_taken` rather than a thrown constraint violation: `lower(name)` is
   * UNIQUE in Postgres (045_supply.sql), so renaming Alpha to Beta is a
   * refusal the operator has to be told about by name, not a 500.
   */
  upsertSupplier(s: {
    id?: string;
    name: string;
    contact?: string | null;
    leadTimeDays?: number | null;
    active?: boolean;
  }): Promise<{ ok: true; id: string } | { ok: false; error: 'name_taken' }>;

  /// Orders with their lines, newest first. One read, because a list that
  /// fetched its items per row would issue a query per shipment on every render.
  listPurchaseOrders(limit: number): Promise<PurchaseOrder[]>;
  /// One order with its lines, or null.
  purchaseOrderById(id: string): Promise<PurchaseOrder | null>;
  /**
   * A new order, as a draft. Refuses an empty one and an unknown variant:
   * half an order is worse than none, because the half that saved looks like
   * a placed shipment.
   */
  createPurchaseOrder(po: {
    supplierId?: string | null;
    expectedAt?: string | null;
    note?: string | null;
    createdBy?: string | null;
    items: Array<{ variantId: string; qtyOrdered: number; unitCostMinor?: number | null }>;
  }): Promise<{ ok: true; id: string } | { ok: false; error: 'no_items' | 'unknown_variant' }>;
  /**
   * Move an order's status. Returns false when there is no such order, so a
   * panel button cannot report a shipment as placed because the request
   * reached a 200 that did nothing.
   *
   * `placed` stamps `placed_at` — the first half of the pair that will one day
   * let this schema measure a real lead time instead of a declared one.
   */
  setPurchaseOrderStatus(id: string, status: PurchaseOrderStatus): Promise<boolean>;
  /**
   * Close one line of an order with what actually arrived, and say whether
   * that was the last open line.
   *
   * The line closes even when the delivery was short: the shortfall is already
   * a claim recorded against the receipt, and keeping the order open over two
   * missing units would show them as "in transit" forever.
   */
  receivePurchaseOrderLine(poId: string, variantId: string, qtyReceived: number): Promise<{
    ok: boolean;
    /** The order's status AFTER this line — 'received' once every line is closed. */
    status: PurchaseOrderStatus | null;
    /** What the order asked this supplier for, which is the receipt's comparison basis. */
    qtyOrdered: number | null;
  }>;
  /**
   * Units on the water, per variant id — open lines of PLACED orders only.
   *
   * NEVER added to `shop_variants.stock` or to a runway: a box in customs is
   * not a shelf, and a forecast that counts it promises stock nobody can ship
   * today. It exists so the panel can say «заказ уже размещён» instead of
   * «пора заказывать», which is a different sentence about the same shelf.
   */
  inTransitByVariant(): Promise<Record<string, number>>;
  adminShopOrders(limit: number): Promise<ShopOrder[]>;
  /**
   * One page of frame 02 «Заказы», plus the two numbers the screen states.
   *
   * `total` is how many orders match the CURRENT filter, so the footer can say
   * «Показано 25 из 284» honestly; `counts` is every status counted over the
   * WHOLE table, unfiltered, because the filter chips carry live counters and a
   * counter that changed when you clicked it would be useless.
   *
   * Separate from [adminShopOrders] rather than replacing it: the dashboard,
   * the finance report and the owner screen all want "the last N orders" with
   * no paging at all, and giving them a page object would make four screens
   * carry a total none of them prints.
   */
  adminShopOrderPage(q: {
    limit: number;
    offset: number;
    status?: ShopOrderStatus;
  }): Promise<ShopOrderPage>;
  /// One order for frame 03, or null. Same shape as a row of the list.
  shopOrderById(id: string): Promise<ShopOrder | null>;
  /**
   * The order's status history, oldest first — the frame 03 timeline.
   *
   * Empty for every order that changed status before migration 039 existed;
   * that gap is real and the card says so rather than drawing a delivered
   * order as though nothing ever happened to it.
   */
  shopOrderEvents(orderId: string): Promise<ShopOrderEvent[]>;
  /**
   * Frame 05a — take a комплект back and give the money back, in ONE
   * transaction: the refund row, plus a +qty stock move per restocked line
   * carrying reason='return', the order id AND this refund's id.
   *
   * Atomic on purpose. A refund row with no stock move means the money left and
   * the shelf never learned; a stock move with no refund row is a unit that
   * appears from nowhere and is counted as a return by frame 05 with no amount
   * behind it. Half of this is worse than none of it.
   *
   * [restock] may be empty — a broken unit that is refunded and binned does not
   * go back on the shelf, and pretending it did would sell it again.
   *
   * WHAT THIS DOES NOT DO, and why the panel says so:
   *  · does not touch the device registry. It has three states — stock / sold /
   *    blocked (routes/inventory.ts) — and none of them is «вернули», so a
   *    serial keeps saying «Активировано».
   *  · does not revoke the course. Entitlement is granted on dispatch and is
   *    removed only by a person (DELETE /admin/entitlements/...): a mother
   *    losing her course because a box came back is not a decision this makes.
   *  · does not move the order's status. A refunded order was still delivered.
   */
  recordOrderRefund(r: {
    orderId: string;
    amountMinor: number;
    reason: OrderRefundReason;
    note?: string | null;
    staffId?: string | null;
    restock?: Array<{ variantId: string; qty: number }>;
  }): Promise<OrderRefundResult>;
  /// One order's refunds, newest first. Empty when it has none.
  orderRefunds(orderId: string): Promise<OrderRefund[]>;
  /**
   * Every refund booked in an inclusive date window, newest first.
   *
   * Dates are UTC `YYYY-MM-DD`, matching how admin/finance.ts buckets orders
   * and stock moves. Unlike those two this is NOT a newest-N slice: refunds are
   * rare, the whole window is read, so «Возвращено денег» is never a floor.
   */
  refundsBetween(fromDate: string, toDate: string): Promise<OrderRefund[]>;
  /**
   * Move an order's status, recording WHO moved it and from what.
   *
   * [staffId] is optional because the storefront and the app can move an order
   * with no member of staff involved; the timeline prints «система» for those
   * rather than inventing an author.
   */
  setShopOrderStatus(orderId: string, status: ShopOrderStatus, staffId?: string): Promise<void>;
  /**
   * One customer's own orders, newest first — screen 42.
   *
   * By PHONE, because that is what an order carries: the shop takes orders
   * from the landing page as well as the app, and the woman who ordered on a
   * laptop before installing anything is the same customer. Matching on a
   * user id would show her an empty screen and a charge on her card.
   *
   * [phone] must already be normalised; the caller holds the one normaliser.
   */
  shopOrdersByPhone(phone: string, limit: number): Promise<ShopOrder[]>;

  /// Landing-page callback requests. Recording one can never fail on stock or
  /// availability — the whole point is to capture the number before the visitor
  /// leaves — so this returns the id rather than a typed failure.
  recordShopLead(lead: ShopLeadInput): Promise<{ id: string }>;
  adminShopLeads(limit: number): Promise<ShopLead[]>;
  /**
   * How many callback requests there are, and how many nobody has rung yet —
   * over the WHOLE table, not over a page.
   *
   * `adminShopLeads(limit)` was the only accessor, so «не обработано: N» on the
   * Магазин tab was counted over one page and printed as a total. The page is
   * newest-first, so what falls off it are the OLDEST uncalled leads: exactly
   * the women who have waited longest. The true count did exist — on
   * /admin/dashboard, which requires `finance`, and seller, operator and
   * support (the roles that actually work this queue) do not hold it.
   *
   * Two numbers in one read rather than two calls: they are printed in one
   * sentence («43 · не обработано: 12»), and counted a moment apart they can
   * disagree.
   */
  shopLeadCounts(): Promise<{ total: number; uncalled: number }>;
  setShopLeadStatus(leadId: string, status: ShopLeadStatus): Promise<void>;

  /// Store settings — WhatsApp number, Kaspi link, and any other keys the admin
  // ---- Staff sign-in (phone + password) ----
  /// The account for a normalised phone, or null. Includes the hash, so it is
  /// only ever called from the login path.
  // ---- App sign-in (phone number, no SMS) ----
  /// The account for this normalised phone, or null.
  userByPhone(phone: string): Promise<{ id: string; displayName: string } | null>;
  /// Create one. The phone IS the identity; email is left null on purpose
  /// rather than invented (migration 020).
  createUserWithPhone(a: { phone: string; displayName: string }): Promise<{ id: string; displayName: string }>;
  createUserSession(s: {
    tokenHash: string;
    userId: string;
    expiresAt: Date;
    userAgent: string;
  }): Promise<void>;
  /// Who is holding this token — the app's equivalent of staffBySessionToken.
  userBySessionToken(tokenHash: string): Promise<{ userId: string } | null>;
  deleteUserSession(tokenHash: string): Promise<void>;
  /// Claims from this phone inside the window — the rate limit on registering.
  // ---- Which devices are ours (migration 028) ----
  /// What the registry knows about this serial, or null when it is not ours.
  ///
  /// [serial] is normalised by [normalizeSerial] before it gets here, because a
  /// MAC is printed six different ways and a registry that misses a unit over
  /// punctuation refuses a real customer.
  deviceRegistryEntry(serial: string): Promise<DeviceRegistryRow | null>;
  /// Add units received into stock. Idempotent per serial: receiving the same
  /// shipment twice must not create a second row or reset a unit already sold.
  addDeviceSerials(rows: Array<{
    serial: string;
    kind?: 'band' | 'tag' | null;
    activationCode?: string | null;
    note?: string | null;
    addedBy?: string | null;
  }>): Promise<{ added: number; skipped: number }>;
  /// Bind a unit to the account that just paired it. Returns false when it was
  /// already taken by somebody else, which is what makes an activation code
  /// single-use.
  markDeviceActivated(serial: string, phone: string): Promise<boolean>;
  setDeviceRegistryStatus(serial: string, status: 'stock' | 'sold' | 'blocked'): Promise<void>;
  /// Record which physical units went out with an order.
  ///
  /// Done at DISPATCH, not at intake: at intake there is no order yet. This is
  /// the link that lets support answer "she says her tracker is broken — which
  /// one did we send her, and when?", which nothing could answer before.
  ///
  /// Returns the serials it did NOT recognise, so the packer is told rather
  /// than a typo being swallowed into a row nobody will ever look at.
  assignDevicesToOrder(orderId: string, serials: string[]): Promise<{ linked: string[]; unknown: string[] }>;
  /// The units sent with an order. The other direction of the same question.
  devicesForOrder(orderId: string): Promise<DeviceRegistryRow[]>;
  listDeviceRegistry(limit: number): Promise<DeviceRegistryRow[]>;
  /// The unit carrying this activation code, or null. For the fallback path:
  /// units already in the wild whose serial nobody captured.
  deviceByActivationCode(code: string): Promise<DeviceRegistryRow | null>;

  recentPhoneClaims(phone: string, since: Date): Promise<number>;
  recordPhoneClaim(phone: string): Promise<void>;

  /// Store the code we just sent, replacing any live one for this number.
  ///
  /// Hashed, like a password: this row is readable by anything that can read
  /// the database, and a six-digit code in plaintext beside a phone number is a
  /// working key to that account.
  putPhoneCode(c: { phone: string; codeHash: string; expiresAt: Date }): Promise<void>;

  /// Check a code and, if it matches, CONSUME it so it cannot be replayed.
  ///
  /// Returns why it failed rather than a bare boolean, because the three
  /// reasons need different words on screen: 'expired' asks her to send a new
  /// one, 'too_many' has locked the code, and 'wrong' is a typo.
  usePhoneCode(phone: string, codeHash: string, now: Date):
    Promise<'ok' | 'wrong' | 'expired' | 'too_many' | 'none'>;

  staffByPhone(phone: string): Promise<StaffAccount | null>;
  staffById(id: string): Promise<StaffAccount | null>;
  /// Create or update an account. Used by the seeding script.
  upsertStaffAccount(a: {
    phone: string;
    passwordHash: string;
    role: StaffRole;
    displayName?: string;
  }): Promise<void>;
  /// Create, and fail if the phone is taken. Deliberately NOT upsert: adding a
  /// colleague who already has an account must not silently reset their
  /// password and change their role.
  createStaffAccount(a: {
    phone: string;
    passwordHash: string;
    role: StaffRole;
    displayName: string;
  }): Promise<{ id: string } | null>;
  /// The roster the panel shows. No password hash: it has no business leaving
  /// this layer, and the panel has no use for it.
  listStaffAccounts(): Promise<StaffSummary[]>;
  /// Only the fields given are touched.
  updateStaffAccount(
    id: string,
    patch: { role?: StaffRole; displayName?: string; passwordHash?: string; disabled?: boolean },
  ): Promise<void>;
  /// Sign every device of one account out. A password change or a lockout that
  /// leaves the old sessions alive has not actually done anything.
  deleteStaffSessionsFor(staffId: string): Promise<number>;
  /// Stamp a successful sign-in, so the roster can show who is still using this.
  touchStaffLogin(staffId: string): Promise<void>;
  /// Record a session. [tokenHash] is a sha256 — the token itself never lands
  /// in the database, so a leaked dump is not a set of live keys.
  createStaffSession(s: {
    tokenHash: string;
    staffId: string;
    expiresAt: Date;
    userAgent: string;
  }): Promise<void>;
  /// Resolve a session, or null when unknown or expired.
  /// displayName and phone come back too: the panel puts the signed-in person
  /// in its header, and until it could ask, it showed an invented name.
  staffBySessionToken(
    tokenHash: string,
  ): Promise<{ staffId: string; role: StaffRole; displayName: string; phone: string } | null>;
  deleteStaffSession(tokenHash: string): Promise<void>;
  /// Failed sign-ins for this phone inside the window — the rate limit.
  recentFailedLogins(phone: string, since: Date): Promise<number>;
  recordLoginAttempt(phone: string, succeeded: boolean): Promise<void>;

  /// adds. A flat key→value store; the public /shop/config only exposes a
  /// whitelist (contact/links), never secrets. get returns all; set upserts.
  getShopSettings(): Promise<Record<string, string>>;
  setShopSettings(patch: Record<string, string>): Promise<void>;

  /// Daily calendar audio (pregnancy + child development). One short clip per
  /// (track, day, locale), uploaded/edited from the admin panel and played by the
  /// app on the matching day. list* returns metadata only — never the bytes.
  listDailyAudio(track: AudioTrack): Promise<DailyAudioMeta[]>;
  /**
   * Product photos, uploaded rather than linked.
   *
   * The panel offered «Ссылка на фото» — paste a URL — which asks a person
   * selling watches to host an image somewhere first, and puts the storefront's
   * pictures on a server nobody here controls. `color` is `''` for the
   * product's own photo and a colour key for a variant's.
   */
  getProductPhoto(productId: string, color: string): Promise<{ mime: string; bytes: Buffer } | null>;
  /** Which photos exist, without the bytes — for the panel's thumbnails and
   *  for telling the storefront which products have one. */
  listProductPhotos(): Promise<Array<{ productId: string; color: string; uploadedAt: string }>>;
  putProductPhoto(p: { productId: string; color: string; mime: string; bytes: Buffer; staffId?: string | null }): Promise<void>;
  deleteProductPhoto(productId: string, color: string): Promise<void>;
  getDailyAudio(track: AudioTrack, day: number, locale: AudioLocale): Promise<{ mime: string; bytes: Buffer } | null>;
  upsertDailyAudio(a: DailyAudioInput): Promise<void>;
  deleteDailyAudio(track: AudioTrack, day: number, locale: AudioLocale): Promise<void>;
}

export type AudioTrack = 'pregnancy' | 'child';
export type AudioLocale = 'ru' | 'kk';
export interface DailyAudioMeta {
  track: AudioTrack;
  day: number;
  locale: AudioLocale;
  title: string | null;
  mime: string;
  size: number; // bytes
  updatedAt: string;
}
export interface DailyAudioInput {
  track: AudioTrack;
  day: number;
  locale: AudioLocale;
  title: string | null;
  mime: string;
  bytes: Buffer;
}

export interface ShopVariant { id: string; color: string; colorHex: string; stock: number }
export interface ShopProduct {
  id: string;
  name: string;
  priceMinor: number;
  variants: ShopVariant[];
  /**
   * 'bundle' means the row is a SET, not a thing on a shelf: it has no colours
   * of its own, and `parts` says which products a buyer must choose a colour of.
   * The storefront needs it to render the комплект at all — before this it was
   * returned with an empty `variants` array and looked like a product nobody
   * could pick, which is why the combo was unsellable.
   */
  kind: 'simple' | 'bundle';
  parts: Array<{ partId: string; qty: number }>;

  // ---- Catalogue (migration 033, frames 08 / 08a) ----
  //
  // The operator-owned half of a product. Until this was returned here, an
  // operator could set a Kazakh name, a stage and an age band in the panel and
  // the APP COULD NOT SEE ANY OF IT: /shop/products answered with five fields
  // and the storefront hard-coded the rest. Migration 033's own header names
  // this — «now it is data an operator owns» — and it was owned by nobody.
  //
  // Deliberately NOT here: cost_minor and anything margin-shaped. This route is
  // unauthenticated; what a thing cost us is not a customer's business.
  //
  // All nullable. A product from before the migration is UNCATEGORISED, and the
  // app must fall back to its own heuristic rather than show a customer «не
  // указан», which is panel vocabulary for "an operator still has work to do".
  nameKk: string | null;
  descriptionRu: string | null;
  descriptionKk: string | null;
  /** Which stage of motherhood this is FOR. Null → the app's own heuristic. */
  stage: ProductStage | null;
  category: string | null;
  /** Персонализация: the child age band this suits, in months. */
  ageMinMonths: number | null;
  ageMaxMonths: number | null;
  photoUrl: string | null;
  /**
   * Can it be bought right now.
   *
   * DERIVED, and derived HERE rather than by each caller: a simple product is
   * in stock when some colour of it is, and a bundle when every part can be
   * supplied — a bundle holds no stock of its own, so reading its (empty)
   * variants made the комплект, the only thing on the storefront that carries
   * the course, look permanently unavailable.
   */
  inStock: boolean;
}
/**
 * Fill in [ShopProduct.inStock] across a whole catalogue, and return it.
 *
 * One definition, called by both repositories, because the two readings of
 * "available" are not the same and getting the bundle wrong is expensive: a
 * simple product is available when SOME colour of it is on a shelf, a bundle
 * when EVERY part can be supplied. A bundle carries no stock of its own — the
 * комплект's `variants` is empty by design — so the obvious test (`some
 * variant has stock`) marks the 39 000 ₸ set, the only product that carries
 * the course, as permanently «нет в наличии».
 *
 * A bundle with no parts recorded is NOT in stock. It cannot be assembled from
 * nothing, and claiming otherwise sells something that cannot be shipped.
 */
export function markInStock(products: ShopProduct[]): ShopProduct[] {
  const byId = new Map(products.map((p) => [p.id, p]));
  for (const p of products) {
    p.inStock = p.kind === 'bundle'
      ? p.parts.length > 0 && p.parts.every((part) => {
        const src = byId.get(part.partId);
        return !!src && src.variants.some((v) => v.stock >= part.qty);
      })
      : p.variants.some((v) => v.stock > 0);
  }
  return products;
}

export interface ShopOrderInput {
  customerName: string; phone: string; city: string; address: string; note?: string;
  items: Array<{ variantId: string; qty: number }>;
  /**
   * Sold as this bundle, e.g. 'combo'.
   *
   * The items are still the PARTS — she picks a watch colour and a tracker
   * colour, and stock comes off both — but the order is priced at the bundle's
   * price and grants whatever the bundle grants. Two devices bought separately
   * are NOT the комплект: they cost 29 800 rather than 39 000 and unlock
   * nothing, which is the only reason the bundle is worth offering.
   */
  bundleId?: string;
}
/**
 * Every status an order can hold, in the order it normally moves through them.
 *
 * One list, exported, because it is now read in four places — the route's
 * validator, the list filter, the panel's chips and the CHECK constraint on
 * shop_order_events. Four copies of five strings is how a sixth status reaches
 * the database and nothing on screen can filter by it.
 */
export const SHOP_ORDER_STATUSES = ['new', 'confirmed', 'shipped', 'delivered', 'cancelled'] as const;
export type ShopOrderStatus = (typeof SHOP_ORDER_STATUSES)[number];
export interface ShopOrder {
  id: string; customerName: string; phone: string; city: string; address: string;
  note: string | null; totalMinor: number; discountMinor: number; status: ShopOrderStatus; createdAt: string;
  /**
   * [variantId] is which colour of which product the line took off the shelf.
   *
   * Optional because it was not on the wire before frame 05a and a panel served
   * by an older backend must not guess: a refund that restocks needs to name a
   * variant, and matching one back by product name and colour — which the
   * in-memory cancellation path used to do — picks the wrong row the day two
   * products share a colour name. Absent means «сервер не сказал», and the
   * refund form says so instead of sending something plausible.
   */
  items: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number; variantId?: string }>;
}

/**
 * Why a комплект came back — frame 05a, migration 051.
 *
 * Five reasons, and «other» carries the operator's own note. There is no sixth
 * meaning "we do not know": a refund is booked by a person who was holding the
 * box, so the reason is always available AT THE TIME. What is never available
 * afterwards is a reason for a refund taken before this list existed, and
 * nothing backfills those — see REFUND_REASONS_SINCE in admin/finance.ts.
 */
export const ORDER_REFUND_REASONS =
  ['defect', 'not_suitable', 'changed_mind', 'not_delivered', 'other'] as const;
export type OrderRefundReason = (typeof ORDER_REFUND_REASONS)[number];

/**
 * One refund booked against one order.
 *
 * WHAT IS NOT HERE: where the money went back to. shop_orders has never stored
 * how an order was paid for (see admin/finance.ts), so a Kaspi/наличные column
 * could only ever be filled in by guessing, on the one screen somebody
 * reconciles against a bank statement.
 */
export interface OrderRefund {
  id: number;
  orderId: string;
  /** Minor units, always > 0. */
  amountMinor: number;
  reason: OrderRefundReason;
  note: string | null;
  /** Kept even when the account is gone, like ShopOrderEvent.staffId. */
  staffId: string | null;
  /** Resolved from the roster where it can be; null for a removed account. */
  staffName: string | null;
  at: string;
  /** Units this refund put back on the shelf, from its own stock moves. */
  restockedUnits: number;
}

export type OrderRefundResult =
  | { ok: true; refund: OrderRefund }
  | {
    ok: false;
    /**
     * 'refund_exceeds_order' — the refunds booked so far plus this one come to
     * more than the order was worth. Refused rather than clamped: the operator
     * has either the wrong order or the wrong number, and both need a person.
     * 'restock_exceeds_order' — more units back than went out on that line.
     * 'unknown_line' — a variant that is not on this order at all.
     */
    error: 'not_found' | 'refund_exceeds_order' | 'restock_exceeds_order' | 'unknown_line';
    /** For the two line errors, which variant. */
    variantId?: string;
  };
/**
 * One recorded move of an order's status — frame 03's timeline (migration 039).
 *
 * [staffName] is resolved from the roster where it can be. It stays null for a
 * transition made by an account since removed, and for one nobody made at all;
 * the id is kept in either case, because it is what the row is keyed on.
 */
export interface ShopOrderEvent {
  id: number;
  orderId: string;
  fromStatus: ShopOrderStatus | null;
  toStatus: ShopOrderStatus;
  staffId: string | null;
  staffName: string | null;
  at: string;
}

/**
 * A page of orders, with the two numbers frame 02 prints beside it.
 *
 * `total` counts what matches the filter; `counts` counts every status over the
 * whole table so the chips do not change under the pointer.
 */
export interface ShopOrderPage {
  orders: ShopOrder[];
  total: number;
  counts: Record<ShopOrderStatus, number>;
}

export type ShopOrderResult =
  | { ok: true; id: string; totalMinor: number; discountMinor: number }
  // 'incomplete_bundle': the order claimed to be a bundle but its lines do not
  // contain the bundle's parts. Refused rather than silently priced as a
  // bundle, which would sell a 39 000 ₸ комплект — and the course with it — for
  // whatever one tracker costs.
  | { ok: false; error: 'empty' | 'not_found' | 'out_of_stock' | 'incomplete_bundle'; variantId?: string };

/// A callback request from the landing page: a name and a number, nothing more.
/// Not an order — no address, no variant, no stock reserved. See migration 017.
/**
 * Why a stock level changed.
 *
 * A bare number told you the count and nothing else, so a delivery, a sale, a
 * breakage and a miscount were indistinguishable — which makes the one question
 * stock control exists for ("we counted forty and it says thirty-seven")
 * unanswerable.
 */
/** One lesson of the Ма!Ма! course. */
export interface CourseLesson {
  id: string;
  course: string;
  titleRu: string;
  /** Optional: lessons go up in Russian first, and the app falls back to it. */
  titleKk: string | null;
  youtubeUrl: string;
  summaryRu: string | null;
  summaryKk: string | null;
  sort: number;
  published: boolean;
  createdAt: string;
}

/**
 * One unit we bought, and what became of it.
 *
 * `stock` — received, unsold. `sold` — paired to [activatedByPhone].
 * `blocked` — stolen, returned or replaced under warranty; never pairs again.
 */
export interface DeviceRegistryRow {
  serial: string;
  status: 'stock' | 'sold' | 'blocked';
  kind: 'band' | 'tag' | null;
  activationCode: string | null;
  orderId: string | null;
  receivedAt: string;
  activatedByPhone: string | null;
  activatedAt: string | null;
  note: string | null;
}

/** One lesson's worth of "where she got to". */
export interface CourseProgress {
  lessonId: string;
  positionSeconds: number;
  /** YouTube's, as the player measured it; unknown until a player has loaded. */
  durationSeconds: number | null;
  completed: boolean;
  updatedAt: string;
}

export type StockMoveReason = 'receipt' | 'sale' | 'return' | 'writeoff' | 'correction';

/** Who moved it. Absent for automatic moves, e.g. an order taking stock. */
export interface StockMoveAuthor {
  staffId?: string;
  note?: string;
}

export interface StockMove {
  id: number;
  variantId: string;
  productName: string;
  color: string;
  /** Signed: +50 received, −1 sold. Sums to the stock level with no case analysis. */
  delta: number;
  reason: StockMoveReason;
  note: string | null;
  staffId: string | null;
  orderId: string | null;
  /**
   * Which refund this move belongs to (migration 051), or null.
   *
   * The discriminator frame 05 was missing. A cancellation and a refund both
   * write reason='return' with an order_id, and «Возвратов, шт» / «Доля
   * возвратов, %» added them together — counting orders that never entered
   * revenue as returns against units sold. Null on every row written before
   * 051, which is honest: those are all cancellations.
   */
  refundId?: number | null;
  at: string;
}

// ---- Поставки (migration 045) ---------------------------------------------

export interface Supplier {
  id: string;
  name: string;
  /** Phone, WhatsApp, a manager's name — one line, because separate columns per
   *  channel produce a table where half the rows fill in the wrong one. */
  contact: string | null;
  /**
   * The lead time the supplier DECLARED, in days. Null when they never said.
   *
   * Not measured: nothing in this database has a placed→received pair yet, and
   * a figure invented from that emptiness is one a buyer plans money against.
   */
  leadTimeDays: number | null;
  active: boolean;
  createdAt: string;
}

export type PurchaseOrderStatus = 'draft' | 'placed' | 'received' | 'cancelled';

export interface PurchaseOrderItem {
  variantId: string;
  productId: string;
  productName: string;
  color: string;
  qtyOrdered: number;
  /** What arrived. 0 until a receipt closes the line. */
  qtyReceived: number;
  /** Null until somebody typed a purchase price. The panel prints «—» rather
   *  than a computed guess: this product only learns a unit cost from a receipt
   *  carrying `batchCostMinor`. */
  unitCostMinor: number | null;
  /** When the line was closed by a receipt, or null while it is in transit. */
  receivedAt: string | null;
}

export interface PurchaseOrder {
  id: string;
  supplierId: string | null;
  /** Denormalised for the list, which otherwise reads the supplier table per row. */
  supplierName: string | null;
  /** The supplier's DECLARED term. Null falls back to the warehouse constant. */
  supplierLeadTimeDays: number | null;
  status: PurchaseOrderStatus;
  placedAt: string | null;
  expectedAt: string | null;
  note: string | null;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
  items: PurchaseOrderItem[];
}

export interface InventoryProduct {
  id: string;
  name: string;
  sku: string | null;
  priceMinor: number;
  costMinor: number | null;
  kind: 'simple' | 'bundle';
  active: boolean;
  sort: number;
  lowStockThreshold: number;
  /**
   * Units on hand. For a bundle this is DERIVED — how many complete sets its
   * parts can make — because a bundle with its own count drifts from the parts
   * it is assembled from within a week.
   */
  stock: number;
  /** Below the threshold, and worth saying so before a customer finds out. */
  lowStock: boolean;
  variants: Array<{ id: string; color: string; colorHex: string; stock: number }>;

  // ---- Catalogue (migration 033, frames 08 / 08a) ----
  //
  // Added here rather than on a second "catalogue product" type: a screen that
  // shows the stage next to the stock needs both, and two reads of the same
  // table drift apart the first time one of them gains a filter.
  //
  // All nullable. A product from before the migration is UNCATEGORISED, not
  // mis-categorised, and the panel shows that as «не указан».
  nameKk: string | null;
  /**
   * Which stage of motherhood the product is FOR. Until this column existed,
   * shop_stage.dart derived the shop's «Для вашего этапа» from her pregnancy
   * flag and her children's ages, because — in its own words — inventing a
   * stage field would have been fabrication. Now it is data an operator owns.
   */
  stage: ProductStage | null;
  category: string | null;
  descriptionRu: string | null;
  descriptionKk: string | null;
  /** Персонализация: the child age band this suits, in months. */
  ageMinMonths: number | null;
  ageMaxMonths: number | null;
  photoUrl: string | null;
  seoSlug: string | null;
  seoTitle: string | null;
  seoDescription: string | null;
}

export type ShopLeadLocale = 'ru' | 'kz';
export type ShopLeadStatus = 'new' | 'called' | 'ordered' | 'dropped';
export interface ShopLeadInput {
  customerName: string; phone: string; package?: string; locale?: ShopLeadLocale;
}
export interface ShopLead {
  id: string; customerName: string; phone: string; package: string;
  locale: ShopLeadLocale; status: ShopLeadStatus; createdAt: string;
}

/// The family bundle: a watch and a tracker bought together take this much off,
/// per matched pair (2 buys of each = 2× off). Recomputed server-side from the
/// order's own contents at placement — the client never sends a price — so the
/// saving advertised on the storefront is exactly the saving that is charged.
///
/// **Currently 0.** The landing page — the only place prices are advertised —
/// no longer sells a discounted hardware pair. Its «Комплект «Мама и ребёнок»»
/// is 39 000 ₸ for both devices PLUS the Ма!Ма! course (a 40 000 ₸ gift), which
/// is not a product in this schema and cannot be expressed as a discount on the
/// two devices. A non-zero value here would make the shop API undercut the
/// landing's own à-la-carte prices for the same two items.
///
/// The mechanism is kept rather than deleted: re-enabling a hardware bundle is a
/// one-line change plus the storefront copy to advertise it.
export const BUNDLE_DISCOUNT_MINOR = 0;
export function bundleDiscountMinor(lines: Array<{ productId: string; qty: number }>): number {
  const qtyOf = (id: string) => lines.filter((l) => l.productId === id).reduce((n, l) => n + l.qty, 0);
  return Math.min(qtyOf('watch'), qtyOf('tracker')) * BUNDLE_DISCOUNT_MINOR;
}
