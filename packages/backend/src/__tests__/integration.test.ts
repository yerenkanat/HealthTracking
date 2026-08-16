/**
 * IN-PROCESS integration test — boots the REAL Fastify server (buildServer) and
 * drives it with fastify.inject(). Exercises the actual routing, zod validation,
 * and handlers (ingestHandler, geofence geometry, guardrail, bp calibration) with
 * in-memory fakes for the DB/Redis/push/LLM. Runs with `npx vitest run` — no
 * Docker/Postgres/Redis required. (The docker-compose smoke additionally exercises
 * the literal pg/Timescale/PostGIS + ioredis drivers.)
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { InjectPayload, Response as InjectResponse } from 'light-my-request';
import { buildServer } from '../server';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { emergencyReason } from '../emergency/reason.js';
import type { Repository, SleepNight, WearableDayRow, CryRow, CryThresholdRow, DayLogRow, EpdsRow, SafetyAlertRow, ProfileRow, NotificationPrefs, PushDeliveryRecord } from '../db/repository';
import type { Geofence, GeofenceEvent, ChildLocationFix } from '@fcs/shared';

/**
 * Opening one person's health record now needs a stated reason — it goes into
 * the audit log beside the name of whoever looked. Appended to every
 * per-person read below; the rule itself is covered in auditReason.test.ts.
 */
const WHY = '?reason=' + encodeURIComponent('Обращение клиента');

const USER = '11111111-1111-1111-1111-111111111111';
const CHILD = '33333333-3333-3333-3333-333333333333';
const DEVICE = '22222222-2222-2222-2222-222222222222';

const HOME: Geofence = {
  id: '44444444-4444-4444-4444-444444444444',
  name: 'Home',
  shape: 'circle',
  center: { lat: 43.238949, lng: 76.889709 },
  radiusM: 100,
};

