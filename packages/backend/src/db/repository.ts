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

export type { BiMetrics };

export interface SleepNight {
  night: string; // ISO date (wake day)
  deepMin: number;
  remMin: number;
  lightMin: number;
  awakeMin: number;
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
}

export interface SafetyAlertRow {
  childId: string;
  kind: 'entered' | 'left';
  zoneName: string;
  at: string; // ISO timestamp
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
  contentItems: number;
  contentLinked: number;
}

export interface Repository {
  // Health
  insertHealthMetric(m: BandTelemetry & { userId: string; triageSeverity: TriageSeverity }): Promise<void>;
  insertBpCalibration(userId: string, cal: BpCalibration & { cuffSystolic: number; cuffDiastolic: number; ppgSystolic: number; ppgDiastolic: number }): Promise<void>;

  // Child / geofence
  loadGeofences(childId: string): Promise<Geofence[]>;
  insertGeofenceEvent(evt: GeofenceEvent): Promise<void>;
  insertLocation(fix: ChildLocationFix): Promise<void>;

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
  geofenceOwner(geofenceId: string): Promise<{ userId: string } | null>;

  // ---- CRUD + history (client API) ----
  listChildren(userId: string): Promise<Array<{ id: string; name: string }>>;
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

  // Newborn care events (feed/diaper/sleep), push-only upsert on (child, at, kind).
  // listNewbornEvents joins the caller's children for the admin drawer.
  recordNewbornEvent(childId: string, e: NewbornEventRow): Promise<void>;
  listNewbornEvents(userId: string, limit: number): Promise<Array<{ childId: string; childName: string } & NewbornEventRow>>;

  queryMetrics(userId: string, opts: { from: string; to: string; metric: string }): Promise<Array<{ t: string; value: number }>>;
  listGeofenceEvents(childId: string, limit: number): Promise<GeofenceEvent[]>;

  // ---- Sleep (nightly summaries) ----
  recordSleep(userId: string, s: SleepNight): Promise<void>;
  listSleep(userId: string, limit: number): Promise<SleepNight[]>;

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
  adminListUsers(q: string, limit: number, offset: number): Promise<{ total: number; users: Array<{ id: string; displayName: string; phone: string | null; dueDate: string | null }> }>;
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

  // ---- Timeline content (the CMS) ----
  /// The whole catalogue, keyed by stage (`w1`..`w40`, `m0`..`m60`).
  contentCatalog(): Promise<Record<string, ContentItemRow[]>>;
  /// Replace one stage's items outright. Editing is per stage, so a save can
  /// never partially apply across stages.
  putStageContent(stageKey: string, items: ContentItemRow[]): Promise<void>;

  writeAudit(entry: { staffId: string; action: string; target?: string }): Promise<void>;
  listAudit(limit: number): Promise<Array<{ staffId: string; action: string; target: string | null; at: string }>>;
}
