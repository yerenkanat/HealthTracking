/**
 * Antenatal protocol — the module derives the same schedule the app and the
 * admin panel show, and GET /antenatal/protocol serves it. These pin the load
 * from the shared contract, the "which visit now" derivation, and the route.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import type { Repository } from '../db/repository';
import {
  antenatalProtocol,
  visitAtWeek,
  nextVisitAfter,
  currentOrNextVisit,
  windowsOpenAt,
  antenatalStatusForWeek,
} from '../antenatal/protocol';

describe('antenatal protocol module', () => {
  it('loads the 8-visit schedule from the shared contract', () => {
    expect(antenatalProtocol.visits.length).toBe(8);
    expect(antenatalProtocol.visits[0]).toMatchObject({ number: 1, fromWeek: 10, toWeek: 12 });
    expect(antenatalProtocol.visits.at(-1)).toMatchObject({ number: 8, fromWeek: 40 });
  });

  it('every visit item carries a category and a Russian label', () => {
    for (const v of antenatalProtocol.visits) {
      for (const it of v.items) {
        expect(['counsel', 'exam', 'lab', 'imaging', 'prophylaxis']).toContain(it.category);
        expect(it.ru.trim().length).toBeGreaterThan(0);
      }
    }
  });

  it('safety-critical items sit on the right visit', () => {
    const has = (n: number, id: string) =>
      antenatalProtocol.visits[n - 1].items.some((it) => it.id === id);
    expect(has(3, 'anti_d')).toBe(true); // 28–30 wk, rhesus-negative
    expect(has(3, 'ogtt')).toBe(true); // 24–28 wk
    expect(has(4, 'maternity_leave')).toBe(true); // 30 wk
  });

  it('derives the visit due now or next from the week', () => {
    expect(visitAtWeek(11)?.number).toBe(1);
    expect(visitAtWeek(22)).toBeNull(); // between windows
    expect(nextVisitAfter(22)?.number).toBe(3);
    expect(currentOrNextVisit(6)?.number).toBe(1); // before the first
    expect(currentOrNextVisit(41)).toBeNull(); // past term
  });

  it('opens the OGTT and anti-D windows at week 28', () => {
    const open = windowsOpenAt(28).map((w) => w.id);
    expect(open).toContain('ogtt');
    expect(open).toContain('anti_d');
    expect(windowsOpenAt(6)).toHaveLength(0);
  });

  it('summarises a mother’s status for the admin patient view', () => {
    expect(antenatalStatusForWeek(null)).toBeNull();
    expect(antenatalStatusForWeek(27)).toMatchObject({ visitNumber: 3, total: 8, dueNow: true });
    expect(antenatalStatusForWeek(22)).toMatchObject({ visitNumber: 3, dueNow: false });
  });
});

describe('GET /antenatal/protocol', () => {
  function makeApp(): FastifyInstance {
    const repo = {} as Repository;
    return buildServer(
      {
        repo,
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

  it('serves the protocol without auth', async () => {
    const app = makeApp();
    const res = await app.inject({ method: 'GET', url: '/antenatal/protocol' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.visits).toHaveLength(8);
    expect(body.categories.counsel).toBeTruthy();
    await app.close();
  });
});