type StaffRole = 'admin' | 'clinician' | 'support';
function makeDeps(
  authUser: () => Promise<{ userId: string } | null> = async () => ({ userId: USER }),
  authAdmin: () => Promise<{ staffId: string; role: StaffRole } | null> = async () => ({ staffId: 's1', role: 'admin' }),
  chatLimiter?: import('../http/rateLimit').RateLimiter,
  ingestLimiter?: import('../http/rateLimit').RateLimiter,
) {
  const events: GeofenceEvent[] = [];
  const pushes = { emergency: 0, geofence: 0 };
  const healthRows: unknown[] = [];
  const calRows: unknown[] = [];
  let lastLocation: ChildLocationFix | null = null;
  /** Every fix ever inserted, for locationHistory. */
  const locationTrail: ChildLocationFix[] = [];
  /** The durable copy, behind repo.lastLocation — distinct from the cache above. */
  let storedLocation: ChildLocationFix | null = null;
  const fenceState = new Map<string, 'in' | 'out'>(); // real Redis-like dedup

  // In-memory CRUD state
  const children: Array<{ id: string; name: string; gender?: 'boy' | 'girl' | null; dateOfBirth?: string | null }> = [];
  const appointments: Array<{ id: string; title: string; at: string; note: string; userId: string }> = [];
  const medRows: Array<{ id: string; name: string; dose: string; perDay: number; userId: string }> = [];
  const medicalIds = new Map<string, Record<string, string>>();
  const newbornRows = new Map<string, Array<{ at: string; kind: string; detail: string | null; durationMin: number | null }>>();
  const growthRows = new Map<string, Array<{ at: string; weightKg: number | null; heightCm: number | null }>>();
  const doseRows: Array<{ medId: string; date: string; count: number; userId: string }> = [];
  const vaccineRows = new Map<string, Set<string>>(); // childId → keys
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null }> = [];
  /// What the ingest path has stamped on each device — the fleet view's
  /// «последний сигнал», battery and firmware. Nothing wrote these before.
  const liveness = new Map<string, { at: string; batteryPct: number | null; firmware: string | null }>();
  const defects = new Map<string, { at: string; by: string; note: string | null }>();
  const geofences = new Map<string, import('@fcs/shared').Geofence[]>();
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
  const sleepRows: SleepNight[] = [];
  const wearableRows: WearableDayRow[] = [];
  const cryRows: CryRow[] = [];
  /** `cry_settings` — absent until the back office sets a threshold (17c). */
  let cryThresholdRow: CryThresholdRow | null = null;
  const weightRows: Array<{ date: string; kg: number }> = [];
  const kickRows: Array<{ endedAt: string; count: number; durationSec: number }> = [];
  const contractionRows: Array<{ endedAt: string; count: number; avgDurationSec: number; avgIntervalSec: number }> = [];
  const dayLogs = new Map<string, DayLogRow>();
  /** `epds_results` — keyed by the client-supplied id, as the real table is. */
  const epdsRows = new Map<string, EpdsRow>();
  const alertRows: SafetyAlertRow[] = [];
  const contentRows = new Map<string, import('../db/repository').ContentItemRow[]>();
  const pregWeeks = new Map<number, import('../db/repository').PregnancyWeekOverride>();
  let profile: ProfileRow | null = null;
  /** notification_prefs — null until PUT /notifications/settings writes one. */
  let notifyPrefs: NotificationPrefs | null = null;
  /** push_deliveries — every attempt this server recorded, held ones included. */
  const pushLedger: PushDeliveryRecord[] = [];
  /// Her timezone, not the box's. Deliberately not UTC: a fake that agrees with
  /// the server clock cannot fail the way production does.
  const NOTIFY_TZ = 'Asia/Almaty';
  /// What PUT /notifications/settings last stored in `users.timezone`.
  let notifyTz = NOTIFY_TZ;
  let idSeq = 1;

  /**
   * Her latest readings and her triage history — ONE definition.
   *
   * `adminUserDetail` builds these by calling `adminUserHealth` in both real
   * repositories, so a fake in which the two disagree can make a screen pass
   * against numbers no repository would ever hand it.
   */
  const HEALTH = {
    latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 },
    triage: [{ code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00Z' }],
  };

  const repo: Repository = {
    insertHealthMetric: async (m) => { healthRows.push(m); return false; },
    listManualVitals: async () => [],
    shopProducts: async () => [],
    listDailyAudio: async () => [],
    getProductPhoto: async () => null,
    listProductPhotos: async () => [],
    putProductPhoto: async () => {},
    deleteProductPhoto: async () => {},
    getDailyAudio: async () => null,
    upsertDailyAudio: async () => {},
    deleteDailyAudio: async () => {},
    placeShopOrder: async () => ({ ok: false, error: 'empty' }),
    adminShopVariants: async () => [],
    setShopVariantStock: async () => {},
    addShopVariant: async () => {},
    // Поставки (migration 045). This fake exists for the app-facing routes; the
    // supply chain is exercised against the real memory repository in
    // inventoryRoutes.test.ts, where an unfaithful fake would be the defect.
    listSuppliers: async () => [],
    upsertSupplier: async () => ({ ok: true, id: 'sup-1' }),
    listPurchaseOrders: async () => [],
    purchaseOrderById: async () => null,
    createPurchaseOrder: async () => ({ ok: false, error: 'no_items' }),
    setPurchaseOrderStatus: async () => false,
    receivePurchaseOrderLine: async () => ({ ok: false, status: null, qtyOrdered: null }),
    inTransitByVariant: async () => ({}),
    adminShopOrders: async () => [],
    adminShopOrderPage: async () => ({
      orders: [], total: 0,
      counts: { new: 0, confirmed: 0, shipped: 0, delivered: 0, cancelled: 0 },
    }),
    shopOrderById: async () => null,
    shopOrderEvents: async () => [],
    setShopOrderStatus: async () => {},
    recordShopLead: async () => ({ id: 'lead-1' }),
    adminShopLeads: async () => [],
    shopLeadCounts: async () => ({ total: 0, uncalled: 0 }),
    setShopLeadStatus: async () => {},
    getShopSettings: async () => ({}),
    setShopSettings: async () => {},
    insertBpCalibration: async (_u, c) => void calRows.push(c),
    latestBpCalibration: async () =>
      (calRows.length ? calRows[calRows.length - 1] : null) as never,
    loadGeofences: async (childId) =>
      childId === CHILD ? [HOME, ...(geofences.get(childId) ?? [])] : (geofences.get(childId) ?? []),
    insertGeofenceEvent: async (e) => void events.push(e),
    // Staff sign-in is exercised by staffLogin.test.ts against the memory
    // repository; this integration stub only has to satisfy the interface.
    courseLessons: async () => [],
    upsertCourseLesson: async () => ({ id: 'lesson-1' }),
    deleteCourseLesson: async () => {},
    courseProgress: async () => [],
    saveCourseProgress: async () => {},
    courseProgressSummary: async () => [],
    hasEntitlement: async () => false,
    grantEntitlement: async () => {},
    revokeEntitlement: async () => {},
    listEntitlements: async () => [],
    adminProducts: async () => [],
    // Support (frame 12). This fake serves the flows below, none of which touch
    // the support queue; its behaviour is covered against the real memory
    // repository in supportRoutes.test.ts, where a write can be read back.
    listSupportTickets: async () => [],
    listSupportTicketsForUser: async () => [],
    getSupportTicket: async () => null,
    createSupportTicket: async () => 'sup-1',
    updateSupportTicket: async () => true,
    listSupportReplies: async () => [],
    addSupportReply: async () => {},
    markSupportTicketRead: async () => true,
    listSupportTemplates: async () => [],
    // Catalogue (frames 08/08a/08b). This fake serves the flows below, none of
    // which edit the catalogue; catalogue behaviour is covered against the real
    // memory repository in productCatalog.test.ts, where a write can be read
    // back.
    updateProduct: async () => {},
    listShopCategories: async () => [],
    upsertShopCategory: async () => {},
    deleteShopCategory: async () => true,
    upsertProduct: async () => {},
    bundleParts: async () => [],
    setBundleParts: async () => {},
    moveStock: async () => ({ ok: false as const, error: 'unknown_variant' as const }),
    stockMoves: async () => [],
    soldUnitsSince: async () => ({}),
    courseLessonWatchers: async () => 0,
    pruneLocationHistory: async () => 0,
    userByPhone: async () => null,
    createUserWithPhone: async (a: { phone: string; displayName: string }) =>
      ({ id: 'user-1', displayName: a.displayName }),
    createUserSession: async () => {},
    userBySessionToken: async () => null,
    deleteUserSession: async () => {},
    recentPhoneClaims: async () => 0,
    recordPhoneClaim: async () => {},
    deviceRegistryEntry: async () => null,
    addDeviceSerials: async () => ({ added: 0, skipped: 0 }),
    markDeviceActivated: async () => true,
    assignDevicesToOrder: async () => ({ linked: [], unknown: [] }),
    devicesForOrder: async () => [],
    setDeviceRegistryStatus: async () => {},
    listDeviceRegistry: async () => [],
    deviceByActivationCode: async () => null,
    putPhoneCode: async () => {},
    usePhoneCode: async () => 'ok' as const,
    staffByPhone: async () => null,
    staffById: async () => null,
    upsertStaffAccount: async () => {},
    createStaffAccount: async () => null,
    listStaffAccounts: async () => [],
    updateStaffAccount: async () => {},
    deleteStaffSessionsFor: async () => 0,
    touchStaffLogin: async () => {},
    createStaffSession: async () => {},
    staffBySessionToken: async () => null,
    deleteStaffSession: async () => {},
    recentFailedLogins: async () => 0,
    recordLoginAttempt: async () => {},
    // No family sharing in this fixture: it drives the single-account flow, and
    // an empty grant table is the honest state for it. Every method answers
    // "nobody has been let in" rather than throwing.
    // This fixture drives the single-account flow and places no orders.
    shopOrdersByPhone: async () => [],
    familyMembers: async () => [],
    familyMemberships: async () => [],
    familyLevel: async () => null,
    upsertFamilyAccess: async () => {},
    removeFamilyAccess: async () => false,
    createFamilyInvite: async () => {},
    familyInviteByHash: async () => null,
    familyInvites: async () => [],
    claimFamilyInvite: async () => false,
    revokeFamilyInvite: async () => false,
    insertLocation: async (fix) => {
      storedLocation = fix;
      locationTrail.push(fix);
    },
    lastLocation: async () => storedLocation,
    // A real trail, filtered the way Postgres filters it. A fake returning []
    // would let «История дня» pass its wiring test against a repository that
    // can never feed it.
    locationHistory: async (childId, fromIso, toIso, limit) =>
      locationTrail
        .filter((f) => f.childId === childId && f.observedAt >= fromIso && f.observedAt < toIso)
        .sort((a, b) => a.observedAt.localeCompare(b.observedAt))
        .slice(0, limit),
    guardianPushTokens: async () => ({ tokens: ['t'], childName: 'Sultan', locale: 'ru-KZ' }),
    guardianPushTokensForUser: async () => ({ tokens: ['t'], locale: 'ru-KZ' }),
    deletePushToken: async () => {},
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Doctor', tel: '+7700' }],
    deviceOwner: async (id) =>
      id === DEVICE || devices.some((d) => d.id === id) ? { userId: USER } : null,
    // Child- and zone-scoped routes now verify the caller owns the id in the
    // URL, so the fake has to answer ownership questions too.
    childOwner: async (id) =>
      id === CHILD || children.some((c) => c.id === id) ? { userId: USER } : null,
    geofenceOwner: async (id) =>
      [...geofences.values()].flat().some((g) => g.id === id) ? { userId: USER } : null,
    // CRUD
    listChildren: async () => children.map((c) => ({ id: c.id, name: c.name, gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null })),
    upsertChild: async (_u, c) => {
      const row = { id: c.id, name: c.name, gender: c.gender ?? null, dateOfBirth: c.dateOfBirth ?? null };
      const i = children.findIndex((x) => x.id === c.id);
      if (i >= 0) children[i] = row; else children.push(row);
    },
    deleteChild: async (id) => {
      const i = children.findIndex((c) => c.id === id);
      if (i >= 0) children.splice(i, 1);
    },
    listAppointments: async (uid) =>
      appointments.filter((a) => a.userId === uid).map(({ userId: _drop, ...a }) => a),
    upsertAppointment: async (uid, a) => {
      const i = appointments.findIndex((x) => x.id === a.id);
      const row = { ...a, note: a.note ?? '', userId: uid };
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
    listMedications: async (uid) => medRows.filter((m) => m.userId === uid).map(({ userId: _d, ...m }) => m),
    upsertMedication: async (uid, m) => {
      const i = medRows.findIndex((x) => x.id === m.id);
      const row = { ...m, userId: uid };
      if (i >= 0) medRows[i] = row; else medRows.push(row);
    },
    medicationOwner: async (id) => {
      const m = medRows.find((x) => x.id === id);
      return m ? { userId: m.userId } : null;
    },
    deleteMedication: async (id) => {
      const i = medRows.findIndex((m) => m.id === id);
      if (i >= 0) medRows.splice(i, 1);
    },
    listDevices: async () => devices.map((d) => ({ ...d })),
    createDevice: async (_u, d) => void devices.push({ ...d, childId: d.childId ?? null }),
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
    },
    // Frame 11's liveness stamp. Recorded even for DEVICE, which this fake
    // answers ownership for without holding a row — otherwise an assertion
    // about "the fleet knows this device is alive" could not be written for
    // the device every other test in this file uses.
    touchDevice: async (deviceId, seen) => {
      const was = liveness.get(deviceId);
      liveness.set(deviceId, {
        at: !was || seen.at > was.at ? seen.at : was.at,
        batteryPct: seen.batteryPct ?? was?.batteryPct ?? null,
        firmware: seen.firmware ?? was?.firmware ?? null,
      });
    },
    markDeviceDefect: async (deviceId, mark) => {
      if (deviceId !== DEVICE && !devices.some((d) => d.id === deviceId)) return false;
      if (mark) defects.set(deviceId, mark); else defects.delete(deviceId);
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
      const list = newbornRows.get(childId) ?? [];
      const i = list.findIndex((x) => x.at === e.at && x.kind === e.kind);
      if (i >= 0) list[i] = e; else list.push(e);
      newbornRows.set(childId, list);
    },
    listNewbornEvents: async (userId, limit) => {
      if (userId !== USER) return [];
      const out: Array<Record<string, unknown>> = [];
      for (const [childId, list] of newbornRows) {
        const c = children.find((x) => x.id === childId);
        for (const e of list) out.push({ childId, childName: c?.name ?? 'Sultan', ...e });
      }
      out.sort((a, b) => String(b.at).localeCompare(String(a.at)));
      return out.slice(0, limit) as never;
    },
    upsertGrowth: async (childId, g) => {
      const list = growthRows.get(childId) ?? [];
      const i = list.findIndex((x) => x.at === g.at);
      if (i >= 0) list[i] = g; else list.push(g);
      growthRows.set(childId, list);
    },
    listGrowth: async (userId) => {
      if (userId !== USER) return [];
      const out: Array<Record<string, unknown>> = [];
      for (const [childId, list] of growthRows) {
        const c = children.find((x) => x.id === childId);
        for (const g of list) out.push({ childId, childName: c?.name ?? 'Sultan', ...g });
      }
      return out.sort((a, b) => String(a.at).localeCompare(String(b.at))) as never;
    },
    upsertDose: async (userId, d) => {
      const i = doseRows.findIndex((x) => x.medId === d.medId && x.date === d.date);
      if (i >= 0) doseRows[i] = { ...d, userId }; else doseRows.push({ ...d, userId });
    },
    listDoses: async (userId) =>
      doseRows.filter((d) => d.userId === userId).map(({ userId: _o, ...d }) => d)
        .sort((a, b) => b.date.localeCompare(a.date)) as never,
    setVaccine: async (childId, key, done) => {
      const set = vaccineRows.get(childId) ?? new Set<string>();
      if (done) set.add(key); else set.delete(key);
      vaccineRows.set(childId, set);
    },
    listVaccines: async (userId) => {
      if (userId !== USER) return [];
      const out: Array<Record<string, unknown>> = [];
      for (const [childId, keys] of vaccineRows) {
        const c = children.find((x) => x.id === childId);
        for (const key of keys) out.push({ childId, childName: c?.name ?? 'Sultan', vaccineKey: key });
      }
      return out as never;
    },
    upsertChildEmergency: async (childId, m) => void medicalIds.set(childId, { ...m } as Record<string, string>),
    listMedicalIds: async (userId) => {
      const out: Array<Record<string, unknown>> = [];
      if (userId !== USER) return out as never;
      for (const [childId, m] of medicalIds) {
        const c = children.find((x) => x.id === childId);
        out.push({ childId, childName: c?.name ?? 'Sultan', ...m });
      }
      return out as never;
    },
    getChildEmergency: async (childId) => (medicalIds.get(childId) ?? null) as never,
    queryMetrics: async () => [{ t: '2026-07-15T08:00:00Z', value: 72 }, { t: '2026-07-15T08:05:00Z', value: 80 }],
    listGeofenceEvents: async () => events.filter((e) => e.transition),
    // Sleep
    recordSleep: async (_u, s) => {
      const i = sleepRows.findIndex((x) => x.night === s.night);
      if (i >= 0) sleepRows[i] = s; else sleepRows.push(s);
    },
    listSleep: async (_u, limit) => [...sleepRows].sort((a, b) => b.night.localeCompare(a.night)).slice(0, limit),
    // The watch's activity/wellbeing day. Upsert on (device, day) — the same
    // key the real ON CONFLICT uses, so this fake cannot pass a batch that a
    // real database would turn into duplicate rows.
    upsertWearableDay: async (row) => {
      const { userId: _u, ...day } = row;
      const i = wearableRows.findIndex((x) => x.deviceId === day.deviceId && x.day === day.day);
      if (i >= 0) wearableRows[i] = day; else wearableRows.push(day);
    },
    listWearableDays: async (_u, limit) =>
      [...wearableRows].sort((a, b) => b.day.localeCompare(a.day)).slice(0, limit),
    recordCry: async (_u, c) => {
      const i = cryRows.findIndex((x) => x.at === c.at);
      // The verdict survives a re-push of the analysis, exactly as the ON
      // CONFLICT clause in pgRepository leaves it alone: the app re-sends its
      // whole history on sign-in, and a fake that dropped it here would hide a
      // route that erases the only ground truth this product has.
      const kept = i >= 0 ? { verdict: cryRows[i].verdict ?? null, actualReason: cryRows[i].actualReason ?? null } : {};
      const row = { verdict: null, actualReason: null, ...kept, ...c };
      if (i >= 0) cryRows[i] = row; else cryRows.push(row);
    },
    listCry: async (_u, limit) => [...cryRows].sort((a, b) => b.at.localeCompare(a.at)).slice(0, limit),
    recordCryVerdict: async (_u, at, verdict, actualReason) => {
      const i = cryRows.findIndex((x) => x.at === at);
      if (i < 0) return false;
      cryRows[i] = { ...cryRows[i], verdict, actualReason };
      return true;
    },
    cryStats: async () => ({ analyses: cryRows.length, byReason: [], unrated: cryRows.length, lastAt: null, firstAt: null }),
    getCryThreshold: async () => cryThresholdRow,
    setCryThreshold: async (v) => {
      cryThresholdRow = { minConfidence: v.minConfidence, updatedAt: new Date().toISOString(), updatedBy: v.updatedBy };
    },
    recordWeight: async (_u, w) => {
      const i = weightRows.findIndex((x) => x.date === w.date);
      if (i >= 0) weightRows[i] = w; else weightRows.push(w);
    },
    listWeight: async (_u, limit) => [...weightRows].sort((a, b) => b.date.localeCompare(a.date)).slice(0, limit),
    recordKickSession: async (_u, s) => {
      const i = kickRows.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) kickRows[i] = s; else kickRows.push(s);
    },
    listKickSessions: async (_u, limit) => [...kickRows].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    recordContractionSession: async (_u, s) => {
      const i = contractionRows.findIndex((x) => x.endedAt === s.endedAt);
      if (i >= 0) contractionRows[i] = s; else contractionRows.push(s);
    },
    listContractionSessions: async (_u, limit) => [...contractionRows].sort((a, b) => b.endedAt.localeCompare(a.endedAt)).slice(0, limit),
    // Day logs
    upsertDayLog: async (_u, log) => void dayLogs.set(log.date, log),
    listDayLogs: async (_u, from, to) =>
      [...dayLogs.values()].filter((d) => d.date >= from && d.date <= to).sort((a, b) => a.date.localeCompare(b.date)),
    // Postpartum screenings: upsert on the id, newest first — the same shape
    // `ON CONFLICT (user_id, id)` gives, so a re-push updates in the fake too
    // rather than growing the list the way a naive push-only fake would.
    upsertEpds: async (_u, row) => void epdsRows.set(row.id, row),
    listEpds: async (_u, limit) =>
      [...epdsRows.values()].sort((a, b) => b.takenAt.localeCompare(a.takenAt)).slice(0, limit),
    // Safety alerts
    recordAlert: async (_u, a) => void alertRows.unshift(a),
    listAlerts: async (_u, limit) => alertRows.slice(0, limit),
    setAlertOutcome: async (_u, childId, at, outcome) => {
      const row = alertRows.find(
        (a) => a.childId === childId && a.kind === 'sos' && Date.parse(a.at) === Date.parse(at));
      if (!row) return false;
      row.outcome = outcome;
      return true;
    },
    // Profile + device reassignment
    getProfile: async () => profile,
    // The phone is not part of an edit and the fake must not invent one: it
    // keeps whatever sign-in put there, exactly as both real repositories do.
    upsertProfile: async (_u, p) => void (profile = { ...p, phone: profile?.phone ?? null }),
    reassignDevice: async (id, childId) => {
      const d = devices.find((x) => x.id === id);
      if (d) d.childId = childId;
    },
    deleteAccount: async (userId) => {
      if (userId !== USER) return false;
      profile = null;
      children.length = 0;
      devices.length = 0;
      geofences.clear();
      sleepRows.length = 0;
      dayLogs.clear();
      alertRows.length = 0;
      healthRows.length = 0;
      return true;
    },
    // Admin
    adminStats: async () => ({ activeUsers: 1, devicesOnline: devices.length, alertsToday: pushes.emergency, ingestLastHour: healthRows.length }),
    childrenStats: async () => ({ total: 0, boys: 0, girls: 0, unknown: 0, withDob: 0, byAge: [] }),
    // The reason comes out of the same helper both repositories use, over a
    // reading that really does cross the threshold — a hand-written `code`
    // here would let the feed regress to «EMERGENCY» with this test green.
    recentEmergencies: async () => [{
      id: `${USER}|2026-07-15T08:00:00Z`, userId: USER, displayName: 'Aigerim',
      ...emergencyReason({ systolicMmHg: 162, diastolicMmHg: 108 }),
      severity: 'emergency', at: '2026-07-15T08:00:00Z',
      acknowledgedAt: null, acknowledgedBy: null,
    }],
    acknowledgeEmergency: async () => true,
    adminListUsers: async () => ({ total: 1, users: [{ id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01', lastMetricAt: '2026-07-21T08:00:00.000Z', latestSeverity: 'warning' }] }),
    adminUserHealth: async (userId) => (userId === USER ? { ...HEALTH } : null),
    adminUserDetail: async (userId) =>
      userId === USER
        ? {
            id: USER, displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-11-01', locale: 'ru-KZ',
            // Given, so the panel's rendering of the populated case is exercised;
            // the memory repository seeds them null, which covers the other.
            birthDate: '1996-04-12', city: 'Алматы',
            doctorPhone: '+77007654321', avgCycleLength: 28, avgPeriodLength: 5,
            children: children.map((c) => ({ id: c.id, name: c.name, dateOfBirth: null, zones: 0 })),
            devices: devices.map((d) => ({ ...d, batteryPct: 62 })),
            // The same vitals adminUserHealth answers with, because BOTH real
            // repositories build this field by calling it. The fake used to
            // answer `{hr: 80}` and an empty triage list here while its own
            // health method held six readings and an emergency — so the mother
            // card could be asserted against numbers no repository produces.
            ...HEALTH,
            alerts: [], sleepNights: sleepRows.length, loggedDays: dayLogs.size,
          }
        : null,
    adminDevices: async (limit) =>
      devices.slice(0, limit).map((d) => {
        const live = liveness.get(d.id);
        const defect = defects.get(d.id);
        return {
          id: d.id, deviceId: `row-${d.id}`, name: d.name, kind: d.kind, userId: USER,
          displayName: 'Aigerim', childName: null,
          // Whatever the ingest path stamped, and nulls when it never has —
          // «ни разу не выходило на связь» is a real answer this fake must be
          // able to give.
          batteryPct: live?.batteryPct ?? null,
          lastSeen: live?.at ?? null,
          firmware: live?.firmware ?? null,
          defectAt: defect?.at ?? null,
          defectBy: defect?.by ?? null,
          defectNote: defect?.note ?? null,
        };
      }),
    adminSafetyEvents: async (limit) =>
      alertRows.slice(0, limit).map((a) => ({
        userId: USER, displayName: 'Aigerim', childName: 'Sultan',
        kind: a.kind, zoneName: a.zoneName, at: a.at,
        // Read back off the row this fake stores, so закрытие СОС through
        // setAlertOutcome is visible in the admin feed here exactly as it is
        // in Postgres.
        outcome: a.kind === 'sos' ? (a.outcome ?? null) : null,
        phone: profile?.phone ?? '+77001112233',
      })),
    adminAnalytics: async () => ({
      totalUsers: 1, pregnant: 1, withChildren: children.length, devices: devices.length,
      alerts7d: alertRows.length, sosAllTime: 0, stageDistribution: {}, contentStageKeys: [],
      contentStages: contentRows.size, contentItems: 0, contentLinked: 0,
    }),
    // Computed rather than hand-written, so the fixture cannot claim a shape
    // the real metric code does not produce.
    adminBiMetrics: async () =>
      computeBiMetrics({
        users: [{ id: USER, createdAt: '2026-06-01T00:00:00Z' }],
        events: alertRows.map((a) => ({ userId: USER, at: a.at, kind: 'alert' as const })),
        devices: { total: devices.length, online: devices.length },
        now: new Date('2026-07-15T08:00:00Z'),
      }),
    // An empty business, stated as an empty business. This fixture exists for
    // the health/safety routes; a dashboard number invented here would be a
    // number some other test could then assert on.
    dashboardSnapshot: async (asOf: string) => ({
      asOf,
      users: { total: 1, newToday: 0, new7d: 0, new30d: 0, dau: 0, wau: 0, mau: 0, retentionD7: null },
      mothers: { pregnant: 0, mothers: 0, both: 0, unknown: 1 },
      children: { total: 0, boys: 0, girls: 0, unknown: 0, byAge: [], withDob: 0 },
      devices: { total: devices.length, online: 0, watches: 0, trackers: 0, unassigned: 0, unregistered: 0 },
      cities: [],
      citiesUnknown: 1,
      commerce: {
        leads: { total: 0, new: 0 },
        orders: { total: 0, new: 0, confirmed: 0, shipped: 0, delivered: 0, cancelled: 0 },
        revenueMinor: 0, pipelineMinor: 0, avgOrderMinor: null,
        stock: { units: 0, retailMinor: 0, costMinor: 0, unitsWithoutCost: 0 },
        lowStock: [],
      },
      course: { lessons: 0, granted: 0, started: 0, finished: 0, lessonsCompleted: 0, active7d: 0 },
    }),
    contentCatalog: async () => Object.fromEntries(contentRows),
    putStageContent: async (stageKey, items) => {
      if (items.length === 0) contentRows.delete(stageKey);
      else contentRows.set(stageKey, items);
    },
    // Pregnancy-week overrides: a faithful little store rather than a stub, so
    // this fake answers `GET /pregnancy/weeks` the way the real ones do —
    // nothing edited yet, therefore the shipped contract. `rev` increments,
    // because the served version number is built from it.
    pregnancyWeekOverrides: async () => [...pregWeeks.values()].sort((a, b) => a.week - b.week),
    putPregnancyWeekOverride: async (v) => {
      const prev = pregWeeks.get(v.week);
      pregWeeks.set(v.week, {
        ...v, rev: (prev?.rev ?? 0) + 1,
        updatedAt: '2026-07-15T08:00:00Z', updatedBy: v.updatedBy,
      });
    },
    pregnancyWeekMotherCounts: async () => ({}),
    // Frame 16b → screen 37. Nothing edited, therefore the shipped emergency
    // contract, which is what `/emergency-help` must answer here. The editor
    // itself is driven end to end in emergencyHelpEditor.test.ts against the
    // real memory repository.
    emergencyHelpOverrides: async () => [],
    putEmergencyHelpOverride: async () => {},
    // Frames 15/15a/15b. Nothing edited, therefore the shipped immunisation
    // contract — which is exactly what this file's assertions about
    // `/vaccination/schedule` expect. The editor itself is driven end to end in
    // vaccinationEditor.test.ts against the real memory repository.
    vaccinationOverrides: async () => [],
    putVaccinationOverride: async () => {},
    vaccinationSettings: async () => null,
    putVaccinationSettings: async () => {},
    vaccinationScheduleLog: async () => [],
    vaccinationCoverage: async () => ({ childAges: [], ticks: [], childrenWithoutDob: 0 }),
    // Frame 06. This file is about ingest and the health path; broadcasts are
    // driven end to end in broadcasts.test.ts against the real memory
    // repository, so these answer emptily rather than half-faking a ledger the
    // weekly-gap rule depends on.
    listBroadcasts: async () => [],
    saveBroadcast: async () => {},
    broadcastAudience: async () => ({ matched: 0, excluded: 0 }),
    publishBroadcast: async () => null,
    listAnnouncements: async () => [],
    // Frame 25. A REAL little store rather than a stub returning defaults: the
    // settings route is a read-your-writes contract, and a fake that forgets
    // what it was told would make «сохранилось» pass while the screen resets
    // itself on every open. `notifyPrefs` is captured above so a test can look
    // at what the route actually stored.
    getNotificationPrefs: async () => ({
      ...(notifyPrefs ?? {
        zoneEvents: true, checkIn: true, lowBattery: true, updates: true,
        quietStart: null, quietEnd: null,
      }),
      timezone: notifyTz,
      updatedAt: notifyPrefs ? '2026-07-15T08:00:00.000Z' : null,
    }),
    putNotificationPrefs: async (_userId, prefs) => { notifyPrefs = { ...prefs }; },
    /// Read back by getNotificationPrefs above rather than swallowed: a fake
    /// that accepts a zone and keeps answering Asia/Almaty would make the write
    /// path look wired while the column stayed unwritten — the exact defect.
    setUserTimezone: async (_userId, tz) => { notifyTz = tz; },
    recordPushDelivery: async (row) => void pushLedger.push({ ...row }),
    pushDeliverySummary: async (days) => ({
      windowDays: days,
      kinds: [],
      deadTokens: 0,
      muted: { zoneEvents: 0, checkIn: 0, lowBattery: 0, updates: 0, quietHours: 0, configured: notifyPrefs ? 1 : 0 },
      lastAt: null,
    }),
    writeAudit: async (e) => void audit.push({ ...e, target: e.target ?? null, at: '2026-07-15T08:00:00Z' }),
    listAudit: async () =>
      // reason included: the interface declares it, and a fake that omits it
      // was how the security summary compiled against a shape nothing returns.
      audit.map((a) => ({
        ...a, staffName: null, staffPhone: null, targetName: null,
        reason: (a as {reason?: string | null}).reason ?? null,
      })),
  };

  const server = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'Rest and hydrate gently.' },
      ingest: {
        cacheLocation: async (fix) => void (lastLocation = fix),
        resolveTransition: async (childId, fenceId, inside) => {
          const key = `${childId}:${fenceId}`;
          const next = inside ? 'in' : 'out';
          const prev = fenceState.get(key) ?? null;
          fenceState.set(key, next);
          if (prev === next) return null;
          if (prev === null && next === 'out') return null;
          return inside ? 'enter' : 'exit';
        },
        sendEmergencyPush: async () => void pushes.emergency++,
        sendGeofencePush: async () => void pushes.geofence++,
      },
      cacheLastLocation: async () => lastLocation,
      setBpCalibration: async () => {},
      authUser,
      authAdmin,
      chatLimiter,
      ingestLimiter,
    },
    { logger: false },
  );

  return {
    server, events, pushes, healthRows, calRows, pushLedger,
    get lastLocation() { return lastLocation; },
    /** What PUT /notifications/settings actually stored, or null. */
    get notifyPrefs() { return notifyPrefs; },
  };
}

