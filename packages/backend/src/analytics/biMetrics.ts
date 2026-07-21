/**
 * Product metrics for the admin overview: DAU/WAU/MAU, growth, retention and
 * engagement.
 *
 * Pure on purpose. The Postgres repository computes these in SQL and the
 * in-memory one computes them here, and two implementations of "what does
 * retention mean" WILL drift — the version that drifts silently is the one
 * nobody can test. So the definitions live here, in one place, with
 * biMetrics.test.ts pinning each one to a worked example.
 *
 * Every window is bucketed by UTC day. Not a detail: bucketing by server-local
 * day makes DAU jump or drop by an hour's worth of users twice a year in any
 * region that observes DST, which reads as a product event rather than a
 * clock change.
 */

export type BiEventKind = 'telemetry' | 'location' | 'alert' | 'sos' | 'chat' | 'emergency';

export interface BiUser {
  id: string;
  /** ISO timestamp of signup. */
  createdAt: string;
}

export interface BiEvent {
  userId: string;
  /** ISO timestamp. */
  at: string;
  kind: BiEventKind;
}

export interface BiPoint {
  date: string; // YYYY-MM-DD (UTC)
  value: number;
}

/**
 * A retention figure and the cohort it came from.
 *
 * The cohort size travels with the rate deliberately: "100% D30 retention" off
 * a cohort of 2 is noise, and a dashboard that shows only the percentage
 * invites someone to act on it.
 */
export interface BiRetention {
  rate: number; // 0..1
  cohort: number;
}

/**
 * Growth accounting: where this month's actives came from, and what it cost.
 *
 * new + resurrected + returning is exactly the current period's active count,
 * and churned is the users the previous period had and this one does not.
 * `net` is the change in actives between the two periods. Reported together
 * because a flat MAU can be a stable base or heavy churn masked by heavy
 * acquisition, and those need opposite responses.
 */
export interface BiGrowthAccounting {
  /** Signed up during the period and active in it. */
  new: number;
  /** Active in both this period and the previous one. */
  returning: number;
  /** Active now, silent through the whole previous period, not new. */
  resurrected: number;
  /** Active in the previous period and not in this one. */
  churned: number;
  /** Actives this period minus actives last period. */
  net: number;
  /** churned / previous period's actives. */
  churnRate: number;
  /** Days in each period. */
  periodDays: number;
}

/**
 * How far each module reaches into the active base.
 *
 * Counts of USERS, not events. The event mix is dominated by telemetry, which
 * arrives on a timer — it says which module is noisiest, not which is used.
 */
export interface BiAdoption {
  /** Users active in the last 30 days who produced at least one such event. */
  users: number;
  /** users / mau. */
  share: number;
}

/**
 * Signup → first action → habit → still here. Each stage is a subset of the
 * one before it, so the drop between two adjacent stages is where users are
 * actually lost.
 */
export interface BiFunnelStage {
  key: string;
  users: number;
  /** Share of the stage above — the conversion actually being measured. */
  ofPrevious: number;
  /** Share of the whole cohort, for reading the funnel end to end. */
  ofCohort: number;
}

export interface BiMetrics {
  asOf: string;
  totalUsers: number;
  dau: number;
  wau: number;
  mau: number;
  /** DAU/MAU. The share of monthly users who show up on a given day. */
  stickiness: number;
  /** MAU/total. How much of the registered base is still here. */
  activeRate: number;
  dauSeries: BiPoint[];
  /** Rolling 7-day actives, one point per day. Smooths the weekday sawtooth. */
  wauSeries: BiPoint[];
  signupSeries: BiPoint[];
  newUsers: { today: number; d7: number; d30: number };
  retention: { d1: BiRetention; d7: BiRetention; d30: BiRetention };
  /** Day 0..30 retention, for the curve. Day 0 is the signup day itself. */
  retentionCurve: (BiRetention & { day: number })[];
  growth: BiGrowthAccounting;
  /** Reach of each module across the active base, keyed by event kind. */
  adoption: Record<BiEventKind, BiAdoption>;
  funnel: BiFunnelStage[];
  engagement: {
    eventsPerActiveUser: number;
    activeDaysPerUser: number;
    eventMix: Record<BiEventKind, number>;
  };
  safety: { alerts7d: number; sosAllTime: number; emergencies7d: number };
  devices: { total: number; online: number };
}

