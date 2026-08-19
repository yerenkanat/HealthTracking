/**
 * Deleting what we promised to delete.
 *
 * docs/CLAUDE-app-design.md §"Приватность": «Маршруты хранятся 90 дней.» The
 * app repeats it to every user in its privacy policy.
 *
 * db/schema.sql has carried the DELETE since the Timescale retention policy was
 * dropped — as a COMMENT, with a note to run it "as a scheduled job (pg_cron,
 * or an app cron)". Neither was ever set up, so every child's location trail has
 * been accumulating since the first fix: a minute-by-minute record of where a
 * named child has been for as long as the family has used the product, held
 * against an explicit promise not to.
 *
 * That was the whole of this file. It swept ONE table, and everything else
 * holding personal data was kept until the account was deleted — or for ever,
 * where it is keyed by a phone number rather than by user_id. The periods below
 * are the owner's decisions (docs/TODO.md §9.6), written down once and enforced
 * from here.
 *
 * It stays deliberately small and deliberately PURE about its arithmetic,
 * because the two ways a retention sweep goes wrong are both invisible in
 * production: it silently stops running, or it computes the wrong cutoff and
 * deletes a year instead of a quarter.
 *
 * NOTHING here deletes an accounting record. shop_orders / shop_order_items /
 * shop_order_events have no sweep on purpose — see RETENTION_KEPT below.
 */

// ---------------------------------------------------------------------------
// The periods. One place. Nothing else may guess, and no call site may hold a
// literal — the security panel and the published privacy policy both point at
// these constants rather than repeating the numbers.
// ---------------------------------------------------------------------------

/** The window the app promises for a child's trail, in days. */
export const ROUTE_RETENTION_DAYS = 90;

/**
 * A zone crossing is the same data as the route that produced it.
 *
 * Keeping the crossing longer than the trail it came from was never a decision,
 * just an omission: geofence_events records that a named child entered or left
 * a named place at a named minute, which is a coarse movement history under
 * another name.
 */
export const GEOFENCE_EVENT_RETENTION_DAYS = ROUTE_RETENTION_DAYS;

/**
 * Twelve months for safety_alerts, SOS rows included.
 *
 * Long enough that a parent can look back over a school year; short enough that
 * it is not a permanent movement history of a child. What is kept is the record
 * of the event, not of the child.
 */
export const SAFETY_ALERT_RETENTION_MONTHS = 12;
export const SAFETY_ALERT_RETENTION_DAYS = 365;

/**
 * Three years for audit_log — the accountability record.
 *
 * The panel claimed exactly this for months with nothing enforcing it, and was
 * corrected in b8aac0c to say «срок не задан» rather than keep printing a
 * fiction beside a real sweep. Three years is the right period for the evidence
 * that nobody read a mother's record unexplained, so the original claim is made
 * TRUE here rather than left disclaimed.
 *
 * YEARS is what the screen prints; DAYS is what the cutoff uses and is derived
 * from it, so the two cannot drift. 365-day years: the error against leap days
 * is under a day per sweep, and it errs towards deleting slightly early — the
 * direction that cannot leave a row behind past its stated period.
 */
export const AUDIT_RETENTION_YEARS = 3;
export const AUDIT_RETENTION_DAYS = AUDIT_RETENTION_YEARS * 365;

/**
 * Thirty days for phone_codes.
 *
 * A used code is deleted on use already; an ABANDONED one — a number that asked
 * for a code and never came back — lived for ever: a phone number beside a hash
 * in a table nobody reads. The phone_codes_expiry index exists and implies a
 * sweep nobody wrote. A live code expires in minutes, so thirty days can never
 * take one that is still usable.
 */
export const PHONE_CODE_RETENTION_DAYS = 30;

/**
 * Ninety days for user_login_attempts and staff_login_attempts.
 *
 * Rate-limiting reads minutes and intrusion review reads weeks; neither reads
 * years. Phone plus timestamp is personal data — it says which number tried to
 * get into this product, and when.
 */
export const LOGIN_ATTEMPT_RETENTION_DAYS = 90;

/**
 * Twelve months for shop_leads.
 *
 * A name and a phone number typed into the landing form. If nobody has acted on
 * it in a year, holding it is not a business need.
 */
export const SHOP_LEAD_RETENTION_DAYS = 365;