let ctx: ReturnType<typeof makeDeps>;
let app: FastifyInstance;
beforeEach(async () => {
  ctx = makeDeps();
  app = ctx.server;
  await app.ready();
});

// The return type is stated explicitly because inject() also has a
// callback-style overload, and without it TypeScript resolves these to
// `void & Promise<Response> & Chain` — every `r.statusCode` in the file then
// fails to typecheck even though the calls are correct.
const post = (url: string, payload: InjectPayload): Promise<InjectResponse> =>
  app.inject({ method: 'POST', url, payload });
const get = (url: string): Promise<InjectResponse> =>
  app.inject({ method: 'GET', url });

describe('server wiring (in-process)', () => {
  it('GET /health', async () => {
    const r = await get('/health');
    expect(r.statusCode).toBe(200);
    expect(r.json().ok).toBe(true);
  });

  // ---- Erasing the account ----
  // The app's reset says "all data will be erased" and only cleared the phone;
  // there was no server-side deletion at all. With telemetry syncing, her
  // blood-pressure history, her child's name and date of birth and the
  // coordinates of her home and her child's school outlived the account she
  // believed she had removed.
  it('erases the account and everything belonging to it', async () => {
    await post('/children', { id: '55555555-5555-5555-5555-555555555555', name: 'Sultan' });
    await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 118,
            diastolicMmHg: 76,
          },
        },
      ],
    });
    expect((await get('/children')).json().children).toHaveLength(1);

    const r = await app.inject({ method: 'DELETE', url: '/account' });
    expect(r.statusCode).toBe(204);
    expect((await get('/children')).json().children).toHaveLength(0);
  });

  it('refuses to erase without a session', async () => {
    // There is no id in the path, so this can never be aimed at another
    // account — but it must still be impossible to fire unauthenticated.
    const { server } = makeDeps(async () => null); // nobody signed in
    await server.ready();
    const r = await server.inject({ method: 'DELETE', url: '/account' });
    expect(r.statusCode).toBe(401);
    await server.close();
  });

  // ---- Ingest is bounded, but only for a runaway ----
  it('stops a client that will not stop posting', async () => {
    // Ingest was unlimited on the reasoning that dropping it would lose health
    // data. A 429 does not drop anything — the client requeues, exactly as it
    // does with no signal — so the real choice was between a limit and letting
    // one authenticated caller write to a timeseries database as fast as it
    // can post 500-item batches.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 3, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, undefined, limiter);
    await server.ready();

    const send = () =>
      server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: {
          items: [
            {
              type: 'telemetry',
              payload: {
                deviceId: '',
                source: 'manual',
                recordedAt: new Date().toISOString(),
                heartRateBpm: 72,
              },
            },
          ],
        },
      });

    for (let i = 0; i < 3; i++) {
      expect((await send()).statusCode).toBe(200);
    }
    const blocked = await send();
    expect(blocked.statusCode).toBe(429);
    // Retry-After so the client backs off by the server's clock, not a guess.
    expect(blocked.headers['retry-after']).toBeTruthy();
    expect(blocked.json().retryAfterSec).toBeGreaterThan(0);
    await server.close();
  });

  it('a legitimate backlog drain never meets the limit', async () => {
    // The worst legitimate case is a phone coming back after a long spell
    // offline: a full 5000-item queue leaves in 25 back-to-back requests at
    // maxFlushItems=200. If the limit bit there it would cost real readings,
    // because the queue trims its oldest ordinary items once it overflows.
    const { server } = makeDeps(); // the production default: 120 per 5 min
    await server.ready();
    for (let i = 0; i < 25; i++) {
      const r = await server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: {
          items: [
            {
              type: 'telemetry',
              payload: {
                deviceId: '',
                source: 'manual',
                recordedAt: new Date().toISOString(),
                heartRateBpm: 70 + i,
              },
            },
          ],
        },
      });
      expect(r.statusCode, `request ${i + 1} of the drain was rejected`).toBe(200);
    }
    await server.close();
  });

  it('an unauthenticated ingest never spends the budget', async () => {
    // Same reasoning as the chat limiter: taking a token before knowing who is
    // asking would let anyone exhaust a named user's allowance.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(async () => null, undefined, undefined, limiter);
    await server.ready();
    for (let i = 0; i < 5; i++) {
      const r = await server.inject({
        method: 'POST',
        url: '/ingest/batch',
        payload: { items: [] },
      });
      expect(r.statusCode).toBe(401);
    }
    expect(limiter.size).toBe(0);
    await server.close();
  });

  it('rejects a malformed batch with 400 (zod)', async () => {
    const r = await post('/ingest/batch', { items: [{ type: 'telemetry', payload: { deviceId: '' } }] });
    expect(r.statusCode).toBe(400);
  });

  // ---- Readings entered by hand ----
  // The most trustworthy number the product has is a cuff reading the mother
  // types in — an actual cuff, not a PPG estimate. Attribution went only
  // through deviceOwner(), so a reading with no device to name was refused at
  // the edge and dropped by the handler. Her clinician's view never showed
  // one, and nothing anywhere said so.
  it('accepts a hand-entered reading and attributes it to the caller', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 118,
            diastolicMmHg: 76,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().telemetryCount).toBe(1);
    expect(r.json().rejected).toBe(0);
  });

  it('runs the server-side emergency backstop on a hand-entered reading', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: '',
            source: 'manual',
            recordedAt: new Date().toISOString(),
            systolicMmHg: 175,
            diastolicMmHg: 118,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().emergencies).toBe(1);
  });

  it('still refuses a BAND reading with no device', async () => {
    // The relaxation is for hand-entered readings only. A band reading with no
    // device cannot be attributed to anyone either, and must keep failing at
    // the edge rather than being quietly credited to whoever posted it.
    const r = await post('/ingest/batch', {
      items: [
        { type: 'telemetry', payload: { deviceId: '', recordedAt: new Date().toISOString() } },
      ],
    });
    expect(r.statusCode).toBe(400);
  });

  it('still refuses a band reading for a device the caller does not own', async () => {
    const r = await post('/ingest/batch', {
      items: [
        {
          type: 'telemetry',
          payload: {
            deviceId: 'someone-elses-band',
            recordedAt: new Date().toISOString(),
            heartRateBpm: 80,
          },
        },
      ],
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().rejected).toBe(1);
    expect(r.json().telemetryCount).toBe(0);
  });

  it('ingests emergency telemetry + Home enter, dedups, then exit', async () => {
    const home = { lat: 43.238949, lng: 76.889709 };
    const away = { lat: 43.30, lng: 77.0 };

    const r1 = await post('/ingest/batch', {
      items: [
        { type: 'telemetry', payload: { deviceId: DEVICE, recordedAt: new Date().toISOString(), systolicMmHg: 148, diastolicMmHg: 95 } },
        { type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } },
      ],
    });
    expect(r1.statusCode).toBe(200);
    const s1 = r1.json();
    expect(s1.telemetryCount).toBe(1);
    expect(s1.emergencies).toBe(1);
    expect(ctx.pushes.emergency).toBe(1);
    expect(s1.geofenceEvents.some((e: GeofenceEvent) => e.geofenceName === 'Home' && e.transition === 'enter')).toBe(true);

    // The crossing now reaches the safety_alerts feed the back-office reads. It
    // used to land only in geofence_events, so GET /admin/safety — the
    // operational child-safety view — was permanently empty.
    const safety = (await get('/admin/safety')).json().events;
    expect(safety.some((e: { kind: string; zoneName: string }) => e.kind === 'entered' && e.zoneName === 'Home')).toBe(true);
    // ...and the guardian can read her own alert feed too.
    const mine = (await get('/alerts')).json().alerts;
    expect(mine.some((a: { kind: string; zoneName: string }) => a.kind === 'entered' && a.zoneName === 'Home')).toBe(true);

    // Duplicate Home fix → no second alert (real dedup).
    const r2 = await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    expect(r2.json().geofenceEvents).toHaveLength(0);

    // Move away → exit.
    const r3 = await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: away, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    expect(r3.json().geofenceEvents.some((e: GeofenceEvent) => e.transition === 'exit')).toBe(true);
  });

  it('rejects telemetry from an unknown device', async () => {
    const r = await post('/ingest/batch', {
      items: [{ type: 'telemetry', payload: { deviceId: '99999999-9999-9999-9999-999999999999', recordedAt: new Date().toISOString(), heartRateBpm: 80 } }],
    });
    expect(r.json().rejected).toBe(1);
    expect(r.json().telemetryCount).toBe(0);
  });

  it('returns last known child location', async () => {
    const away = { lat: 43.30, lng: 77.0 };
    await post('/ingest/batch', {
      items: [{ type: 'location', payload: { childId: CHILD, coords: away, source: 'gps', observedAt: new Date().toISOString() } }],
    });
    const r = await get(`/children/${CHILD}/location`);
    expect(r.statusCode).toBe(200);
    expect(r.json().coords.lat).toBeCloseTo(away.lat);
  });

  it('computes BP calibration offsets', async () => {
    const r = await post('/calibration/bp', {
      userId: USER, cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      measuredAt: new Date().toISOString(),
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().systolicOffset).toBe(8);
    expect(r.json().diastolicOffset).toBe(4);
  });

  it('accepts a BP calibration with no body userId (identity from the session)', async () => {
    const r = await post('/calibration/bp', {
      cuffSystolic: 130, cuffDiastolic: 85, ppgSystolic: 122, ppgDiastolic: 80,
      measuredAt: '2026-07-22T09:00:00.000Z',
    });
    expect(r.statusCode).toBe(200);
    // ...and the owner can pull the latest back for a new-device restore.
    const got = (await get('/calibration/bp')).json().calibration;
    expect(got.systolicOffset).toBe(8); // 130 − 122
    expect(got.diastolicOffset).toBe(5); // 85 − 80
    expect(got.cuffSystolic).toBe(130);
    // ...and it surfaces in the clinician's wellness view.
    const wellness = (await get(`/admin/users/${USER}/wellness${WHY}`)).json();
    expect(wellness.bpCalibration.diastolicOffset).toBe(5);
  });

  it('rejects a BP calibration whose body userId is not the caller', async () => {
    const r = await post('/calibration/bp', {
      userId: '99999999-9999-9999-9999-999999999999',
      cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
      measuredAt: '2026-07-22T09:00:00.000Z',
    });
    expect(r.statusCode).toBe(403);
  });

  it('AI chat with a critical reading forces the emergency screen (LLM bypassed)', async () => {
    const r = await post('/ai/chat', {
      userId: USER, locale: 'ru-KZ', message: 'is everything okay?',
      latestTelemetry: { systolicMmHg: 150, diastolicMmHg: 96 },
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().action).toBe('SHOW_EMERGENCY_SCREEN');
  });

  it('AI chat normal question returns a grounded reply', async () => {
    const r = await post('/ai/chat', { userId: USER, locale: 'en', message: 'tips for sleep?' });
    expect(r.json().kind).toBe('chat');
  });
});

