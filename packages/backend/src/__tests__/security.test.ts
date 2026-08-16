/**
 * Frame 22 — «Безопасность»: who has been reading special-category data.
 *
 * Every part of this existed and none of it was on a screen. The audit log
 * records who opened whose record and why, the capability matrix decides who
 * may, the retention sweep deletes routes at 90 days — and there was no page
 * that let anybody ASK whether it was being abused. A log nobody can query is
 * evidence after the fact and nothing before it.
 *
 * The number that matters is not the total. It is how many reads touched health
 * or a child's location, and how many of those went unexplained.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { PROTECTED_ACTIONS, summarizeSecurity, type AuditRow } from '../admin/security';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { StaffRole } from '../auth/capabilities';

const NOW = new Date('2026-08-08T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

const row = (over: Partial<AuditRow> = {}): AuditRow => ({
  staffId: 's1',
  staffName: 'Ерен',
  action: 'view_health',
  target: 'u1',
  targetName: 'Айгерім',
  reason: 'Обращение клиента',
  at: daysAgo(1),
  ...over,
});

describe('what counts as a protected read', () => {
  it('health and location, and nothing else', () => {
    expect(PROTECTED_ACTIONS.view_health).toBe('health');
    expect(PROTECTED_ACTIONS.view_wellness).toBe('health');
    expect(PROTECTED_ACTIONS.view_safety_feed).toBe('location');
    expect(PROTECTED_ACTIONS.view_devices).toBe('location');
    // Ordinary back-office work is not a privacy event, and counting it here
    // would bury the reads that are.
    expect(PROTECTED_ACTIONS.list_users).toBeUndefined();
    expect(PROTECTED_ACTIONS.edit_content).toBeUndefined();
    expect(PROTECTED_ACTIONS.stock_move).toBeUndefined();
  });

  it('separates the two kinds, because they answer to different rules', () => {
    const s = summarizeSecurity(
      [row(), row({ action: 'view_devices' }), row({ action: 'view_wellness' })],
      NOW,
    );
    expect(s.protectedReads).toBe(3);
    expect(s.health).toBe(2);
    expect(s.location).toBe(1);
  });

  it('ignores everything outside the window', () => {
    const s = summarizeSecurity([row({ at: daysAgo(40) }), row({ at: daysAgo(3) })], NOW, 30);
    expect(s.protectedReads).toBe(1);
  });
});

describe('the number that should be zero', () => {
  it('counts reads with no reason recorded', () => {
    // Either a row from before the reason became mandatory, or a route that
    // reached protected data without going through readReason — which is the
    // hole this page exists to make visible.
    const s = summarizeSecurity([row(), row({ reason: null }), row({ reason: '  ' })], NOW);
    expect(s.withoutReason).toBe(2);
  });

  it('treats an empty reason as no reason', () => {
    // Otherwise the number that should be zero stays zero while the log fills
    // with blanks.
    expect(summarizeSecurity([row({ reason: '' })], NOW).withoutReason).toBe(1);
  });
});

describe('who has been looking', () => {
  it('ranks staff by how much they read, and names them', () => {
    const s = summarizeSecurity(
      [
        row({ staffId: 'a', staffName: 'Айгерім' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
      ],
      NOW,
    );
    expect(s.byStaff[0]).toEqual({ staffId: 'b', staffName: 'Ерен', reads: 3 });
    expect(s.byStaff[1].staffId).toBe('a');
  });

  it('the log itself comes back newest first', () => {
    // It is read from the top by somebody checking what just happened.
    const s = summarizeSecurity(
      [row({ at: daysAgo(5), target: 'old' }), row({ at: daysAgo(1), target: 'new' })],
      NOW,
    );
    expect(s.recent[0].target).toBe('new');
  });
});

// ---------------------------------------------------------------------------

let app: FastifyInstance;

function makeApp(role: StaffRole) {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

beforeEach(() => { app = makeApp('owner'); });

describe('GET /admin/security', () => {
  it('reports a real read end to end', async () => {
    // Open a health record with a reason, then ask the security page about it.
    //
    // `/detail` rather than the deleted `/health` (docs/BACKLOG.md §3): it is
    // the read the panel makes, it carries the same guard and reason gate, and
    // `view_user_detail` is a `health` action in PROTECTED_ACTIONS — so this
    // still exercises the health counter, through the route that is used.
    await app.inject({
      method: 'GET',
      url: `/admin/users/${DEMO_USER}/detail?reason=${encodeURIComponent('Разбор жалобы')}`,
    });
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(body.protectedReads).toBeGreaterThanOrEqual(1);
    expect(body.health).toBeGreaterThanOrEqual(1);
    expect(body.withoutReason).toBe(0);
    expect(body.recent[0].reason).toBe('Разбор жалобы');
    await app.close();
  });

  it('quotes the retention promises from where they are defined', async () => {
    // The screen reports these to a regulator. Re-typing 90 here is how the
    // page ends up claiming something the sweep does not do.
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(body.retention.routeDays).toBe(90);
    expect(body.retention.auditYears).toBe(3);
    await app.close();
  });

  it('is the `staff` capability, not `health`', async () => {
    // Being able to read health records is not the same as being able to read
    // the record of everyone reading them.
    const clinician = makeApp('clinician');
    expect((await clinician.inject({ method: 'GET', url: '/admin/security' })).statusCode).toBe(403);
    await clinician.close();
    await app.close();
  });

  it('bounds the window rather than trusting the query', async () => {
    const body = (await app.inject({ method: 'GET', url: '/admin/security?days=99999' })).json();
    expect(body.windowDays).toBeLessThanOrEqual(365);
    await app.close();
  });
});
