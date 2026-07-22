/**
 * Immunisation schedule — the module loads the shared contract, dueAtMonth/
 * dueByMonth derive coverage, and GET /vaccination/schedule serves it.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import { vaccinationSchedule, dueAtMonth, dueByMonth } from '../vaccination/schedule';

describe('vaccination schedule module', () => {
  it('loads the schedule from the shared contract', () => {
    expect(vaccinationSchedule.vaccines.length).toBeGreaterThanOrEqual(16);
    expect(vaccinationSchedule.vaccines[0]).toMatchObject({ id: 'hepb', atMonth: 0 });
  });

  it('every vaccine has an id and a Russian label', () => {
    for (const v of vaccinationSchedule.vaccines) {
      expect(v.id.length).toBeGreaterThan(0);
      expect(v.ru.trim().length).toBeGreaterThan(0);
    }
  });

  it('dueAtMonth returns the birth doses at 0 months', () => {
    const ids = dueAtMonth(0).map((v) => v.id);
    expect(ids).toContain('hepb');
    expect(ids).toContain('bcg');
  });

  it('dueByMonth grows with age', () => {
    expect(dueByMonth(0).length).toBeLessThan(dueByMonth(12).length);
    expect(dueByMonth(72).length).toBe(vaccinationSchedule.vaccines.length);
  });
});

describe('GET /vaccination/schedule', () => {
  function makeApp(): FastifyInstance {
    return buildServer(
      {
        repo: {} as Repository,
        guardrail: { callLLM: async () => 'ok' },
        ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
  }

  it('serves the schedule without auth', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/vaccination/schedule' });
    expect(res.statusCode).toBe(200);
    expect(res.json().vaccines.length).toBeGreaterThanOrEqual(16);
    await app.close();
  });
});