describe('/ai/chat rate limiting', () => {
  // The route spends money and reaches a third party on every call, and had no
  // limit of any kind — a broken retry loop was as expensive as an abusive one.
  const buildLimited = async (limit: number) => {
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, limiter);
    await server.ready();
    return { app: server, limiter };
  };

  const chat = (app: FastifyInstance, userId = USER) =>
    app.inject({
      method: 'POST',
      url: '/ai/chat',
      payload: { userId, locale: 'en', message: 'hello' } as InjectPayload,
    });

  it('refuses with 429 once the caller is over the limit', async () => {
    const { app } = await buildLimited(2);
    expect((await chat(app)).statusCode).toBe(200);
    expect((await chat(app)).statusCode).toBe(200);
    const over = await chat(app);
    expect(over.statusCode).toBe(429);
    expect(over.json().error).toBe('rate_limited');
    await app.close();
  });

  it('tells the client how long to wait, in a header and the body', async () => {
    const { app } = await buildLimited(1);
    await chat(app);
    const over = await chat(app);
    expect(Number(over.headers['retry-after'])).toBeGreaterThan(0);
    expect(over.json().retryAfterSec).toBeGreaterThan(0);
    await app.close();
  });

  it('an unauthenticated request never spends the budget', async () => {
    // The limit is taken AFTER auth on purpose: if it ran first, anyone could
    // burn a stranger's allowance without ever proving who they are — a
    // denial-of-service on the assistant, aimed at one named user.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(async () => null, undefined, limiter); // nobody signed in
    await server.ready();

    for (let i = 0; i < 5; i++) {
      expect((await chat(server)).statusCode).toBe(401);
    }
    expect(limiter.size).toBe(0); // not one token spent
    await server.close();
  });

  it('a forbidden request does not spend the budget either', async () => {
    // Asking as somebody else is rejected at the ownership check; that must
    // not cost the impersonated user their allowance.
    const { RateLimiter } = await import('../http/rateLimit');
    const limiter = new RateLimiter({ limit: 1, windowMs: 60_000 });
    const { server } = makeDeps(undefined, undefined, limiter);
    await server.ready();

    const r = await server.inject({
      method: 'POST',
      url: '/ai/chat',
      payload: { userId: CHILD, locale: 'en', message: 'hi' } as InjectPayload,
    });
    expect(r.statusCode).toBe(403);
    expect(limiter.size).toBe(0);
    await server.close();
  });
});

