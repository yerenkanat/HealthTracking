/**
 * Week-by-week baby-development calendar — the module loads the shared contract
 * and the routes serve it. These pin the load (ru + kk skills for every week of
 * the first year), the WHO disclaimer note, the clamping, and the two endpoints.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import { childDevCalendar, devWeekContent, firstDevWeek, lastDevWeek } from '../child/development';

describe('baby-development calendar module', () => {
  it('loads a week-by-week calendar covering the first year from the shared contract', () => {
    expect(childDevCalendar.weeks.length).toBeGreaterThanOrEqual(52);
    expect(firstDevWeek).toBe(1);
    expect(lastDevWeek).toBeGreaterThanOrEqual(52);
  });

  it('every week has WHO ranges and Russian + Kazakh motor / speech / cognition text', () => {
    for (const w of childDevCalendar.weeks) {
      expect(w.weightKg.trim().length, `week ${w.week} weightKg`).toBeGreaterThan(0);
      expect(w.heightCm.trim().length, `week ${w.week} heightCm`).toBeGreaterThan(0);
      for (const lang of ['ru', 'kk'] as const) {
        expect(w[lang].motor.trim().length, `week ${w.week} ${lang}.motor`).toBeGreaterThan(0);
        expect(w[lang].speech.trim().length, `week ${w.week} ${lang}.speech`).toBeGreaterThan(0);
        expect(w[lang].cognition.trim().length, `week ${w.week} ${lang}.cognition`).toBeGreaterThan(0);
      }
    }
  });

  it('carries the paediatrician disclaimer note in both languages', () => {
    expect(childDevCalendar.note.ru.trim().length).toBeGreaterThan(0);
    expect(childDevCalendar.note.kk.trim().length).toBeGreaterThan(0);
  });

  it('devWeekContent clamps out-of-range weeks to the nearest real entry', () => {
    expect(devWeekContent(24)?.week).toBe(24);
    expect(devWeekContent(0)?.week).toBe(firstDevWeek); // newborn, before week 1
    expect(devWeekContent(999)?.week).toBe(lastDevWeek); // past one year
  });
});

describe('baby-development calendar routes', () => {
  function makeApp(): FastifyInstance {
    return buildServer(
      {
        repo: {} as Repository,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {},
          resolveTransition: async () => null,
          sendEmergencyPush: async () => {},
          sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
  }

  it('GET /child/development serves the whole calendar', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/child/development' });
    expect(res.statusCode).toBe(200);
    expect(res.json().weeks.length).toBeGreaterThanOrEqual(52);
    await app.close();
  });

  it('GET /child/development/:week serves one week and rejects a non-numeric one', async () => {
    const app = makeApp();
    const ok = await app.inject({ method: 'GET', url: '/child/development/24' });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().week).toBe(24);
    const bad = await app.inject({ method: 'GET', url: '/child/development/abc' });
    expect(bad.statusCode).toBe(400);
    await app.close();
  });
});
