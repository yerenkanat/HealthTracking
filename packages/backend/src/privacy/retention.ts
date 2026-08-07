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
 * This is the whole of that job. It is deliberately small and deliberately
 * PURE about its arithmetic, because the two ways a retention sweep goes wrong
 * are both invisible in production: it silently stops running, or it computes
 * the wrong cutoff and deletes a year instead of a quarter.
 */

/** The window the app promises, in days. Named once; nothing else may guess. */
export const ROUTE_RETENTION_DAYS = 90;

/**
 * The instant before which a fix must be gone.
 *
 * Takes `now` rather than reading the clock, so the boundary can be exercised
 * at exactly 90 days rather than approximately.
 */
export function retentionCutoff(now: Date, days = ROUTE_RETENTION_DAYS): string {
  return new Date(now.getTime() - days * 86_400_000).toISOString();
}

export interface RetentionResult {
  /** Fixes deleted this run. */
  removed: number;
  /** The cutoff used, so a log line can be checked rather than trusted. */
  cutoff: string;
  /** Set when the sweep failed; the caller decides whether that is fatal. */
  error?: string;
}

export interface RetentionDeps {
  pruneLocationHistory(cutoffIso: string): Promise<number>;
}

/**
 * Run one sweep.
 *
 * Never throws. A retention job that takes the process down with it on a
 * transient database error gets disabled by whoever is on call, and a disabled
 * retention job is the state this code exists to end. The failure is REPORTED
 * instead — silence and success must not look the same, which is the other way
 * this fails: nobody notices it stopped.
 */
export async function sweepRoutes(
  repo: RetentionDeps,
  now: Date,
  days = ROUTE_RETENTION_DAYS,
): Promise<RetentionResult> {
  const cutoff = retentionCutoff(now, days);
  try {
    return { removed: await repo.pruneLocationHistory(cutoff), cutoff };
  } catch (e) {
    return { removed: 0, cutoff, error: e instanceof Error ? e.message : String(e) };
  }
}

/** How often the sweep runs once the server is up. */
export const SWEEP_INTERVAL_MS = 6 * 60 * 60 * 1000;

export interface ScheduleOptions {
  /** Reads the clock. Injected so a test does not have to wait six hours. */
  now?: () => Date;
  /** Where the outcome goes. */
  log?: (result: RetentionResult) => void;
  intervalMs?: number;
  days?: number;
}

/**
 * Start the sweep and keep it running. Returns a function that stops it.
 *
 * Runs once at startup rather than waiting for the first interval: a server
 * that restarts more often than the period would otherwise never sweep at all,
 * and on a single box a deploy every few days against a six-hour timer is
 * exactly that shape.
 *
 * Four times a day, not once: the promise is "90 days", and a daily job means
 * a fix can outlive the window by up to 24 hours. Six hours costs one cheap
 * indexed DELETE and makes the promise true to within a quarter of a day.
 */
export function scheduleRouteRetention(
  repo: RetentionDeps,
  opts: ScheduleOptions = {},
): () => void {
  const now = opts.now ?? (() => new Date());
  const log = opts.log ?? (() => {});
  const run = () => { void sweepRoutes(repo, now(), opts.days).then(log); };

  run();
  const timer = setInterval(run, opts.intervalMs ?? SWEEP_INTERVAL_MS);
  // Never hold the process open for this: it is housekeeping, and a test or a
  // CLI that finishes its work should exit.
  if (typeof timer.unref === 'function') timer.unref();
  return () => clearInterval(timer);
}
