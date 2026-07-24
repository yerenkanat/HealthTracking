/**
 * In-memory Repository — lets the backend boot and serve real requests WITHOUT a
 * Postgres/Timescale/PostGIS stack, for local dev and demos on test data.
 * Selected in index.ts when USE_MEMORY_DB=true (or no DATABASE_URL). Not for
 * production: state lives in process memory and is lost on restart.
 */

import { randomUUID } from 'node:crypto';
import type { ContentItemRow, Repository, SleepNight, WeightRow, KickSessionRow, ContractionSessionRow, MedicalIdRow, NewbornEventRow, GrowthRow, DoseRow, DayLogRow, SafetyAlertRow, ProfileRow } from './repository';
import type { BpCalibration, Geofence, GeofenceEvent } from '@fcs/shared';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { computeChildrenStats } from '../analytics/childStats.js';
import { buildSyntheticPopulation } from '../analytics/syntheticPopulation.js';

export const DEMO_USER = '11111111-1111-1111-1111-111111111111';
export const DEMO_CHILD = '33333333-3333-3333-3333-333333333333';

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
  const healthRows: unknown[] = [];
  // Emergency acknowledgements, keyed by the derived emergency id. An overlay —
  // the emergencies themselves are still derived from the health rows, so
  // acknowledging one needs no change to the ingest/triage path.
  const emergencyAcks = new Map<string, { staffId: string; at: string }>();
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
  const sleep: SleepNight[] = [];
  const weights: WeightRow[] = [];
  const kickSessions: KickSessionRow[] = [];
  const contractionSessions: ContractionSessionRow[] = [];
  const childEmergency = new Map<string, MedicalIdRow>();
  const newbornEvents = new Map<string, NewbornEventRow[]>();
  const growth = new Map<string, GrowthRow[]>();
  const doses: Array<DoseRow & { userId: string }> = [];
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

  return {
    // Health
    insertHealthMetric: async (m) => void healthRows.push(m),
    insertBpCalibration: async (userId, cal) => void bpCalibrations.push({ ...cal, userId }),
    latestBpCalibration: async (userId) => {
      const mine = bpCalibrations.filter((c) => c.userId === userId);
      if (!mine.length) return null;
      // Newest by calibratedAt — the same "latest wins" the pg ORDER BY gives.
      const latest = mine.reduce((a, b) => (a.calibratedAt >= b.calibratedAt ? a : b));
      const { userId: _omit, ...row } = latest;
      return row;
    },
    // Child / geofence
    loadGeofences: async (childId) => geofences.get(childId) ?? [],
    insertGeofenceEvent: async (e) => void events.push(e),
    insertLocation: async () => {},
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
    adminListUsers: async () => ({
      total: 1,
      users: [{ id: DEMO_USER, displayName: profile?.displayName ?? '', phone: profile?.phone ?? null, dueDate: profile?.dueDate ?? null }],
    }),
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
        return { latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 }, triage: [] };
      }
      const num = (v: unknown) => (typeof v === 'number' ? v : null);
      return {
        latest: {
          hr: num(last.heartRateBpm),
          spo2: num(last.spo2Pct),
          systolic: num(last.systolicMmHg),
          diastolic: num(last.diastolicMmHg),
          temp: num(last.coreTempC),
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
        children: children.map((c) => ({
          id: c.id,
          name: c.name,
          dateOfBirth: null,
          zones: (geofences.get(c.id) ?? []).length,
        })),
        devices: devices.map((d) => ({
          id: d.id,
          name: d.name,
          kind: d.kind,
          childId: d.childId,
          batteryPct: batteryByDevice.get(d.id) ?? null,
        })),
        latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 },
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
      sleep.length = 0;
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
  };
}
