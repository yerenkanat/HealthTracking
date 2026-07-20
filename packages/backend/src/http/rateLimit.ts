/**
 * A small per-caller rate limiter.
 *
 * WHY IN-PROCESS: the app has no Redis in dev, and reaching for one here would
 * make the limit untestable and undeployable in the same breath. This is a
 * fixed-window counter held in memory — correct for a single instance, and the
 * seam to swap for a shared store when there is more than one.
 *
 * KEYED BY USER, NOT IP. The callers are authenticated, and a whole city behind
 * one carrier NAT shares an IP — limiting by address would throttle strangers
 * for each other's traffic. An unauthenticated request never reaches here.
 *
 * WHAT IT IS FOR: /ai/chat spends money per call and is the one route where a
 * loop — a broken client as easily as an abusive one — is expensive rather than
 * merely noisy. Telemetry ingest is deliberately NOT limited this way: it is
 * high-volume by design, and dropping it would lose health data.
 */

export interface RateLimitDecision {
  allowed: boolean;
  /** Requests left in the current window, after this one. */
  remaining: number;
  /** Seconds until the window resets — what a Retry-After header wants. */
  retryAfterSec: number;
}

export interface RateLimiterOptions {
  /** Requests permitted per window. */
  limit: number;
  windowMs: number;
  /** Injected so tests do not sleep. */
  now?: () => number;
}

export class RateLimiter {
  private readonly limit: number;
  private readonly windowMs: number;
  private readonly now: () => number;
  private readonly hits = new Map<string, { count: number; windowStart: number }>();

  constructor(opts: RateLimiterOptions) {
    this.limit = opts.limit;
    this.windowMs = opts.windowMs;
    this.now = opts.now ?? Date.now;
  }

  take(key: string): RateLimitDecision {
    const t = this.now();
    const entry = this.hits.get(key);

    if (!entry || t - entry.windowStart >= this.windowMs) {
      this.hits.set(key, { count: 1, windowStart: t });
      return { allowed: true, remaining: this.limit - 1, retryAfterSec: 0 };
    }

    const retryAfterSec = Math.max(1, Math.ceil((entry.windowStart + this.windowMs - t) / 1000));
    if (entry.count >= this.limit) {
      // Deliberately does NOT extend the window on a rejected request. Doing so
      // would let a client that keeps hammering lock itself out indefinitely,
      // which punishes a buggy retry loop far more than it protects anything.
      return { allowed: false, remaining: 0, retryAfterSec };
    }

    entry.count += 1;
    return { allowed: true, remaining: this.limit - entry.count, retryAfterSec };
  }

  /**
   * Drop windows that have expired.
   *
   * Without this the map grows once per user forever — a slow leak that only
   * shows up in production, months in, as memory that never comes back.
   */
  sweep(): number {
    const t = this.now();
    let dropped = 0;
    for (const [key, entry] of this.hits) {
      if (t - entry.windowStart >= this.windowMs) {
        this.hits.delete(key);
        dropped++;
      }
    }
    return dropped;
  }

  /** Live entry count — for the sweep test and for ops visibility. */
  get size(): number {
    return this.hits.size;
  }
}
