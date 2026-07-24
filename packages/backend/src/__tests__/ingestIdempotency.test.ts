/**
 * Idempotent telemetry ingest.
 *
 * TelemetryBatcher re-sends a whole batch when a flush fails — including when the
 * server stored it and only the RESPONSE was lost. Before this, the resend wrote a
 * duplicate history row AND fired the emergency push a second time: one reading,
 * two "your blood pressure is critical" notifications to a pregnant woman. The
 * reading is now deduped on (userId, deviceId, recordedAt); a resend stores
 * nothing, pushes nothing, and is reported as a duplicate.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;
let pushes: number;
beforeEach(() => {
  repo = createMemoryRepository();
  pushes = 0;
});

function app(): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => { pushes++; },
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: 'u1' }), // a signed-in mother; manual readings attribute to her
      authAdmin: async () => ({ staffId: 's1', role: 'admin' as const }),
    },
    { logger: false },
  );
}

// A hand-entered cuff reading in the emergency range, attributed to the caller.
const AT = '2026-07-24T08:00:00.000Z';
const EMERGENCY_BATCH = {
  items: [{ type: 'telemetry', payload: { source: 'manual', deviceId: '', recordedAt: AT, systolicMmHg: 168, diastolicMmHg: 116 } }],
};

async function post(a: FastifyInstance, body: unknown) {
  const r = await a.inject({ method: 'POST', url: '/ingest/batch', payload: body });
  return { status: r.statusCode, body: r.json() };
}

describe('POST /ingest/batch is idempotent per reading', () => {
  it('stores + pushes the first time, and treats an identical resend as a duplicate', async () => {
    const a = app();

    const first = await post(a, EMERGENCY_BATCH);
    expect(first.status).toBe(200);
    expect(first.body.telemetryCount).toBe(1);
    expect(first.body.emergencies).toBe(1);
    expect(first.body.duplicates).toBe(0);
    expect(pushes).toBe(1);

    // The batcher requeues the same batch (its flush response was lost).
    const second = await post(a, EMERGENCY_BATCH);
    expect(second.status).toBe(200);
    expect(second.body.telemetryCount).toBe(0); // nothing new stored
    expect(second.body.emergencies).toBe(0);
    expect(second.body.duplicates).toBe(1);
    expect(pushes).toBe(1); // NOT pushed a second time — the whole point

    // And the back-office still shows exactly one emergency, not two.
    const feed = (await a.inject({ method: 'GET', url: '/admin/emergencies' })).json().emergencies;
    expect(feed).toHaveLength(1);
  });

  it('a genuinely different reading (new instant) is stored and pushed on its own', async () => {
    const a = app();
    await post(a, EMERGENCY_BATCH);
    const other = await post(a, {
      items: [{ type: 'telemetry', payload: { source: 'manual', deviceId: '', recordedAt: '2026-07-24T09:15:00.000Z', systolicMmHg: 170, diastolicMmHg: 118 } }],
    });
    expect(other.body.telemetryCount).toBe(1);
    expect(other.body.duplicates).toBe(0);
    expect(pushes).toBe(2);
  });
});
