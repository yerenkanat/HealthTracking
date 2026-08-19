/**
 * Frame 22 — «Безопасность».
 *
 * docs/CLAUDE-admin-design.md: «метрики просмотров защищённых данных → журнал
 * доступа с основанием → кто что видит → хранение → открытый вопрос.»
 *
 * Every piece of this already existed and none of it was on a screen: the audit
 * log records who opened whose record and why, the capability matrix decides
 * who can, and the retention sweep deletes routes at 90 days. What was missing
 * was the one page that lets somebody ASK whether any of it is being abused.
 *
 * The metric that matters is not the total. It is how many of those reads were
 * of SPECIAL-CATEGORY data — health, and a child's location — because that is
 * the number a regulator asks for and the number that should be small.
 *
 * PURE: audit rows in, summary out. No repository, no clock beyond the instant
 * it is given.
 */

import { RETENTION_KEPT, RETENTION_SWEEPS } from '../privacy/retention';

/** Audit actions that touch health or a child's whereabouts. */
export const PROTECTED_ACTIONS: Readonly<Record<string, 'health' | 'location'>> = {
  view_health: 'health',
  view_wellness: 'health',
  view_user_detail: 'health',
  view_children_stats: 'health',
  // How much she moved, how she slept and how stressed the watch thinks she
  // was, for a NAMED woman — special-category data, guarded by `health` and
  // gated on a reason exactly like /wellness (routes/admin.ts). It was written
  // to the log and counted by nothing: fifty opens of her heart rate, SpO2,
  // blood pressure, stress and breathing left this page reporting zero, her
  // name never appeared in `recent`, and `withoutReason` — the number this
  // page exists to make non-zero — structurally could not see the route.
  view_wearable: 'health',
  // A child's position and the fleet list that carries her name beside it.
  view_safety_feed: 'location',
  view_devices: 'location',
  view_device_registry: 'location',
};

export interface AuditRow {
  staffId: string;
  staffName: string | null;
  action: string;
  target: string | null;
  targetName: string | null;
  reason: string | null;
  at: string;
}

export interface SecuritySummary {
  /** Protected reads in the window. */
  protectedReads: number;
  /** Of those, how many were health as opposed to location. */
  health: number;
  location: number;
  /**
   * Protected reads with NO recorded reason.
   *
   * Should be zero for anything written after the reason became mandatory.
   * A number here is either a row from before that, or a route that reached
   * protected data without going through `readReason` — which is the exact
   * hole this page exists to make visible.
   */
  withoutReason: number;
  /** Who looked, most active first. Names the person, not just the id. */
  byStaff: Array<{ staffId: string; staffName: string | null; reads: number }>;
  /** The reads themselves, newest first. */
  recent: AuditRow[];
  /** How many days the window covered. */
  windowDays: number;
}

export function summarizeSecurity(
  audit: AuditRow[],
  now: Date,
  windowDays = 30,
): SecuritySummary {
  const since = now.getTime() - windowDays * 86_400_000;
  const rows = audit.filter((a) => {
    if (!(a.action in PROTECTED_ACTIONS)) return false;
    const t = Date.parse(a.at);
    return Number.isFinite(t) && t >= since;
  });

  const byStaff = new Map<string, { staffId: string; staffName: string | null; reads: number }>();
  let health = 0;
  let location = 0;
  let withoutReason = 0;

  for (const r of rows) {
    if (PROTECTED_ACTIONS[r.action] === 'health') health++;
    else location++;
    // Empty string counts as missing: a reason of '' is not a reason, and
    // treating it as one is how the number that should be zero stays zero.
    if (!r.reason || !r.reason.trim()) withoutReason++;

    const seen = byStaff.get(r.staffId);
    if (seen) seen.reads++;
    else byStaff.set(r.staffId, { staffId: r.staffId, staffName: r.staffName, reads: 1 });
  }

  return {
    protectedReads: rows.length,
    health,
    location,
    withoutReason,
    byStaff: [...byStaff.values()].sort((a, b) => b.reads - a.reads),
    // Newest first — the log is read from the top when somebody is checking
    // something that just happened.
    recent: [...rows].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, 100),
    windowDays,
  };
}

// ---------------------------------------------------------------------------
// «Хранение» — the second half of frame 22.
// ---------------------------------------------------------------------------

/** One swept table, as the card prints it. */
export interface RetentionSweptLine {
  /** The table, so a claim on this screen can be checked against the schema. */
  table: string;
  /** What it is, for somebody who has never seen the schema. */
  label: string;
  /** Why it is that period, in the words of the decision. */
  why: string;
  /** The period the sweep actually uses. Days, because that is the cutoff. */
  days: number;
}

/** One table deliberately not swept. */
export interface RetentionKeptLine {
  table: string;
  label: string;
  why: string;
}

export interface RetentionReport {
  /**
   * The route promise, kept as its own field because it is the one this
   * product printed to every user before any of the rest existed.
   *
   * Derived, not typed: null if location_history ever leaves the schedule,
   * so the card says «срок не задан» instead of quoting a period nothing
   * enforces. That failure has already happened once here, with the audit log.
   */
  routeDays: number | null;
  /** The audit period in YEARS, or null when audit_log is off the schedule. */
  auditSweep: number | null;
  /** Every sweep that runs. One line per entry in RETENTION_SWEEPS. */
  swept: RetentionSweptLine[];
  /** What is kept on purpose, so an absence reads as a decision. */
  kept: RetentionKeptLine[];
}

/** The period a table is swept on, or null when nothing sweeps it. */
function sweptDays(table: string): number | null {
  return RETENTION_SWEEPS.find((s) => s.table === table)?.days ?? null;
}

/**
 * What this product deletes, and what it keeps — derived, never listed.
 *
 * The card reported exactly two of eight enforced periods: the route sweep and
 * the audit sweep, each named in the route by hand. Six were invisible —
 * geofence crossings, safety alerts, phone codes, login attempts, shop leads,
 * support threads — and this is the page somebody opens to answer «what does
 * this product keep, and for how long». A page listing two of eight does not
 * read as incomplete; it reads as the whole answer.
 *
 * So nothing here names a table except to pull the two legacy fields out of the
 * schedule by name. A ninth sweep appears on the panel by being added to
 * RETENTION_SWEEPS, with no edit to this function, to the route, or to the
 * panel's HTML — which is the only arrangement under which the card stays true
 * without somebody remembering to make it so.
 */
export function retentionSummary(): RetentionReport {
  const auditDays = sweptDays('audit_log');
  return {
    routeDays: sweptDays('location_history'),
    // Years, because that is the unit the decision was made in and the unit the
    // card has always printed. AUDIT_RETENTION_DAYS is AUDIT_RETENTION_YEARS
    // × 365 by construction (privacy/retention.ts), so this division is exact
    // and cannot invent a period the sweep does not use.
    auditSweep: auditDays == null ? null : Math.round(auditDays / 365),
    swept: RETENTION_SWEEPS.map((s) => ({
      table: s.table,
      label: s.labelRu,
      why: s.whyRu,
      days: s.days,
    })),
    kept: RETENTION_KEPT.map((k) => ({
      table: k.table,
      label: k.labelRu,
      why: k.whyRu,
    })),
  };
}
