/**
 * In-memory Repository — lets the backend boot and serve real requests WITHOUT a
 * Postgres/Timescale/PostGIS stack, for local dev and demos on test data.
 * Selected in index.ts when USE_MEMORY_DB=true (or no DATABASE_URL). Not for
 * production: state lives in process memory and is lost on restart.
 */

import type { ContentItemRow, Repository, SleepNight, DayLogRow, SafetyAlertRow, ProfileRow } from './repository';
import type { Geofence, GeofenceEvent } from '@fcs/shared';

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

  const children: Array<{ id: string; name: string }> = [{ id: DEMO_CHILD, name: 'Sultan' }];
  const devices: Array<{ id: string; name: string; kind: string; childId: string | null }> = [];
  const geofences = new Map<string, Geofence[]>([[DEMO_CHILD, [home]]]);
  const events: GeofenceEvent[] = [];
  const healthRows: unknown[] = [];
  const audit: Array<{ staffId: string; action: string; target: string | null; at: string }> = [];
  const sleep: SleepNight[] = [];
  const dayLogs = new Map<string, DayLogRow>();
  const alerts: SafetyAlertRow[] = [];
  let profile: ProfileRow | null = { displayName: 'Aigerim', phone: '+77001112233', dueDate: null, locale: 'ru-KZ' };
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

  return {
    // Health
    insertHealthMetric: async (m) => void healthRows.push(m),
    insertBpCalibration: async () => {},
    // Child / geofence
    loadGeofences: async (childId) => geofences.get(childId) ?? [],
    insertGeofenceEvent: async (e) => void events.push(e),
    insertLocation: async () => {},
    // Push / AI / emergency
    guardianPushTokens: async () => ({ tokens: [], childName: children[0]?.name ?? '' }),
    guardianPushTokensForUser: async () => [],
    retrieveRagPassages: async () => [],
    emergencyContacts: async () => [{ label: 'Ambulance', tel: '103' }],
    deviceOwner: async (id) => (devices.some((d) => d.id === id) ? { userId: DEMO_USER } : null),
    // The in-memory store is single-tenant, so anything that exists belongs to
    // the demo user — but the checks still have to run, or the routes would be
    // exercised unguarded in every test that uses this repository.
    childOwner: async (id) => (children.some((c) => c.id === id) ? { userId: DEMO_USER } : null),
    geofenceOwner: async (id) =>
      [...geofences.values()].flat().some((g) => g.id === id) ? { userId: DEMO_USER } : null,
    // CRUD
    listChildren: async () => children.map((c) => ({ ...c })),
    createChild: async (_u, name) => {
      const c = { id: `child-${idSeq++}`, name };
      children.push(c);
      return c;
    },
    deleteChild: async (id) => {
      const i = children.findIndex((c) => c.id === id);
      if (i >= 0) children.splice(i, 1);
    },
    listDevices: async () => devices.map((d) => ({ ...d })),
    createDevice: async (_u, d) => void devices.push({ ...d, childId: d.childId ?? null }),
    deleteDevice: async (id) => {
      const i = devices.findIndex((d) => d.id === id);
      if (i >= 0) devices.splice(i, 1);
    },
    createGeofence: async (childId, g) => {
      const withId = { ...g, id: `gf-${idSeq++}` };
      geofences.set(childId, [...(geofences.get(childId) ?? []), withId]);
      return withId;
    },
    deleteGeofence: async (id) => {
      for (const [k, list] of geofences) geofences.set(k, list.filter((g) => g.id !== id));
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
    recentEmergencies: async () => [],
    adminListUsers: async () => ({
      total: 1,
      users: [{ id: DEMO_USER, displayName: profile?.displayName ?? '', phone: profile?.phone ?? null, dueDate: profile?.dueDate ?? null }],
    }),
    adminUserHealth: async () => ({ latest: { hr: 80, spo2: 97, systolic: 138, diastolic: 82, temp: 36.7 }, triage: [] }),

    adminUserDetail: async (userId) => {
      if (userId !== DEMO_USER) return null;
      return {
        id: DEMO_USER,
        displayName: profile?.displayName ?? '',
        phone: profile?.phone ?? null,
        dueDate: profile?.dueDate ?? null,
        locale: profile?.locale ?? null,
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
