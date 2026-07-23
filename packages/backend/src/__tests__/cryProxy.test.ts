/**
 * The cry-analysis proxy: POST /cry/analyze authenticates the caller, forwards
 * the raw multipart body to the injected classifier, and returns its JSON.
 * Unauthenticated callers are refused; a missing classifier 503s; an upstream
 * failure surfaces as a clean 502.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';

const ANALYSIS = {
  status: 'success',
  primary_reason: 'hungry',
  confidence: 0.84,
  probabilities: { hungry: 84, tired: 10, belly_pain: 4, discomfort: 2, burping: 0 },
  recommendation_ru: 'Покормите малыша.',
};

function makeApp(opts: { authed?: boolean; cry?: ((a: Buffer, c: string) => Promise<unknown>) | undefined } = {}): FastifyInstance {
  const { authed = true, cry } = opts;
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => (authed ? { userId: 'u1' } : null),
      authAdmin: async () => null,
      cryAnalyze: cry,
    },
    { logger: false },
  );
}

const multipart = { 'content-type': 'multipart/form-data; boundary=X' };
const clip = Buffer.from('----X\r\nfake-audio-bytes\r\n----X--');

describe('POST /cry/analyze', () => {
  it('forwards the clip and returns the classifier JSON', async () => {
    let seenType = '';
    let seenLen = 0;
    const app = makeApp({
      cry: async (audio, contentType) => {
        seenType = contentType;
        seenLen = audio.length;
        return ANALYSIS;
      },
    });
    const res = await app.inject({ method: 'POST', url: '/cry/analyze', headers: multipart, payload: clip });
    expect(res.statusCode).toBe(200);
    expect(res.json().primary_reason).toBe('hungry');
    expect(seenType).toContain('multipart/form-data'); // forwarded verbatim (with boundary)
    expect(seenLen).toBe(clip.length);
    await app.close();
  });

  it('refuses an unauthenticated caller', async () => {
    const app = makeApp({ authed: false, cry: async () => ANALYSIS });
    const res = await app.inject({ method: 'POST', url: '/cry/analyze', headers: multipart, payload: clip });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('503s when the classifier is not configured', async () => {
    const app = makeApp({ cry: undefined });
    const res = await app.inject({ method: 'POST', url: '/cry/analyze', headers: multipart, payload: clip });
    expect(res.statusCode).toBe(503);
    await app.close();
  });

  it('rejects an empty body', async () => {
    const app = makeApp({ cry: async () => ANALYSIS });
    const res = await app.inject({ method: 'POST', url: '/cry/analyze', headers: multipart, payload: Buffer.alloc(0) });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('surfaces an upstream failure as 502', async () => {
    const app = makeApp({ cry: async () => { throw new Error('down'); } });
    const res = await app.inject({ method: 'POST', url: '/cry/analyze', headers: multipart, payload: clip });
    expect(res.statusCode).toBe(502);
    await app.close();
  });
});
