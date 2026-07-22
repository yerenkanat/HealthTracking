/**
 * Week-by-week pregnancy calendar — the module loads the shared contract and the
 * routes serve it. These pin the load (ru + kk present for every week), the
 * clamping, and the two endpoints.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import { pregnancyCalendar, weekContent, firstWeek, lastWeek } from '../pregnancy/weeks';

describe('pregnancy calendar module', () => {
  it('loads a week-by-week calendar from the shared contract', () => {
    expect(pregnancyCalendar.weeks.length).toBeGreaterThanOrEqual(40);
    expect(firstWeek).toBe(1);
    expect(lastWeek).toBeGreaterThanOrEqual(40);
  });

  it('every week has Russian and Kazakh baby / you / recommend text', () => {
    for (const w of pregnancyCalendar.weeks) {
      for (const lang of ['ru', 'kk'] as const) {
        expect(w[lang].baby.trim().length, `week ${w.week} ${lang}.baby`).toBeGreaterThan(0);
        expect(w[lang].you.trim().length, `week ${w.week} ${lang}.you`).toBeGreaterThan(0);
        expect(w[lang].recommend.trim().length, `week ${w.week} ${lang}.recommend`).toBeGreaterThan(0);
      }
    }
  });

  it('weekContent clamps out-of-range weeks to the nearest real entry', () => {
    expect(weekContent(6)?.week).toBe(6);
    expect(weekContent(0)?.week).toBe(firstWeek); // before the start
    expect(weekContent(99)?.week).toBe(lastWeek); // past the end
  });
});

describe('pregnancy calendar routes', () => {
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

  it('GET /pregnancy/weeks serves the whole calendar', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/pregnancy/weeks' });
    expect(res.statusCode).toBe(200);
    expect(res.json().weeks.length).toBeGreaterThanOrEqual(40);
    await app.close();
  });

  it('GET /pregnancy/weeks/:week serves one week, 404s an impossible one is clamped', async () => {
    const app = makeApp();
    const ok = await app.inject({ method: 'GET', url: '/pregnancy/weeks/12' });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().week).toBe(12);
    const bad = await app.inject({ method: 'GET', url: '/pregnancy/weeks/abc' });
    expect(bad.statusCode).toBe(400);
    await app.close();
  });
});
