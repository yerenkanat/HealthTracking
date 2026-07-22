/**
 * Acknowledging an emergency — the back-office action that was removed for want
 * of anywhere to store it. It is an OVERLAY: the emergency is still derived from
 * the health-metric row on the safety path; only the acknowledgement is new.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const STAFF = { staffId: 's1', role: 'admin' as const };

let repo: Repository;
beforeEach(() => {
  repo = createMemoryRepository();
});

function app(): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => STAFF,
    },
    { logger: false },
  );
}

/** Put an emergency-severity metric into the repo so it surfaces on the feed. */
async function seedEmergency(at: string) {
  await repo.insertHealthMetric({
    deviceId: 'd', userId: 'u1', recordedAt: at, triageSeverity: 'emergency',
  } as never);
}

describe('POST /admin/emergencies/:id/ack', () => {
  it('acknowledges an emergency, and a repeat is a no-op (409)', async () => {
    await seedEmergency('2026-07-15T08:00:00.000Z');
    const a = app();

    let feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;
    expect(feed).toHaveLength(1);
    expect(feed[0].acknowledgedAt).toBeNull();
    const id = feed[0].id;
    expect(id).toContain('u1|');

    const ack1 = await a.inject({ method: 'POST', url: `/admin/emergencies/${encodeURIComponent(id)}/ack` });
    expect(ack1.statusCode).toBe(200);

    feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;
    expect(feed[0].acknowledgedAt).not.toBeNull();
    expect(feed[0].acknowledgedBy).toBe('s1');

    // Idempotent: acknowledging again reports it was already done.
    const ack2 = await a.inject({ method: 'POST', url: `/admin/emergencies/${encodeURIComponent(id)}/ack` });
    expect(ack2.statusCode).toBe(409);
    await a.close();
  });

  it('requires staff auth', async () => {
    const a = buildServer(
      {
        repo, guardrail: { callLLM: async () => 'ok' },
        ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
        cacheLastLocation: async () => null, setBpCalibration: async () => {},
        authUser: async () => null, authAdmin: async () => null,
      },
      { logger: false },
    );
    const res = await a.inject({ method: 'POST', url: '/admin/emergencies/x/ack' });
    expect(res.statusCode).toBe(401);
    await a.close();
  });
});