/**
 * Three years for support_tickets and the support_replies hanging off them —
 * the same period as the audit log.
 *
 * A dispute about an order can surface long after the order. Measured from the
 * LAST activity on the thread rather than from when it was opened: a
 * conversation that ran for two years must not lose its beginning while its end
 * is still live.
 */
export const SUPPORT_RETENTION_YEARS = 3;
export const SUPPORT_RETENTION_DAYS = SUPPORT_RETENTION_YEARS * 365;

/**
 * The instant before which a row must be gone.
 *
 * Takes `now` rather than reading the clock, so a boundary can be exercised at
 * exactly the period rather than approximately.
 */
export function retentionCutoff(now: Date, days = ROUTE_RETENTION_DAYS): string {
  return new Date(now.getTime() - days * 86_400_000).toISOString();
}

export interface RetentionResult {
  /** Which table this run swept, so a log line names it. */
  table: string;
  /** Rows deleted this run. */
  removed: number;
  /** The cutoff used, so a log line can be checked rather than trusted. */
  cutoff: string;
  /** Set when the sweep failed; the caller decides whether that is fatal. */
  error?: string;
}

/**
 * The delete side of the repository, and nothing else.
 *
 * Every method takes a cutoff rather than computing one. A retention window
 * that reads the clock cannot be tested against a fixed set of rows, and a
 * period is exactly the kind of number that has to be exercised at its
 * boundary — one day out is a promise broken by a day.
 */
export interface RetentionDeps {
  pruneLocationHistory(cutoffIso: string): Promise<number>;
  pruneGeofenceEvents(cutoffIso: string): Promise<number>;
  pruneSafetyAlerts(cutoffIso: string): Promise<number>;
  pruneAuditLog(cutoffIso: string): Promise<number>;
  prunePhoneCodes(cutoffIso: string): Promise<number>;
  pruneLoginAttempts(cutoffIso: string): Promise<number>;
  pruneShopLeads(cutoffIso: string): Promise<number>;
  pruneSupportTickets(cutoffIso: string): Promise<number>;
}

/** One period, the table it applies to, and why it is that number. */
export interface RetentionSweep {
  /** The table, named as db/schema.sql names it. */
  table: string;
  /** The period in days. Always a constant from above, never a literal. */
  days: number;
  /** The decision in one line, so a reader here need not go and find it. */
  why: string;
  run(repo: RetentionDeps, cutoffIso: string): Promise<number>;
}

/**
 * Every sweep this product runs. New personal data means a new line here.
 *
 * Each entry is independent: one failing does not stop the next, because the
 * first thing a sick database does is break whichever table happens to be
 * first in the list.
 */
export const RETENTION_SWEEPS: readonly RetentionSweep[] = [
  {
    table: 'location_history',
    days: ROUTE_RETENTION_DAYS,
    why: 'the route promise printed in the app',
    run: (repo, cutoff) => repo.pruneLocationHistory(cutoff),
  },
  {
    table: 'geofence_events',
    days: GEOFENCE_EVENT_RETENTION_DAYS,
    why: 'a crossing is the route that produced it and cannot outlive it',
    run: (repo, cutoff) => repo.pruneGeofenceEvents(cutoff),
  },
  {
    table: 'safety_alerts',
    days: SAFETY_ALERT_RETENTION_DAYS,
    why: 'a school year to look back over, not a permanent history of a child',
    run: (repo, cutoff) => repo.pruneSafetyAlerts(cutoff),
  },
  {
    table: 'audit_log',
    days: AUDIT_RETENTION_DAYS,
    why: 'the accountability record; the period the panel has always claimed',
    run: (repo, cutoff) => repo.pruneAuditLog(cutoff),
  },
  {
    table: 'phone_codes',
    days: PHONE_CODE_RETENTION_DAYS,
    why: 'an abandoned sign-in left a phone number behind for ever',
    run: (repo, cutoff) => repo.prunePhoneCodes(cutoff),
  },
  {
    table: 'login_attempts',
    days: LOGIN_ATTEMPT_RETENTION_DAYS,
    why: 'rate-limiting and intrusion review need weeks, not years',
    run: (repo, cutoff) => repo.pruneLoginAttempts(cutoff),
  },
  {
    table: 'shop_leads',
    days: SHOP_LEAD_RETENTION_DAYS,
    why: 'a name and a phone nobody acted on in a year is not a business need',
    run: (repo, cutoff) => repo.pruneShopLeads(cutoff),
  },
  {
    table: 'support_tickets',
    days: SUPPORT_RETENTION_DAYS,
    why: 'a dispute about an order can surface long after the order',
    run: (repo, cutoff) => repo.pruneSupportTickets(cutoff),
  },
];

