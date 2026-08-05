/**
 * The audit log must survive a live feed.
 *
 * Found in production: 92 of 128 audit rows were `view_emergencies`, written
 * by the panel re-fetching the emergency feed every 20 seconds. One laptop
 * left open makes about 4 300 of them a day, and the entries the log exists
 * for — who opened this mother's record — sit underneath.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { createAuditThrottle } from '../http/auditThrottle';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

describe('the throttle itself', () => {
  it('writes the first time and swallows the rest of the window', () => {
    let now = 1_000_000;
    const t = createAuditThrottle(5 * 60 * 1000, () => now);

    expect(t.shouldWrite('staff-1', 'view_emergencies'), 'the first look must be recorded').toBe(true);
    now += 20_000;
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(false);
    now += 20_000;
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(false);
  });

  it('records again once the window has passed', () => {
    // Somebody watching the feed all afternoon should leave a trail through
    // the afternoon, not one row at the start of it.
    let now = 1_000_000;
    const t = createAuditThrottle(5 * 60 * 1000, () => now);
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(true);
    now += 5 * 60 * 1000 + 1;
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(true);
  });

  it('keeps people apart', () => {
    // Otherwise one person's poll would hide a colleague's first look — which
    // is the one thing this log must never do.
    const t = createAuditThrottle(5 * 60 * 1000, () => 1_000_000);
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(true);
    expect(t.shouldWrite('staff-2', 'view_emergencies'), 'a different person, a different row').toBe(true);
  });

  it('keeps actions apart', () => {
    const t = createAuditThrottle(5 * 60 * 1000, () => 1_000_000);
    expect(t.shouldWrite('staff-1', 'view_emergencies')).toBe(true);
    expect(t.shouldWrite('staff-1', 'view_health'), 'a different action is a different act').toBe(true);
  });
});

describe('the live feed against a real server', () => {
  let repo: Repository;
  let app: FastifyInstance;

  beforeEach(() => {
    repo = createMemoryRepository();
    app = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => ({ staffId: 'staff-1', role: 'admin' }),
      },
      { logger: false },
    );
  });

  const poll = () => app.inject({ method: 'GET', url: '/admin/emergencies' });
  const auditCount = async () =>
    (await repo.listAudit(500)).filter((a) => a.action === 'view_emergencies').length;

  it('records one row however many times the panel refreshes', async () => {
    for (let i = 0; i < 15; i++) expect((await poll()).statusCode).toBe(200);
    expect(await auditCount(), 'fifteen polls should not be fifteen rows').toBe(1);
  });

  it('still serves the feed every time', async () => {
    // Throttling the AUDIT must not throttle the data. The feed is how staff
    // see an emergency, and a skipped response is a missed alert.
    for (let i = 0; i < 5; i++) {
      const res = await poll();
      expect(res.statusCode).toBe(200);
      expect(res.json()).toHaveProperty('emergencies');
    }
  });
});