describe('CRUD + history routes (in-process)', () => {
  it('children: create → list → delete', async () => {
    expect((await get('/children')).json().children).toHaveLength(0);
    const id = '66666666-6666-6666-6666-666666666666';
    const created = await post('/children', { id, name: 'Sultan' });
    expect(created.statusCode).toBe(201);
    expect((await get('/children')).json().children).toHaveLength(1);
    const del = await app.inject({ method: 'DELETE', url: `/children/${id}` });
    expect(del.statusCode).toBe(204);
    expect((await get('/children')).json().children).toHaveLength(0);
  });

  it('children: rejects empty name (zod 400)', async () => {
    expect((await post('/children', { id: '66666666-6666-6666-6666-666666666666', name: '' })).statusCode).toBe(400);
  });

  it('children: rejects a non-UUID id (zod 400)', async () => {
    expect((await post('/children', { id: 'child-1', name: 'Sultan' })).statusCode).toBe(400);
  });

  it('children: upsert is idempotent on the id and carries gender + DOB', async () => {
    const id = '77777777-7777-7777-7777-777777777777';
    await post('/children', { id, name: 'Aruzhan', gender: 'girl', dateOfBirth: '2024-03-01' });
    await post('/children', { id, name: 'Aruzhan B.', gender: 'girl', dateOfBirth: '2024-03-01' });
    const kids = (await get('/children')).json().children;
    expect(kids).toHaveLength(1); // updated, not duplicated
    expect(kids[0].name).toBe('Aruzhan B.');
    // GET returns gender + DOB so a new device can restore the full child.
    expect(kids[0].gender).toBe('girl');
    expect(kids[0].dateOfBirth).toBe('2024-03-01');
  });

  it('devices: create → list → delete', async () => {
    const r = await post('/devices', { id: 'AA:BB', name: 'Band', kind: 'band' });
    expect(r.statusCode).toBe(201);
    expect((await get('/devices')).json().devices).toHaveLength(1);
    expect((await post('/devices', { id: 'x', kind: 'nope' })).statusCode).toBe(400); // bad kind
    const del = await app.inject({ method: 'DELETE', url: '/devices/AA:BB' });
    expect(del.statusCode).toBe(204);
    expect((await get('/devices')).json().devices).toHaveLength(0);
  });

  it('geofences: upsert a circle for a child (client id), then list', async () => {
    const gid = 'aaaaaaaa-0000-4000-8000-000000000001';
    const r = await post(`/children/${CHILD}/geofences`, {
      id: gid, name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 80,
    });
    expect(r.statusCode).toBe(201);
    // Re-sync the same id with a new radius → updates, not duplicates.
    await post(`/children/${CHILD}/geofences`, {
      id: gid, name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 120,
    });
    const list = (await get(`/children/${CHILD}/geofences`)).json().geofences;
    const parks = list.filter((g: { name: string }) => g.name === 'Park');
    expect(parks).toHaveLength(1);
    expect(parks[0].radiusM).toBe(120);
  });

  it('geofences: rejects a non-UUID id (zod 400)', async () => {
    const r = await post(`/children/${CHILD}/geofences`, {
      id: 'zone-1', name: 'Park', shape: 'circle', center: { lat: 43.24, lng: 76.9 }, radiusM: 80,
    });
    expect(r.statusCode).toBe(400);
  });

  it('newborn events: record for a child, read back via admin wellness (newest first)', async () => {
    expect((await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T08:00:00.000Z', kind: 'feed', detail: 'left' } })).statusCode).toBe(201);
    await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T10:00:00.000Z', kind: 'diaper', detail: 'wet' } });
    const evs = (await get(`/admin/users/${USER}/wellness${WHY}`)).json().newbornEvents;
    expect(evs.length).toBeGreaterThanOrEqual(2);
    expect(evs[0].kind).toBe('diaper'); // newest first
    expect(evs[0].childName).toBeTruthy();

    // ...and the owner can pull the same events (tagged with childId) to restore
    // the baby log on a new device.
    const restore = (await get('/newborn-events')).json().events;
    expect(restore.length).toBeGreaterThanOrEqual(2);
    expect(restore[0].childId).toBe(CHILD);
    expect(restore.some((e: { kind: string }) => e.kind === 'feed')).toBe(true);
  });

  it('newborn events: rejects a bad kind (zod 400)', async () => {
    const r = await app.inject({ method: 'POST', url: `/children/${CHILD}/newborn-events`,
      payload: { at: '2026-07-21T08:00:00.000Z', kind: 'burp' } });
    expect(r.statusCode).toBe(400);
  });

  it('growth: record a measurement, keep one per day, read it back + admin wellness', async () => {
    expect((await app.inject({ method: 'POST', url: `/children/${CHILD}/growth`,
      payload: { at: '2026-07-20T00:00:00.000', weightKg: 7.2, heightCm: 66 } })).statusCode).toBe(201);
    // Same day again → replaces, not a second row.
    await app.inject({ method: 'POST', url: `/children/${CHILD}/growth`,
      payload: { at: '2026-07-20', weightKg: 7.4 } });
    await app.inject({ method: 'POST', url: `/children/${CHILD}/growth`,
      payload: { at: '2026-07-27', weightKg: 7.6, heightCm: 67 } });

    const rows = (await get('/growth')).json().growth;
    const mine = rows.filter((g: { childId: string }) => g.childId === CHILD);
    expect(mine).toHaveLength(2); // two distinct days
    const d20 = mine.find((g: { at: string }) => g.at === '2026-07-20');
    expect(d20.weightKg).toBe(7.4); // the correction won
    expect(d20.childName).toBeTruthy();

    // ...and it reaches the clinician's wellness view.
    const wellness = (await get(`/admin/users/${USER}/wellness${WHY}`)).json();
    expect(wellness.growth.some((g: { at: string; heightCm: number }) => g.at === '2026-07-27' && g.heightCm === 67)).toBe(true);
  });

  it('growth: rejects a measurement with neither weight nor height (zod 400)', async () => {
    const r = await app.inject({ method: 'POST', url: `/children/${CHILD}/growth`,
      payload: { at: '2026-07-20' } });
    expect(r.statusCode).toBe(400);
  });

  it('growth: rejects an implausible weight (typo filter, 400)', async () => {
    const r = await app.inject({ method: 'POST', url: `/children/${CHILD}/growth`,
      payload: { at: '2026-07-20', weightKg: 720 } }); // slipped decimal
    expect(r.statusCode).toBe(400);
  });

  it('adherence: record doses per day, latest count wins, read back + admin wellness', async () => {
    const MED = 'med-iron-1';
    await post('/medications', { id: MED, name: 'Iron', dose: '30mg', perDay: 2 });

    expect((await app.inject({ method: 'PUT', url: `/medications/${MED}/doses`,
      payload: { date: '2026-07-22', count: 1 } })).statusCode).toBe(200);
    // Second dose the same day → the count is replaced, not summed to a new row.
    await app.inject({ method: 'PUT', url: `/medications/${MED}/doses`, payload: { date: '2026-07-22', count: 2 } });
    await app.inject({ method: 'PUT', url: `/medications/${MED}/doses`, payload: { date: '2026-07-23', count: 1 } });

    const doses = (await get('/doses')).json().doses;
    expect(doses).toHaveLength(2); // two distinct days
    expect(doses.find((d: { date: string }) => d.date === '2026-07-22').count).toBe(2);

    // ...and adherence reaches the clinician's wellness view.
    const wellness = (await get(`/admin/users/${USER}/wellness${WHY}`)).json();
    expect(wellness.doses.some((d: { medId: string; count: number }) => d.medId === MED && d.count === 2)).toBe(true);
  });

  it('adherence: logging against an unknown medication is refused (403 owner guard)', async () => {
    const r = await app.inject({ method: 'PUT', url: '/medications/no-such-med/doses',
      payload: { date: '2026-07-22', count: 1 } });
    expect(r.statusCode).toBe(403); // requireOwned: no owner → not yours
  });

  it('adherence: rejects a malformed dose body (400)', async () => {
    const MED = 'med-folate-1';
    await post('/medications', { id: MED, name: 'Folate', dose: '400mcg', perDay: 1 });
    const r = await app.inject({ method: 'PUT', url: `/medications/${MED}/doses`,
      payload: { date: '22-07-2026', count: 1 } }); // wrong date shape
    expect(r.statusCode).toBe(400);
  });

  it('vaccines: mark done, unmark, read back + admin wellness', async () => {
    expect((await app.inject({ method: 'PUT', url: `/children/${CHILD}/vaccines`,
      payload: { vaccineKey: 'bcg/1', done: true } })).statusCode).toBe(200);
    await app.inject({ method: 'PUT', url: `/children/${CHILD}/vaccines`, payload: { vaccineKey: 'dtp/1', done: true } });
    await app.inject({ method: 'PUT', url: `/children/${CHILD}/vaccines`, payload: { vaccineKey: 'dtp/1', done: true } }); // idempotent

    let recorded = (await get('/vaccines')).json().vaccines.filter((v: { childId: string }) => v.childId === CHILD);
    expect(recorded.map((v: { vaccineKey: string }) => v.vaccineKey).sort()).toEqual(['bcg/1', 'dtp/1']);
    expect(recorded[0].childName).toBeTruthy();

    // Unmark one → it disappears (presence is "done").
    await app.inject({ method: 'PUT', url: `/children/${CHILD}/vaccines`, payload: { vaccineKey: 'bcg/1', done: false } });
    recorded = (await get('/vaccines')).json().vaccines.filter((v: { childId: string }) => v.childId === CHILD);
    expect(recorded.map((v: { vaccineKey: string }) => v.vaccineKey)).toEqual(['dtp/1']);

    // ...and it reaches the clinician's wellness view.
    const wellness = (await get(`/admin/users/${USER}/wellness${WHY}`)).json();
    expect(wellness.vaccines.some((v: { vaccineKey: string }) => v.vaccineKey === 'dtp/1')).toBe(true);
  });

  it('vaccines: rejects a body with no key (400)', async () => {
    const r = await app.inject({ method: 'PUT', url: `/children/${CHILD}/vaccines`,
      payload: { done: true } });
    expect(r.statusCode).toBe(400);
  });

  it('emergency: upsert a child medical-ID, then read it via the admin wellness view', async () => {
    const r = await app.inject({
      method: 'PUT', url: `/children/${CHILD}/emergency`,
      payload: { bloodType: 'O+', allergies: 'penicillin', conditions: '', medications: '',
        doctorName: 'Dr Aliyeva', doctorPhone: '+7700', contactName: 'Gran', contactPhone: '+7701', notes: '' },
    });
    expect(r.statusCode).toBe(200);
    // The admin drawer reads it back joined with the child's name.
    const ids = (await get(`/admin/users/${USER}/wellness${WHY}`)).json().medicalIds;
    const card = ids.find((m: { childId: string }) => m.childId === CHILD);
    expect(card.bloodType).toBe('O+');
    expect(card.allergies).toBe('penicillin');
    expect(card.childName).toBeTruthy();

    // ...and the owner can pull it back for a new-device restore.
    const restore = await get(`/children/${CHILD}/emergency`);
    expect(restore.statusCode).toBe(200);
    expect(restore.json().medicalId.bloodType).toBe('O+');
    expect(restore.json().medicalId.contactPhone).toBe('+7701');
  });

  it('emergency: GET returns null when a child has no medical-ID', async () => {
    const fresh = '44444444-4444-4444-4444-444444444444';
    await post('/children', { id: fresh, name: 'Nsurlan', gender: 'boy', dateOfBirth: null });
    const r = await get(`/children/${fresh}/emergency`);
    expect(r.statusCode).toBe(200);
    expect(r.json().medicalId).toBeNull();
  });

  it('metrics history query validates + returns points', async () => {
    expect((await get('/metrics?from=a&to=b&metric=nope')).statusCode).toBe(400);
    const r = await get('/metrics?from=2026-07-15T00:00:00Z&to=2026-07-16T00:00:00Z&metric=hr');
    expect(r.statusCode).toBe(200);
    expect(r.json().points.length).toBeGreaterThan(0);
  });

  it('401 when the request is unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/children' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'POST', url: '/children', payload: { name: 'X' } })).statusCode).toBe(401);
  });
});