/**
 * What is deliberately NOT swept, and why.
 *
 * Read by no code. Written so the absence is a decision on the record rather
 * than something nobody got to — which is exactly what the single-table version
 * of this file was. If one of these ever gains a period it moves up into
 * RETENTION_SWEEPS, and the published policy changes in the same commit.
 */
export const RETENTION_KEPT: readonly { table: string; why: string }[] = [
  {
    table: 'shop_orders, shop_order_items, shop_order_events',
    why:
      'Accounting records. RK requires retention of primary accounting '
      + 'documents (commonly cited as five years) and code must not delete a '
      + 'financial record on a period nobody can cite. NEEDS A LAWYER to fix '
      + 'the exact term; until then they are kept, and the policy says so in '
      + 'those words rather than implying a number.',
  },
  {
    table: 'health tables, children, diaries',
    why: 'Kept until the account is deleted, when they cascade. Unchanged.',
  },
  {
    table: 'device_registry.activated_by_phone',
    why: 'Warranty and anti-fraud on a physical unit somebody still owns.',
  },
  {
    table: 'user_entitlements',
    why:
      'What a purchase unlocked, keyed by phone. Deleting it would take away '
      + 'a course she paid for if she came back with the same number.',
  },
];

/**
 * Run one sweep.
 *
 * Never throws. A retention job that takes the process down with it on a
 * transient database error gets disabled by whoever is on call, and a disabled
 * retention job is the state this code exists to end. The failure is REPORTED
 * instead — silence and success must not look the same, which is the other way
 * this fails: nobody notices it stopped.
 */
export async function sweepOne(
  sweep: RetentionSweep,
  repo: RetentionDeps,
  now: Date,
): Promise<RetentionResult> {
  const cutoff = retentionCutoff(now, sweep.days);
  try {
    return { table: sweep.table, removed: await sweep.run(repo, cutoff), cutoff };
  } catch (e) {
    return {
      table: sweep.table,
      removed: 0,
      cutoff,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/**
 * Run every sweep, in order, reporting each separately.
 *
 * Sequential, not parallel: these are cheap indexed DELETEs on one small box,
 * and eight at once against a pool sized for request traffic is how
 * housekeeping causes the outage it exists to prevent.
 */
export async function sweepAll(repo: RetentionDeps, now: Date): Promise<RetentionResult[]> {
  const out: RetentionResult[] = [];
  for (const sweep of RETENTION_SWEEPS) out.push(await sweepOne(sweep, repo, now));
  return out;
}

/** How often the sweeps run once the server is up. */
export const SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;

export interface ScheduleOptions {
  /** Reads the clock. Injected so a test does not have to wait six hours. */
  now?: () => Date;
  /** Where each outcome goes — one call per table, success or failure. */
  log?: (result: RetentionResult) => void;
  intervalMs?: number;
}

/**
 * Start the sweeps and keep them running. Returns a function that stops them.
 *
 * Runs once at startup rather than waiting for the first interval: a server
 * that restarts more often than the period would otherwise never sweep at all,
 * and on a single box a deploy every few days against a six-hour timer is
 * exactly that shape.
 *
 * Four times a day, not once: the shortest promise is 90 days, and a daily job
 * lets a row outlive its window by up to 24 hours. Six hours costs a handful of
 * cheap indexed DELETEs and makes every period true to within a quarter of a
 * day.
 */
export function scheduleRetention(
  repo: RetentionDeps,
  opts: ScheduleOptions = {},
): () => void {
  const now = opts.now ?? (() => new Date());
  const log = opts.log ?? (() => {});
  const run = () => {
    void sweepAll(repo, now()).then((results) => { for (const r of results) log(r); });
  };

  run();
  const timer = setInterval(run, opts.intervalMs ?? SWEEP_INTERVAL_MS);
  // Never hold the process open for this: it is housekeeping, and a test or a
  // CLI that finishes its work should exit.
  if (typeof timer.unref === 'function') timer.unref();
  return () => clearInterval(timer);
}
