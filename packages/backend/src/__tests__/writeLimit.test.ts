/**
 * The write-limiter backstop: authenticated writes share one per-identity budget
 * (a runaway is bounded whichever sync endpoint it hits), while reads and the
 * separately-limited /ingest, /ai/chat are exempt.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { RateLimiter } from '../http/rateLimit';

function makeApp(): FastifyInstance {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: 'u1' }),
      authAdmin: async () => null,
      // Tiny budget so the test hits it deterministically.
      writeLimiter: new RateLimiter({ limit: 2, windowMs: 60_000 }),
    },
    { logger: false },
  );
}

const weight = (kg: number) => ({ method: 'POST' as const, url: '/weight', payload: { date: '2026-07-20', kg } });

describe('write limiter', () => {
  it('429s past the per-identity write budget, then reads still work', async () => {
    const app = makeApp();
    expect((await app.inject(weight(60))).statusCode).toBe(201);
    expect((await app.inject(weight(61))).statusCode).toBe(201);
    const over = await app.inject(weight(62)); // 3rd write in the window
    expect(over.statusCode).toBe(429);
    expect(over.headers['retry-after']).toBeTruthy();
    // A GET is never throttled by the write limiter.
    expect((await app.inject({ method: 'GET', url: '/weight' })).statusCode).toBe(200);
    await app.close();
  });

  it('applies across different sync endpoints (shared budget)', async () => {
    const app = makeApp();
    await app.inject(weight(60)); // 1
    await app.inject({ method: 'POST', url: '/medications', payload: { id: 'm1', name: 'Iron' } }); // 2
    // A third write on yet another endpoint is refused.
    const r = await app.inject({ method: 'POST', url: '/sleep', payload: { night: '2026-07-20', deepMin: 1, remMin: 1, lightMin: 1, awakeMin: 1 } });
    expect(r.statusCode).toBe(429);
    await app.close();
  });
});
