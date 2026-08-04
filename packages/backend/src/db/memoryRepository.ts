/**
 * In-memory Repository — lets the backend boot and serve real requests WITHOUT a
 * Postgres/Timescale/PostGIS stack, for local dev and demos on test data.
 * Selected in index.ts when USE_MEMORY_DB=true (or no DATABASE_URL). Not for
 * production: state lives in process memory and is lost on restart.
 */

import { randomBytes, randomUUID, scryptSync } from 'node:crypto';
import type { ContentItemRow, Repository, StaffAccount, SleepNight, CryRow, WeightRow, KickSessionRow, ContractionSessionRow, MedicalIdRow, NewbornEventRow, GrowthRow, DoseRow, DayLogRow, SafetyAlertRow, ProfileRow, ShopOrderStatus, ShopLeadLocale, ShopLeadStatus } from './repository';
import { bundleDiscountMinor } from './repository';
import type { BpCalibration, ChildLocationFix, Geofence, GeofenceEvent } from '@fcs/shared';
import { computeBiMetrics } from '../analytics/biMetrics.js';
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
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null }> = [];
  const geofences = new Map<string, Geofence[]>([[DEMO_CHILD, [home]]]);
  const appointments: Array<{ id: string; title: string; at: string; note: string; userId: string }> = [];
  const medications: Array<{ id: string; name: string; dose: string; perDay: number; userId: string }> = [];
  const events: GeofenceEvent[] = [];
  /** Latest fix per child — what lastLocation reads back. */
  const locations = new Map<string, ChildLocationFix>();

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
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
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
  const shopProds = [
    { id: 'watch', name: 'Смарт-часы Umay', priceMinor: 2490000, sort: 1 },
    { id: 'tracker', name: 'Детский трекер Umay', priceMinor: 490000, sort: 2 },
  ];
  const shopVars: Array<{ id: string; productId: string; color: string; colorHex: string; stock: number; sort: number }> = [
    { id: 'v-w-black', productId: 'watch', color: 'Чёрный', colorHex: '#1C1E2A', stock: 0, sort: 1 },
    { id: 'v-w-rose', productId: 'watch', color: 'Розовое золото', colorHex: '#E8B4A0', stock: 0, sort: 2 },
    { id: 'v-w-violet', productId: 'watch', color: 'Сиреневый', colorHex: '#B9A8F0', stock: 0, sort: 3 },
    { id: 'v-t-teal', productId: 'tracker', color: 'Бирюзовый', colorHex: '#12B3A6', stock: 0, sort: 1 },
    { id: 'v-t-blue', productId: 'tracker', color: 'Синий', colorHex: '#3B82F6', stock: 0, sort: 2 },
    { id: 'v-t-pink', productId: 'tracker', color: 'Розовый', colorHex: '#E85C8A', stock: 0, sort: 3 },
  ];
  type ShopOrderRow = { id: string; customerName: string; phone: string; city: string; address: string; note: string | null; totalMinor: number; discountMinor: number; status: string; createdAt: string; items: Array<{ productName: string; color: string; qty: number; unitPriceMinor: number }> };
  const shopOrders: ShopOrderRow[] = [];
  type ShopLeadRow = { id: string; customerName: string; phone: string; package: string; locale: ShopLeadLocale; status: ShopLeadStatus; createdAt: string };
  const shopLeads: ShopLeadRow[] = [];
  type AudioRow = { track: string; day: number; locale: string; title: string | null; mime: string; bytes: Buffer; updatedAt: string };
  const dailyAudio = new Map<string, AudioRow>(); // key: `${track}|${day}|${locale}`
  const shopSettings = new Map<string, string>();

  return {
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
    insertLocation: async (fix) => void locations.set(fix.childId, fix),
    lastLocation: async (childId) => locations.get(childId) ?? null,
    // Push / AI / emergency
    guardianPushTokens: async () => ({ tokens: [], childName: children[0]?.name ?? '', locale: profile?.locale ?? null }),
    guardianPushTokensForUser: async () => ({ tokens: [], locale: profile?.locale ?? null }),
    deletePushToken: async () => {},
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Ambulance', tel: '103' }],
    deviceOwner: async (id) => (devices.some((d) => d.id === id) ? { userId: DEMO_USER } : null),
    // The in-memory store is single-tenant, so anything that exists belongs to
    // the demo user — but the checks still have to run, or the routes would be
    // exercised unguarded in every test that uses this repository.
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
    listDevices: async () => devices.map((d) => ({ ...d })),
    createDevice: async (_u, d) => void devices.push({ ...d, childId: d.childId ?? null }),
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
    recordAlert: async (_u, a) => void alerts.unshift(a),
    listAlerts: async (_u, limit) => alerts.slice(0, limit),
    // Profile + device reassignment
    getProfile: async () => (profile ? { ...profile } : null),
    upsertProfile: async (_u, p) => void (profile = { ...p }),
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
          displayName: profile?.displayName ?? 'Umay user',
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
        userId: DEMO_USER,
        displayName: profile?.displayName ?? '',
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
        stageDistribution: {},
        contentStages: content.size,
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

    writeAudit: async (e) => void audit.push({ ...e, target: e.target ?? null, at: new Date().toISOString() }),
    listAudit: async (limit) => audit.slice(-limit).reverse(),

    // ---- Shop ----
    shopProducts: async () => shopProds
      .sort((a, b) => a.sort - b.sort)
      .map((p) => ({
        id: p.id, name: p.name, priceMinor: p.priceMinor,
        variants: shopVars.filter((v) => v.productId === p.id).sort((a, b) => a.sort - b.sort)
          .map((v) => ({ id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock })),
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
      const discount = bundleDiscountMinor(lines);
      const total = subtotal - discount;
      for (const s of snap) s.variant.stock -= s.qty;
      const id = randomUUID();
      shopOrders.push({
        id, customerName: o.customerName, phone: o.phone, city: o.city, address: o.address,
        note: o.note ?? null, totalMinor: total, discountMinor: discount, status: 'new', createdAt: new Date().toISOString(),
        items: snap.map((s) => ({ productName: s.productName, color: s.color, qty: s.qty, unitPriceMinor: s.unitPriceMinor })),
      });
      return { ok: true as const, id, totalMinor: total, discountMinor: discount };
    },
    adminShopVariants: async () => shopVars.map((v) => ({
      id: v.id, color: v.color, colorHex: v.colorHex, stock: v.stock,
      productId: v.productId, productName: shopProds.find((p) => p.id === v.productId)?.name ?? v.productId,
    })),
    setShopVariantStock: async (variantId, stock) => {
      const v = shopVars.find((x) => x.id === variantId);
      if (v) v.stock = Math.max(0, Math.trunc(stock));
    },
    addShopVariant: async (productId, color, colorHex, stock) => {
      const existing = shopVars.find((v) => v.productId === productId && v.color === color);
      if (existing) { existing.colorHex = colorHex; existing.stock = Math.max(0, Math.trunc(stock)); return; }
      shopVars.push({ id: randomUUID(), productId, color, colorHex, stock: Math.max(0, Math.trunc(stock)), sort: shopVars.length });
    },
    adminShopOrders: async (limit) => shopOrders.slice(-limit).reverse().map((o) => ({ ...o, status: o.status as ShopOrderStatus })),
    setShopOrderStatus: async (orderId, status) => {
      const o = shopOrders.find((x) => x.id === orderId);
      if (o) o.status = status;
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
}
