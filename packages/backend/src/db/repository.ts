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

export type { BiMetrics };

export interface CryRow {
  at: string; // ISO timestamp of the analysis
  reason: string; // wire code, e.g. 'hungry'
  confidence: number; // 0..1
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

export interface ProfileRow {
  displayName: string;
  phone: string | null; // E.164
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
  doctorPhone: string | null; // her own emergency contact
  avgCycleLength: number | null; // women's-health baselines (null = app defaults)
  avgPeriodLength: number | null;
}

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
  /// Medical guidance, so it may not be published without a clinician's
  /// sign-off. See content/medicalReview.ts.
  medical?: boolean;
  /// Work in progress; never served to the app.
  draft?: boolean;
  /// Who checked it, when, and what they read. Back-office only — stripped
  /// before the catalogue reaches a phone, because it names a member of staff.
  review?: { by: string; at: string; fingerprint: string };
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
  id: string;
  name: string;
  kind: string;
  userId: string;
  displayName: string;
  childName: string | null;
  batteryPct: number | null;
  lastSeen: string | null;
}

export interface AdminSafetyEvent {
  userId: string;
  displayName: string;
  childName: string;
  kind: string; // entered | left | sos | checkIn | lowBattery
  zoneName: string;
  at: string;
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
   */
  insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }): Promise<boolean>;
  /**
   * The caller's own HAND-ENTERED readings (device_id NULL): typed cuff/glucose
   * values. For restoring a typed vitals history on a new device — band readings
   * are re-supplied by the device, so they are deliberately excluded.
   */
  listManualVitals(userId: string): Promise<Array<{
    recordedAt: string; heartRateBpm: number | null; spo2Pct: number | null;
    systolicMmHg: number | null; diastolicMmHg: number | null; coreTempC: number | null; glucoseMmol: number | null;
  }>>;
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
  listGeofenceEvents(childId: string, limit: number): Promise<GeofenceEvent[]>;

  // ---- Sleep (nightly summaries) ----
  recordSleep(userId: string, s: SleepNight): Promise<void>;
  listSleep(userId: string, limit: number): Promise<SleepNight[]>;

  // Baby cry-analysis results (parent-recorded, newest-first). Pushed so they
  // survive a reinstall and restore on a new device — history was device-local.
  recordCry(userId: string, c: CryRow): Promise<void>;
  listCry(userId: string, limit: number): Promise<CryRow[]>;

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

  // ---- Child safety alerts (zone enter/exit history) ----
  recordAlert(userId: string, a: SafetyAlertRow): Promise<void>;
  listAlerts(userId: string, limit: number): Promise<SafetyAlertRow[]>;
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
  upsertProfile(userId: string, p: ProfileRow): Promise<void>;

  // ---- Device → child reassignment (tracker tag ownership) ----
  reassignDevice(deviceId: string, childId: string | null): Promise<void>;

  // ---- Admin / back-office ----
  adminStats(): Promise<{ activeUsers: number; devicesOnline: number; alertsToday: number; ingestLastHour: number }>;
  /** Aggregate child demographics (count, gender split, age buckets) as of [asOf] (ISO). */
  childrenStats(asOf: string): Promise<ChildrenStats>;
  recentEmergencies(limit: number): Promise<Array<{ id: string; userId: string; displayName: string; code: string; severity: string; at: string; acknowledgedAt: string | null; acknowledgedBy: string | null }>>;
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
  /// staffName/targetName are resolved from the roster where they can be. Null
  /// means the account is gone or predates accounts existing — the row still
  /// comes back, because a log that hides what it cannot label is worse than
  /// one that shows an id.
  listAudit(limit: number): Promise<Array<{
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
  }>>;

  // ---- Shop (device store) ----
  /// Active products with every colour variant (in- and out-of-stock), for the
  /// public storefront. Out-of-stock variants are returned too so the page can
  /// show them disabled rather than hiding a colour that will restock.
  shopProducts(): Promise<ShopProduct[]>;
  /// Place a COD order. Atomic: each variant row is locked, stock checked and
  /// decremented, then the order + item snapshots are written — all or nothing,
  /// so two buyers cannot oversell the last unit. Returns the order id + total,
  /// or a typed failure (empty cart / unknown variant / insufficient stock).
  placeShopOrder(o: ShopOrderInput): Promise<ShopOrderResult>;
  adminShopVariants(): Promise<Array<ShopVariant & { productId: string; productName: string }>>;
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
  /// The ledger, newest first, optionally for one variant.
  stockMoves(limit: number, variantId?: string): Promise<StockMove[]>;
  adminShopOrders(limit: number): Promise<ShopOrder[]>;
  setShopOrderStatus(orderId: string, status: ShopOrderStatus): Promise<void>;
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
export type ShopOrderStatus = 'new' | 'confirmed' | 'shipped' | 'delivered' | 'cancelled';
export interface ShopOrder {
  id: string; customerName: string; phone: string; city: string; address: string;
  note: string | null; totalMinor: number; discountMinor: number; status: ShopOrderStatus; createdAt: string;
  items: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number }>;
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
  at: string;
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