describe('sleep / cycle / alerts routes (in-process)', () => {
  it('sleep: record nights → list newest-first', async () => {
    expect((await get('/sleep')).json().nights).toHaveLength(0);
    expect((await post('/sleep', { night: '2026-07-14', deepMin: 70, remMin: 90, lightMin: 250, awakeMin: 35 })).statusCode).toBe(201);
    await post('/sleep', { night: '2026-07-15', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25 });
    const nights = (await get('/sleep')).json().nights;
    expect(nights).toHaveLength(2);
    expect(nights[0].night).toBe('2026-07-15'); // newest first
    expect(nights[0].deepMin).toBe(95);
  });

  it('sleep: a hand-entered night round-trips its source + typed asleep total', async () => {
    // A manual night has no measured stage split; the app sends the typed total
    // in manualAsleepMin. Both must survive the backup so a new device restores
    // the night as manual (not as a band night with an inferred split).
    expect((await post('/sleep', {
      night: '2026-07-16', deepMin: 0, remMin: 0, lightMin: 430, awakeMin: 20,
      source: 'manual', manualAsleepMin: 430,
    })).statusCode).toBe(201);
    const night = (await get('/sleep')).json().nights.find((n: { night: string }) => n.night === '2026-07-16');
    expect(night.source).toBe('manual');
    expect(night.manualAsleepMin).toBe(430);
  });

  it('cry history: record results → list newest-first (restored on a new device)', async () => {
    expect((await get('/cry/results')).json().results).toHaveLength(0);
    expect((await post('/cry/results', { at: '2026-07-20T09:00:00.000Z', reason: 'hungry', confidence: 0.82 })).statusCode).toBe(201);
    await post('/cry/results', { at: '2026-07-20T11:30:00.000Z', reason: 'tired', confidence: 0.64 });
    const results = (await get('/cry/results')).json().results;
    expect(results).toHaveLength(2);
    expect(results[0].at).toBe('2026-07-20T11:30:00.000Z'); // newest first
    expect(results[0].reason).toBe('tired');
    expect(results[0].confidence).toBeCloseTo(0.64);
  });

  it('cry history: rejects a bad confidence (zod 400)', async () => {
    expect((await post('/cry/results', { at: '2026-07-20T09:00:00.000Z', reason: 'hungry', confidence: 1.5 })).statusCode).toBe(400);
  });

  it('sleep: rejects out-of-range minutes (zod 400)', async () => {
    expect((await post('/sleep', { night: '2026-07-15', deepMin: -1, remMin: 0, lightMin: 0, awakeMin: 0 })).statusCode).toBe(400);
    expect((await post('/sleep', { night: '2026-07-15', deepMin: 0, remMin: 0, lightMin: 9999, awakeMin: 0 })).statusCode).toBe(400);
  });

  it('weight: record → list newest-first, upsert on the date', async () => {
    expect((await get('/weight')).json().entries).toHaveLength(0);
    expect((await post('/weight', { date: '2026-07-14', kg: 64.2 })).statusCode).toBe(201);
    await post('/weight', { date: '2026-07-15', kg: 64.5 });
    await post('/weight', { date: '2026-07-15', kg: 64.8 }); // same day → updates
    const entries = (await get('/weight')).json().entries;
    expect(entries).toHaveLength(2); // not 3 — the 15th was upserted
    expect(entries[0].date).toBe('2026-07-15'); // newest first
    expect(entries[0].kg).toBe(64.8);
  });

  it('weight: rejects an out-of-range or misfingered value (zod 400)', async () => {
    expect((await post('/weight', { date: '2026-07-15', kg: 3.5 })).statusCode).toBe(400); // grams, not kg
    expect((await post('/weight', { date: '2026-07-15', kg: 3500 })).statusCode).toBe(400);
    expect((await post('/weight', { date: 'nope', kg: 64 })).statusCode).toBe(400);
  });

  it('kick sessions: record → list newest-first, upsert on endedAt', async () => {
    expect((await get('/kick-sessions')).json().sessions).toHaveLength(0);
    expect((await post('/kick-sessions', { endedAt: '2026-07-20T10:00:00.000Z', count: 10, durationSec: 600 })).statusCode).toBe(201);
    await post('/kick-sessions', { endedAt: '2026-07-21T10:00:00.000Z', count: 8, durationSec: 900 });
    await post('/kick-sessions', { endedAt: '2026-07-21T10:00:00.000Z', count: 9, durationSec: 800 }); // same instant → updates
    const s = (await get('/kick-sessions')).json().sessions;
    expect(s).toHaveLength(2);
    expect(s[0].count).toBe(9); // newest, upserted
  });

  it('contraction sessions: record → list, and reject a bad body', async () => {
    expect((await post('/contraction-sessions', { endedAt: '2026-07-22T02:00:00.000Z', count: 6, avgDurationSec: 55, avgIntervalSec: 300 })).statusCode).toBe(201);
    const s = (await get('/contraction-sessions')).json().sessions;
    expect(s[0].avgIntervalSec).toBe(300);
    expect((await post('/contraction-sessions', { endedAt: 'nope', count: 1, avgDurationSec: 1, avgIntervalSec: 1 })).statusCode).toBe(400);
  });

  it('medications: upsert on the client id → list → delete', async () => {
    expect((await get('/medications')).json().medications).toHaveLength(0);
    expect((await post('/medications', { id: 'med-1', name: 'Фолиевая кислота', dose: '400 мкг', perDay: 1 })).statusCode).toBe(201);
    await post('/medications', { id: 'med-1', name: 'Фолиевая кислота', dose: '800 мкг', perDay: 2 }); // same id → updates
    const meds = (await get('/medications')).json().medications;
    expect(meds).toHaveLength(1); // upserted, not duplicated
    expect(meds[0].dose).toBe('800 мкг');
    expect(meds[0].perDay).toBe(2);
    const del = await app.inject({ method: 'DELETE', url: '/medications/med-1' });
    expect(del.statusCode).toBe(204);
    expect((await get('/medications')).json().medications).toHaveLength(0);
  });

  it('medications: rejects an empty name (zod 400)', async () => {
    expect((await post('/medications', { id: 'med-x', name: '' })).statusCode).toBe(400);
  });

  it('cycle day logs: upsert (PUT) + range query', async () => {
    const put = await app.inject({
      method: 'PUT', url: '/cycle/days',
      payload: { date: '2026-07-15', mood: 'calm', symptoms: ['cramps'], kicks: 3, flow: 'medium' },
    });
    expect(put.statusCode).toBe(200);
    // upsert same day updates in place
    await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', mood: 'happy', symptoms: [], kicks: 5 } });
    const days = (await get('/cycle/days?from=2026-07-01&to=2026-07-31')).json().days;
    expect(days).toHaveLength(1);
    expect(days[0].mood).toBe('happy');
    expect(days[0].kicks).toBe(5);
    expect(days[0].flow).toBeNull(); // omitted → cleared to null
  });

  it('cycle day logs: a typed note round-trips so it survives a new device', async () => {
    // The app sends DayLog.note and reads it back; the backend used to strip it
    // (no column), so a note typed on a day was lost on restore.
    await app.inject({
      method: 'PUT', url: '/cycle/days',
      payload: { date: '2026-07-18', symptoms: [], kicks: 0, note: 'Кружилась голова утром' },
    });
    const days = (await get('/cycle/days?from=2026-07-01&to=2026-07-31')).json().days;
    const day = days.find((d: { date: string }) => d.date === '2026-07-18');
    expect(day.note).toBe('Кружилась голова утром');
  });

  it('cycle day logs: rejects a bad date + bad enum (zod 400)', async () => {
    expect((await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '15-07-2026' } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', flow: 'gushing' } })).statusCode).toBe(400);
    expect((await get('/cycle/days?from=only-one')).statusCode).toBe(400); // missing `to`
    // A malformed date is a client error, not something to hand to the database.
    expect((await get('/cycle/days?from=nonsense&to=2026-07-31')).statusCode).toBe(400);
    // Ordered correctly, so this can only 400 because the date itself is invalid.
    expect((await get('/cycle/days?from=2026-01-01&to=2026-13-45')).statusCode).toBe(400);
    // A backwards range can only be a mistake.
    expect((await get('/cycle/days?from=2026-07-31&to=2026-07-01')).statusCode).toBe(400);
  });

  it('alerts: record enter/exit → list newest-first', async () => {
    await post('/alerts', { childId: CHILD, kind: 'left', zoneName: 'Home', at: '2026-07-16T09:00:00Z' });
    await post('/alerts', { childId: CHILD, kind: 'entered', zoneName: 'School', at: '2026-07-16T09:05:00Z' });
    const alerts = (await get('/alerts')).json().alerts;
    expect(alerts).toHaveLength(2);
    expect(alerts[0].kind).toBe('entered');
    expect(alerts[0].zoneName).toBe('School');
    expect((await post('/alerts', { childId: CHILD, kind: 'teleported', zoneName: 'X', at: '2026-07-16T09:05:00Z' })).statusCode).toBe(400);
  });

  it('401 when unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/sleep' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'POST', url: '/alerts', payload: {} })).statusCode).toBe(401);
  });
});

