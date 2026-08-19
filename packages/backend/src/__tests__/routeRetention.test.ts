/**
 * «Маршруты хранятся 90 дней» — and now something actually deletes them.
 *
 * db/schema.sql has carried the DELETE since the Timescale retention policy was
 * dropped, as a COMMENT, with a note to run it "as a scheduled job (pg_cron,
 * or an app cron)". Neither was ever set up. So every child's location trail
 * had been accumulating since the first fix: a minute-by-minute record of where
 * a named child has been for as long as the family has used the product, kept
 * against an explicit promise not to.
 *
 * The two ways a retention sweep goes wrong are both invisible in production —
 * it quietly stops running, or it computes the wrong cutoff and deletes a year
 * instead of a quarter. So the arithmetic is pure and exercised at its
 * boundary, and the wiring is asserted separately from it.
 */

import { describe, it, expect, vi } from 'vitest';
import {
  ROUTE_RETENTION_DAYS,
  RETENTION_SWEEPS,
  retentionCutoff,
  scheduleRetention,
  sweepOne,
  type RetentionDeps,
} from '../privacy/retention';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

const NOW = new Date('2026-08-07T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

/**
 * The route sweep, looked up rather than reconstructed.
 *
 * Taken from RETENTION_SWEEPS by table name, so if the entry is ever dropped
 * from the schedule this file fails on the lookup instead of quietly testing a
 * sweep nothing runs. That is the exact failure this suite exists for: the
 * DELETE was never missing, the CALLER was.
 */
const ROUTE_SWEEP = RETENTION_SWEEPS.find((s) => s.table === 'location_history')!;

/**
 * A RetentionDeps whose other tables do nothing, so a test about routes is
 * about routes. Anything not overridden returns 0 and deletes nothing.
 */
const deps = (over: Partial<RetentionDeps> = {}): RetentionDeps => ({
  pruneLocationHistory: async () => 0,
  pruneGeofenceEvents: async () => 0,
  pruneSafetyAlerts: async () => 0,
  pruneAuditLog: async () => 0,
  prunePhoneCodes: async () => 0,
  pruneLoginAttempts: async () => 0,
  pruneShopLeads: async () => 0,
  pruneSupportTickets: async () => 0,
  ...over,
});

describe('the window is the one the app promises', () => {
  it('is 90 days, named once', () => {
    // The app's privacy policy quotes this number to every user. It must live
    // in one place, not be re-typed at each call site.
    expect(ROUTE_RETENTION_DAYS).toBe(90);
  });

  it('the cutoff is exactly 90 days back, not 89 or 91', () => {
    // A month-arithmetic version of this is off by up to two days depending on
    // which months it spans, which is how a promise quietly becomes a lie.
    expect(retentionCutoff(NOW)).toBe(daysAgo(90));
  });

  it('does not read the clock itself', () => {
    // Taking `now` is what makes the boundary testable at all. A function that
    // called Date.now() could only ever be checked approximately.
    expect(retentionCutoff(new Date('2020-01-01T00:00:00.000Z'), 1))
      .toBe('2019-12-31T00:00:00.000Z');
  });
});

describe('one sweep', () => {
  it('asks the repository to delete everything past the window', async () => {
    const prune = vi.fn(async () => 41);
    const res = await sweepOne(ROUTE_SWEEP, deps({ pruneLocationHistory: prune }), NOW);
    expect(prune).toHaveBeenCalledWith(daysAgo(90));
    // The table travels with the result: with eight sweeps on one schedule, a
    // log line saying only "removed 41" cannot be checked against anything.
    expect(res).toEqual({ table: 'location_history', removed: 41, cutoff: daysAgo(90) });
  });

  it('reports a failure instead of throwing', async () => {
    // A retention job that takes the process down on a transient database error
    // gets disabled by whoever is on call, and a disabled retention job is the
    // state this whole feature exists to end.
    const res = await sweepOne(
      ROUTE_SWEEP,
      deps({ pruneLocationHistory: async () => { throw new Error('connection reset'); } }),
      NOW,
    );
    expect(res.error).toBe('connection reset');
    expect(res.removed).toBe(0);
    // The cutoff still comes back, so a log line says what it was trying to do.
    expect(res.cutoff).toBe(daysAgo(90));
  });

  it('a quiet run and a failed run do not look alike', async () => {
    // The other way this dies: nobody notices it stopped.
    const quiet = await sweepOne(ROUTE_SWEEP, deps({ pruneLocationHistory: async () => 0 }), NOW);
    expect(quiet.error).toBeUndefined();
  });
});

describe('it is scheduled, which is the part that was missing', () => {
  it('runs immediately rather than waiting for the first interval', async () => {
    // A server that restarts more often than the period would otherwise never
    // sweep at all — and on one box, a deploy every few days against a
    // six-hour timer is exactly that shape.
    const prune = vi.fn(async () => 0);
    const stop = scheduleRetention(deps({ pruneLocationHistory: prune }), { now: () => NOW });
    await vi.waitFor(() => expect(prune).toHaveBeenCalledTimes(1));
    stop();
  });

  it('keeps running, and stops when told', async () => {
    vi.useFakeTimers();
    try {
      const prune = vi.fn(async () => 0);
      const stop = scheduleRetention(
        deps({ pruneLocationHistory: prune }),
        { now: () => NOW, intervalMs: 1000 },
      );
      expect(prune).toHaveBeenCalledTimes(1); // the immediate run
      await vi.advanceTimersByTimeAsync(3500);
      expect(prune).toHaveBeenCalledTimes(4);

      stop();
      await vi.advanceTimersByTimeAsync(5000);
      expect(prune, 'the sweep kept running after it was stopped').toHaveBeenCalledTimes(4);
    } finally {
      vi.useRealTimers();
    }
  });

  it('a failing sweep does not stop the schedule', async () => {
    // One bad night must not silently end retention for good.
    vi.useFakeTimers();
    try {
      const prune = vi.fn(async () => { throw new Error('down'); });
      const stop = scheduleRetention(
        deps({ pruneLocationHistory: prune }),
        { now: () => NOW, intervalMs: 1000 },
      );
      await vi.advanceTimersByTimeAsync(2500);
      expect(prune.mock.calls.length).toBeGreaterThan(1);
      stop();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('the repository really drops the old fixes', () => {
  it('a fix past the window goes; a fix inside it stays', async () => {
    const repo = createMemoryRepository();
    await repo.insertLocation({
      childId: 'old-child', coords: { lat: 43.2, lng: 76.8 },
      source: 'gps', observedAt: daysAgo(120),
    });
    await repo.insertLocation({
      childId: 'recent-child', coords: { lat: 43.3, lng: 76.9 },
      source: 'gps', observedAt: daysAgo(10),
    });

    const removed = await repo.pruneLocationHistory(retentionCutoff(NOW));
    expect(removed).toBe(1);
    expect(await repo.lastLocation('old-child')).toBeNull();
    expect(await repo.lastLocation('recent-child')).not.toBeNull();
  });

  it('the boundary is inclusive of "still inside the window"', async () => {
    // Exactly 90 days old is the last day it is kept. Getting this backwards
    // deletes a day early, which is the safe direction — but the promise is a
    // number, and a number that is wrong by a day is wrong.
    const repo = createMemoryRepository();
    await repo.insertLocation({
      childId: 'edge', coords: { lat: 43.2, lng: 76.8 },
      source: 'gps', observedAt: daysAgo(90),
    });
    expect(await repo.pruneLocationHistory(retentionCutoff(NOW))).toBe(0);
    expect(await repo.lastLocation('edge')).not.toBeNull();
  });
});

describe('the server starts it', () => {
  it('a built server sweeps without anybody asking', async () => {
    // The defect this replaces was not a missing DELETE — it was a DELETE
    // nobody called. Wiring is the whole point, so it is asserted against a
    // real buildServer rather than the scheduler in isolation.
    const repo = createMemoryRepository();
    const pruned: string[] = [];
    const watched = new Proxy(repo, {
      get(target, prop: string) {
        if (prop === 'pruneLocationHistory') {
          return async (cutoff: string) => { pruned.push(cutoff); return 0; };
        }
        return (target as unknown as Record<string, unknown>)[prop];
      },
    });

    const app = buildServer(
      {
        repo: watched,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => null,
      },
      { logger: false },
    );
    await app.ready();
    await vi.waitFor(() => expect(pruned.length).toBeGreaterThan(0));
    // And with the right window, not some other number picked at the call site.
    const age = Date.now() - Date.parse(pruned[0]);
    expect(age / 86_400_000).toBeCloseTo(ROUTE_RETENTION_DAYS, 1);
    await app.close();
  });
});
