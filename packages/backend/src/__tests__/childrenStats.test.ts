/**
 * Children demographics — the pure aggregation (gender split + age buckets),
 * the admin route that serves it, and the readiness probe added alongside.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { computeChildrenStats, ageInMonths, bucketForMonths } from '../analytics/childStats';

const ASOF = '2026-07-23T00:00:00.000Z';

describe('computeChildrenStats', () => {
  it('counts gender, including unknown', () => {
    const s = computeChildrenStats(
      [{ gender: 'boy' }, { gender: 'girl' }, { gender: 'girl' }, { gender: null }],
      ASOF,
    );
    expect(s.total).toBe(4);
    expect(s.boys).toBe(1);
    expect(s.girls).toBe(2);
    expect(s.unknown).toBe(1);
  });

  it('buckets ages and counts only children with a DOB', () => {
    const s = computeChildrenStats(
      [
        { dateOfBirth: '2026-01-01' }, // ~6 months → 0–1
        { dateOfBirth: '2024-01-01' }, // ~2.5y → 1–3
        { dateOfBirth: '2021-01-01' }, // ~5.5y → 3–7
        { dateOfBirth: '2015-01-01' }, // ~11y → 7+
        { dateOfBirth: null }, // no DOB → not in any bucket
      ],
      ASOF,
    );
    expect(s.withDob).toBe(4);
    const b = Object.fromEntries(s.byAge.map((x) => [x.bucket, x.count]));
    expect(b['0–1']).toBe(1);
    expect(b['1–3']).toBe(1);
    expect(b['3–7']).toBe(1);
    expect(b['7+']).toBe(1);
  });

  it('ageInMonths handles the not-yet-a-full-month case and never goes negative', () => {
    expect(ageInMonths('2026-06-25', '2026-07-23')).toBe(0); // < 1 month
    expect(ageInMonths('2026-06-23', '2026-07-23')).toBe(1);
    expect(ageInMonths('2027-01-01', '2026-07-23')).toBe(0); // future DOB clamps to 0
    expect(bucketForMonths(0)).toBe('0–1');
    expect(bucketForMonths(200)).toBe('7+');
  });
});

function makeApp(admin = true): FastifyInstance {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => (admin ? { staffId: 's1', role: 'admin' } : null),
    },
    { logger: false },
  );
}

describe('GET /admin/children/stats', () => {
  it('serves demographics for the demo cohort (admin only)', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin/children/stats' });
    expect(res.statusCode).toBe(200);
    const s = res.json();
    expect(s.total).toBeGreaterThanOrEqual(6);
    expect(s.boys + s.girls + s.unknown).toBe(s.total);
    expect(s.byAge.length).toBe(4);
    await app.close();
  });

  it('is admin-only', async () => {
    const app = makeApp(false);
    const res = await app.inject({ method: 'GET', url: '/admin/children/stats' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });
});

describe('GET /ready', () => {
  it('reports ready when no dependency check is wired (in-memory dev)', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/ready' });
    expect(res.statusCode).toBe(200);
    expect(res.json().ready).toBe(true);
    await app.close();
  });

  it('reports 503 when a dependency is down', async () => {
    const app = buildServer(
      {
        repo: createMemoryRepository(),
        guardrail: { callLLM: async () => 'ok' },
        ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
        checkReady: async () => ({ ready: false, deps: { postgres: false } }),
      },
      { logger: false },
    );
    const res = await app.inject({ method: 'GET', url: '/ready' });
    expect(res.statusCode).toBe(503);
    expect(res.json().ready).toBe(false);
    await app.close();
  });
});