describe('profile + device reassignment routes (in-process)', () => {
  it('profile: 404 until set, then PUT upsert → GET', async () => {
    expect((await get('/profile')).statusCode).toBe(404);
    const put = await app.inject({
      method: 'PUT', url: '/profile',
      payload: {
        displayName: 'Aigerim', phone: '+77001112233', dueDate: '2026-12-01', locale: 'ru-KZ',
        doctorPhone: '+77007654321', avgCycleLength: 30, avgPeriodLength: 6,
      },
    });
    expect(put.statusCode).toBe(200);
    const p = (await get('/profile')).json().profile;
    expect(p.displayName).toBe('Aigerim');
    expect(p.dueDate).toBe('2026-12-01');
    // The `phone` above is ignored, deliberately: it is the sign-in identity,
    // and accepting it let a user claim somebody else's account. Sending one
    // is not an error (older apps still do), it just does nothing.
    // See profileIdentity.test.ts.
    expect(p.phone, 'PUT /profile must not set the sign-in number').toBeNull();
    // The emergency contact + cycle baselines round-trip so they survive a device change.
    expect(p.doctorPhone).toBe('+77007654321');
    expect(p.avgCycleLength).toBe(30);
    expect(p.avgPeriodLength).toBe(6);
  });

  it('profile: rejects an out-of-range cycle baseline (zod 400)', async () => {
    const r = await app.inject({ method: 'PUT', url: '/profile',
      payload: { displayName: 'A', avgCycleLength: 400 } });
    expect(r.statusCode).toBe(400);
  });

  it('profile: rejects empty name + malformed due date (zod 400)', async () => {
    expect((await app.inject({ method: 'PUT', url: '/profile', payload: { displayName: '' } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PUT', url: '/profile', payload: { displayName: 'A', dueDate: '12/01/2026' } })).statusCode).toBe(400);
  });

  it('reassign a tracker tag to another child (PATCH), then unlink', async () => {
    await post('/devices', { id: 'TAG-1', name: 'Tag', kind: 'tag', childId: CHILD });
    const find = async () => (await get('/devices')).json().devices.find((x: { id: string }) => x.id === 'TAG-1');
    expect((await find()).childId).toBe(CHILD);

    // Reassign to a second child the SAME user owns. Reassignment now checks
    // both ends, so an arbitrary child id is correctly refused (see
    // authorization.test.ts) — this test needs a real sibling.
    const other = '88888888-8888-8888-8888-888888888888';
    await post('/children', { id: other, name: 'Aida' });
    expect((await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: { childId: other } })).statusCode).toBe(200);
    expect((await find()).childId).toBe(other);

    await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: { childId: null } });
    expect((await find()).childId).toBeNull();
    // childId is required in the body
    expect((await app.inject({ method: 'PATCH', url: '/devices/TAG-1', payload: {} })).statusCode).toBe(400);
  });

  it('401 when unauthenticated', async () => {
    const anon = makeDeps(async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/profile' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'PUT', url: '/profile', payload: { displayName: 'X' } })).statusCode).toBe(401);
  });
});

describe('admin API (in-process, RBAC + audit)', () => {
  it('stats returns KPIs to staff', async () => {
    const r = await get('/admin/stats');
    expect(r.statusCode).toBe(200);
    expect(r.json()).toHaveProperty('activeUsers');
    expect(r.json()).toHaveProperty('alertsToday');
  });

  it('emergency feed returns events and writes an audit entry', async () => {
    const r = await get('/admin/emergencies');
    expect(r.statusCode).toBe(200);
    // The fixture's reading is 162/108, which is the SEVERE branch — the code
    // now comes out of assessTelemetry rather than being typed here, so it says
    // which one. It used to be a hand-written 'PREECLAMPSIA_BP' next to a
    // production repository answering the literal 'EMERGENCY': the fake and the
    // thing it stood for disagreed, and this assertion checked the fake.
    expect(r.json().emergencies[0].code).toBe('PREECLAMPSIA_BP_SEVERE');
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string }) => a.action === 'view_emergencies')).toBe(true);
  });

  // `/detail`, not the deleted `/admin/users/:id/health` (docs/BACKLOG.md §3):
  // it returns the same `latest` from the same `adminUserHealth`, under the
  // same capability and reason gate, and it is the read the panel makes.
  it('patient health view is audited; unknown user 404', async () => {
    const r = await get(`/admin/users/${USER}/detail${WHY}`);
    expect(r.statusCode).toBe(200);
    expect(r.json().latest.systolic).toBe(138);
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string; target: string }) => a.action === 'view_user_detail' && a.target === USER)).toBe(true);
    expect((await get(`/admin/users/00000000-0000-0000-0000-000000000000/detail${WHY}`)).statusCode).toBe(404);
  });

  it('a clinician reaches patients and not the audit log', async () => {
    const clinician = makeDeps(undefined, async () => ({ staffId: 'c1', role: 'clinician' })).server;
    await clinician.ready();
    // The audit log is who-looked-at-whom, including at her. `staff`, not
    // `health` — being able to read records is not being able to read the
    // record of everyone else reading them.
    expect((await clinician.inject({ method: 'GET', url: '/admin/audit' })).statusCode).toBe(403);
    // Money is not hers either.
    expect((await clinician.inject({ method: 'GET', url: '/admin/dashboard' })).statusCode).toBe(403);
    // The user list WAS 403 here, which made the health view unusable: you
    // cannot open a patient's record without first finding the patient.
    expect((await clinician.inject({ method: 'GET', url: '/admin/users' })).statusCode).toBe(200);
    expect((await clinician.inject({ method: 'GET', url: '/admin/stats' })).statusCode).toBe(200);
  });

  it('admin can list users', async () => {
    const r = await get('/admin/users');
    expect(r.statusCode).toBe(200);
    expect(r.json().total).toBe(1);
    expect(r.json().users[0].displayName).toBe('Aigerim');
  });

  it('401 when staff is unauthenticated', async () => {
    const anon = makeDeps(undefined, async () => null).server;
    await anon.ready();
    expect((await anon.inject({ method: 'GET', url: '/admin/stats' })).statusCode).toBe(401);
  });

  it('patient wellness (sleep/cycle/alerts) is staff-viewable + audited', async () => {
    // Seed the target user's data via the client API (same USER in tests).
    await post('/sleep', { night: '2026-07-15', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25 });
    await app.inject({ method: 'PUT', url: '/cycle/days', payload: { date: '2026-07-15', mood: 'calm', symptoms: [], kicks: 2 } });
    await post('/alerts', { childId: CHILD, kind: 'entered', zoneName: 'School', at: '2026-07-16T09:00:00Z' });

    const r = await get(`/admin/users/${USER}/wellness${WHY}`);
    expect(r.statusCode).toBe(200);
    expect(r.json().sleep[0].deepMin).toBe(95);
    expect(r.json().days[0].mood).toBe('calm');
    expect(r.json().alerts[0].zoneName).toBe('School');
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string; target: string }) => a.action === 'view_wellness' && a.target === USER)).toBe(true);
  });

  it('a clinician can view wellness but not the audit log', async () => {
    const clinician = makeDeps(undefined, async () => ({ staffId: 'c1', role: 'clinician' as const })).server;
    await clinician.ready();
    expect((await clinician.inject({ method: 'GET', url: `/admin/users/${USER}/wellness${WHY}` })).statusCode).toBe(200);
    expect((await clinician.inject({ method: 'GET', url: '/admin/audit' })).statusCode).toBe(403);
  });
});
