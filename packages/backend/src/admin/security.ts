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

/** Audit actions that touch health or a child's whereabouts. */
export const PROTECTED_ACTIONS: Readonly<Record<string, 'health' | 'location'>> = {
  view_health: 'health',
  view_wellness: 'health',
  view_user_detail: 'health',
  view_children_stats: 'health',
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