/** UTC day key. */
export function dayKey(d: Date): string {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(
    d.getUTCDate(),
  ).padStart(2, '0')}`;
}

/** Midnight UTC of the day [d] falls in. */
function startOfUtcDay(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function addDays(d: Date, n: number): Date {
  return new Date(d.getTime() + n * 86400000);
}

function round(n: number, places = 4): number {
  const f = 10 ** places;
  return Math.round(n * f) / f;
}

function safeDiv(a: number, b: number): number {
  return b === 0 ? 0 : round(a / b);
}

export interface BiInput {
  users: BiUser[];
  events: BiEvent[];
  devices: { total: number; online: number };
  now: Date;
  /** Length of the trend series, in days. */
  windowDays?: number;
}

export function computeBiMetrics(input: BiInput): BiMetrics {
  const { users, events, devices, now } = input;
  const windowDays = input.windowDays ?? 30;
  const today = startOfUtcDay(now);
  const todayKey = dayKey(today);

  // userId → set of UTC days on which they did anything.
  const activeDays = new Map<string, Set<string>>();
  // day → set of userIds, for the DAU series.
  const usersByDay = new Map<string, Set<string>>();
  const known = new Set(users.map((u) => u.id));

  for (const e of events) {
    const at = new Date(e.at);
    if (Number.isNaN(at.getTime())) continue;
    // An event from a user we have no signup record for cannot be placed in a
    // cohort, and counting it in DAU while excluding it from retention would
    // make the two disagree on the same screen.
    if (!known.has(e.userId)) continue;
    const k = dayKey(at);
    let days = activeDays.get(e.userId);
    if (!days) activeDays.set(e.userId, (days = new Set()));
    days.add(k);
    let set = usersByDay.get(k);
    if (!set) usersByDay.set(k, (set = new Set()));
    set.add(e.userId);
  }

  const activeSince = (days: number): number => {
    const from = addDays(today, -(days - 1));
    const seen = new Set<string>();
    for (const [k, set] of usersByDay) {
      const d = new Date(`${k}T00:00:00Z`);
      if (d >= from && d <= today) for (const u of set) seen.add(u);
    }
    return seen.size;
  };

  const dau = usersByDay.get(todayKey)?.size ?? 0;
  const wau = activeSince(7);
  const mau = activeSince(30);

  const dauSeries: BiPoint[] = [];
  for (let i = windowDays - 1; i >= 0; i--) {
    const k = dayKey(addDays(today, -i));
    dauSeries.push({ date: k, value: usersByDay.get(k)?.size ?? 0 });
  }

  // ---- growth ----
  const signupsByDay = new Map<string, number>();
  for (const u of users) {
    const at = new Date(u.createdAt);
    if (Number.isNaN(at.getTime())) continue;
    const k = dayKey(at);
    signupsByDay.set(k, (signupsByDay.get(k) ?? 0) + 1);
  }
  const signupSeries: BiPoint[] = [];
  for (let i = windowDays - 1; i >= 0; i--) {
    const k = dayKey(addDays(today, -i));
    signupSeries.push({ date: k, value: signupsByDay.get(k) ?? 0 });
  }
  const signupsWithin = (days: number): number => {
    const from = addDays(today, -(days - 1));
    let n = 0;
    for (const u of users) {
      const at = new Date(u.createdAt);
      if (Number.isNaN(at.getTime())) continue;
      const d = startOfUtcDay(at);
      if (d >= from && d <= today) n++;
    }
    return n;
  };

  // ---- retention ----
  // Day-N retention: of the users whose day N has already arrived, the share
  // who were active on exactly that day. Aggregated across every eligible
  // cohort rather than a single day's, so one quiet Tuesday does not read as
  // a collapse.
  const retentionAt = (n: number): BiRetention => {
    let cohort = 0;
    let retained = 0;
    for (const u of users) {
      const at = new Date(u.createdAt);
      if (Number.isNaN(at.getTime())) continue;
      const target = addDays(startOfUtcDay(at), n);
      if (target > today) continue; // their day N has not happened yet
      cohort++;
      if (activeDays.get(u.id)?.has(dayKey(target))) retained++;
    }
    return { rate: safeDiv(retained, cohort), cohort };
  };

  // ---- engagement (last 30 days) ----
  const from30 = addDays(today, -29);
  const eventMix = {
    telemetry: 0,
    location: 0,
    alert: 0,
    sos: 0,
    chat: 0,
    emergency: 0,
  } as Record<BiEventKind, number>;
  let events30 = 0;
  for (const e of events) {
    const at = new Date(e.at);
    if (Number.isNaN(at.getTime()) || !known.has(e.userId)) continue;
    const d = startOfUtcDay(at);
    if (d < from30 || d > today) continue;
    events30++;
    if (e.kind in eventMix) eventMix[e.kind]++;
  }
  let activeDaySum = 0;
  for (const [, days] of activeDays) {
    for (const k of days) {
      const d = new Date(`${k}T00:00:00Z`);
      if (d >= from30 && d <= today) activeDaySum++;
    }
  }

  // ---- rolling 7-day actives ----
  // DAU alone has a weekday sawtooth big enough to hide a real trend; a
  // rolling week is what you actually read a direction off.
  const wauSeries: BiPoint[] = [];
  for (let i = windowDays - 1; i >= 0; i--) {
    const end = addDays(today, -i);
    const seen = new Set<string>();
    for (let j = 0; j < 7; j++) {
      for (const u of usersByDay.get(dayKey(addDays(end, -j))) ?? []) seen.add(u);
    }
    wauSeries.push({ date: dayKey(end), value: seen.size });
  }

  // ---- growth accounting ----
  // Where this period's actives came from. A flat MAU can be a stable base or
  // heavy churn hidden behind heavy acquisition; only this split tells them
  // apart, and they call for opposite responses.
  const growthOver = (periodDays: number): BiGrowthAccounting => {
    const curFrom = addDays(today, -(periodDays - 1));
    const prevFrom = addDays(curFrom, -periodDays);
    const prevTo = addDays(curFrom, -1);

    const inRange = (u: string, from: Date, to: Date): boolean => {
      const days = activeDays.get(u);
      if (!days) return false;
      for (const k of days) {
        const d = new Date(`${k}T00:00:00Z`);
        if (d >= from && d <= to) return true;
      }
      return false;
    };

    let isNew = 0;
    let returning = 0;
    let resurrected = 0;
    let churned = 0;
    let prevActive = 0;

    for (const u of users) {
      const cur = inRange(u.id, curFrom, today);
      const prev = inRange(u.id, prevFrom, prevTo);
      if (prev) prevActive++;
      if (cur && prev) returning++;
      else if (cur) {
        const at = new Date(u.createdAt);
        const signedUpInPeriod = !Number.isNaN(at.getTime()) && startOfUtcDay(at) >= curFrom;
        if (signedUpInPeriod) isNew++;
        else resurrected++;
      } else if (prev) churned++;
    }

    const curActive = isNew + returning + resurrected;
    return {
      new: isNew,
      returning,
      resurrected,
      churned,
      net: curActive - prevActive,
      churnRate: safeDiv(churned, prevActive),
      periodDays,
    };
  };

  // ---- module adoption ----
  // Counts of USERS per module, not events. The event mix is dominated by
  // telemetry, which arrives on a timer whether or not anyone opens the app —
  // it says which module is noisiest, not which one is used.
  const adoption = {} as Record<BiEventKind, BiAdoption>;
  {
    const byKind = new Map<BiEventKind, Set<string>>();
    for (const e of events) {
      const at = new Date(e.at);
      if (Number.isNaN(at.getTime()) || !known.has(e.userId)) continue;
      const d = startOfUtcDay(at);
      if (d < from30 || d > today) continue;
      let set = byKind.get(e.kind);
      if (!set) byKind.set(e.kind, (set = new Set()));
      set.add(e.userId);
    }
    for (const kind of Object.keys(eventMix) as BiEventKind[]) {
      const n = byKind.get(kind)?.size ?? 0;
      adoption[kind] = { users: n, share: safeDiv(n, mau) };
    }
  }

  // ---- activation funnel ----
  // Each stage is a subset of the one above, so the gap between two adjacent
  // stages is where users are actually lost. Restricted to accounts at least a
  // week old: a user who signed up this morning has not failed to form a habit,
  // and counting them as a drop-off makes every good acquisition day look like
  // a product regression.
  const funnel: BiFunnelStage[] = [];
  {
    const eligible = users.filter((u) => {
      const at = new Date(u.createdAt);
      return !Number.isNaN(at.getTime()) && addDays(startOfUtcDay(at), 7) <= today;
    });
    const last7From = addDays(today, -6);
    let activated = 0;
    let habit = 0;
    let retained = 0;
    for (const u of eligible) {
      const days = activeDays.get(u.id);
      if (!days || days.size === 0) continue;
      activated++;
      if (days.size >= 3) habit++;
      let recent = false;
      for (const k of days) {
        const d = new Date(`${k}T00:00:00Z`);
        if (d >= last7From && d <= today) recent = true;
      }
      if (recent) retained++;
    }
    const cohort = eligible.length;
    const stage = (key: string, n: number, prev: number): BiFunnelStage => ({
      key,
      users: n,
      ofPrevious: safeDiv(n, prev),
      ofCohort: safeDiv(n, cohort),
    });
    funnel.push(
      stage('signed_up', cohort, cohort),
      stage('activated', activated, cohort),
      stage('habit', habit, activated),
      stage('retained', retained, habit),
    );
  }

  // ---- safety ----
  const within7 = (kind: BiEventKind): number => {
    const from = addDays(today, -6);
    let n = 0;
    for (const e of events) {
      if (e.kind !== kind) continue;
      const at = new Date(e.at);
      if (Number.isNaN(at.getTime())) continue;
      const d = startOfUtcDay(at);
      if (d >= from && d <= today) n++;
    }
    return n;
  };

  return {
    asOf: todayKey,
    totalUsers: users.length,
    dau,
    wau,
    mau,
    stickiness: safeDiv(dau, mau),
    activeRate: safeDiv(mau, users.length),
    dauSeries,
    wauSeries,
    signupSeries,
    newUsers: { today: signupsByDay.get(todayKey) ?? 0, d7: signupsWithin(7), d30: signupsWithin(30) },
    retention: { d1: retentionAt(1), d7: retentionAt(7), d30: retentionAt(30) },
    retentionCurve: Array.from({ length: 31 }, (_, day) => ({ day, ...retentionAt(day) })),
    growth: growthOver(30),
    adoption,
    funnel,
    engagement: {
      eventsPerActiveUser: safeDiv(events30, mau),
      activeDaysPerUser: safeDiv(activeDaySum, mau),
      eventMix,
    },
    safety: {
      alerts7d: within7('alert'),
      sosAllTime: events.filter((e) => e.kind === 'sos').length,
      emergencies7d: within7('emergency'),
    },
    devices,
  };
}
