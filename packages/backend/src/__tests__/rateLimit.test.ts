/**
 * The /ai/chat rate limit.
 *
 * The route spends money and reaches a third party on every call, and had no
 * limit of any kind. The two failure modes that matter are opposite: letting a
 * runaway client burn the budget, and throttling a woman having an ordinary
 * conversation — in an app where that conversation may be about a symptom.
 */

import { describe, it, expect } from 'vitest';
import { RateLimiter } from '../http/rateLimit';

describe('RateLimiter', () => {
  const build = (limit = 3, windowMs = 1000) => {
    let t = 0;
    const rl = new RateLimiter({ limit, windowMs, now: () => t });
    return { rl, advance: (ms: number) => { t += ms; }, at: () => t };
  };

  it('allows up to the limit and then refuses', () => {
    const { rl } = build(3);
    expect(rl.take('u1').allowed).toBe(true);
    expect(rl.take('u1').allowed).toBe(true);
    expect(rl.take('u1').allowed).toBe(true);
    expect(rl.take('u1').allowed).toBe(false);
  });

  it('counts down the remaining allowance', () => {
    const { rl } = build(3);
    expect(rl.take('u1').remaining).toBe(2);
    expect(rl.take('u1').remaining).toBe(1);
    expect(rl.take('u1').remaining).toBe(0);
  });

  it('keeps callers separate', () => {
    // Shared-account throttling would be the IP-keyed bug in another form.
    const { rl } = build(2);
    rl.take('u1');
    rl.take('u1');
    expect(rl.take('u1').allowed).toBe(false);
    expect(rl.take('u2').allowed).toBe(true);
  });

  it('lets the caller back in once the window passes', () => {
    const { rl, advance } = build(2, 1000);
    rl.take('u1');
    rl.take('u1');
    expect(rl.take('u1').allowed).toBe(false);
    advance(1000);
    expect(rl.take('u1').allowed).toBe(true);
  });

  it('does not extend the window when it refuses', () => {
    // A client retrying in a tight loop must still be let back in on schedule.
    // Extending on rejection would let a buggy retry lock itself out for ever,
    // which punishes the broken client far more than it protects anything.
    const { rl, advance } = build(1, 1000);
    rl.take('u1');
    for (let i = 0; i < 50; i++) {
      advance(10);
      expect(rl.take('u1').allowed).toBe(false);
    }
    advance(500); // 50*10 + 500 = 1000ms since the window opened
    expect(rl.take('u1').allowed).toBe(true);
  });

  it('reports a retry-after that actually counts down', () => {
    const { rl, advance } = build(1, 10_000);
    rl.take('u1');
    const first = rl.take('u1').retryAfterSec;
    advance(5000);
    const later = rl.take('u1').retryAfterSec;
    expect(first).toBe(10);
    expect(later).toBeLessThan(first);
    expect(later).toBeGreaterThan(0);
  });

  it('never reports a retry-after of zero while refusing', () => {
    // A client told to wait 0 seconds retries immediately, which is a hot loop.
    const { rl, advance } = build(1, 1000);
    rl.take('u1');
    advance(999);
    const d = rl.take('u1');
    expect(d.allowed).toBe(false);
    expect(d.retryAfterSec).toBeGreaterThanOrEqual(1);
  });

  it('forgets expired windows instead of growing for ever', () => {
    // One entry per user who ever chatted is a leak that only shows up months
    // into production, as memory that never comes back.
    const { rl, advance } = build(5, 1000);
    for (let i = 0; i < 100; i++) rl.take(`user-${i}`);
    expect(rl.size).toBe(100);
    advance(1000);
    expect(rl.sweep()).toBe(100);
    expect(rl.size).toBe(0);
  });

  it('sweeping does not evict a caller who is still inside their window', () => {
    const { rl, advance } = build(5, 1000);
    rl.take('old');
    advance(1000);
    rl.take('fresh');
    rl.sweep();
    expect(rl.size).toBe(1);
    // And the surviving entry is the fresh one, with its count intact.
    expect(rl.take('fresh').remaining).toBe(3);
  });

  it('an ordinary conversation never meets the shipped limit', () => {
    // 20 per 5 minutes: a message every 15 seconds for five minutes straight.
    // If this ever fails, the limit has been tuned into the user's way.
    let t = 0;
    const rl = new RateLimiter({ limit: 20, windowMs: 5 * 60_000, now: () => t });
    for (let i = 0; i < 20; i++) {
      expect(rl.take('u1').allowed, `message ${i + 1}`).toBe(true);
      t += 15_000;
    }
  });
});
