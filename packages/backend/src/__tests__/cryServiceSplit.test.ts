/**
 * "Cannot answer" and "did not answer" are different answers.
 *
 * `/cry/analyze` used to reply a flat 502 for every upstream failure, so the
 * phone could not tell a dropped connection from a classifier that has no
 * trained model at all — and the screen invited a mother to record her baby
 * again, five seconds at a time, for a failure that will never resolve on its
 * own. `docs/INTEGRATION_STATUS.md:34` says that is today's production state.
 *
 * This file pins the three outcomes and the availability probe the app asks
 * BEFORE it opens a microphone.
 */

import { describe, it, expect, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { CryUpstreamError, cryFailureFor, cryFailureReply } from '../cry/upstream';

const AUDIO = Buffer.from('five seconds of a baby, more or less');

type Deps = {
  cryAnalyze?: (a: Buffer, ct: string) => Promise<unknown>;
  cryAvailable?: () => Promise<boolean>;
  signedIn?: boolean;
};

function makeApp({ cryAnalyze, cryAvailable, signedIn = true }: Deps): FastifyInstance {
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
      authUser: async () => (signedIn ? { userId: DEMO_USER } : null),
      authAdmin: async () => null,
      cryAnalyze,
      cryAvailable,
    },
    { logger: false },
  );
}

const analyse = (app: FastifyInstance) =>
  app.inject({ method: 'POST', url: '/cry/analyze', headers: { 'content-type': 'audio/m4a' }, payload: AUDIO });

const availability = (app: FastifyInstance) => app.inject({ method: 'GET', url: '/cry/availability' });

describe('cryFailureFor (pure)', () => {
  it('503 from the classifier is "it cannot analyse"', () => {
    expect(cryFailureFor(new CryUpstreamError(503))).toBe('unavailable');
    expect(cryFailureReply('unavailable').status).toBe(503);
  });

  it('400/413/415/422 are about the clip, not the service', () => {
    for (const status of [400, 413, 415, 422]) {
      expect(cryFailureFor(new CryUpstreamError(status)), String(status)).toBe('unreadable');
    }
    expect(cryFailureReply('unreadable').status).toBe(400);
  });

  it('a rate limit or a request timeout is NOT blamed on her recording', () => {
    // Sending her back to re-record because we were throttled would be the same
    // defect as blaming the noise in her room for a missing model file.
    for (const status of [408, 429]) {
      expect(cryFailureFor(new CryUpstreamError(status)), String(status)).toBe('unreachable');
    }
  });

  it('a socket error, a timeout or a 5xx is "we never found out"', () => {
    expect(cryFailureFor(new Error('ECONNREFUSED'))).toBe('unreachable');
    expect(cryFailureFor(new DOMException('aborted', 'TimeoutError'))).toBe('unreachable');
    expect(cryFailureFor(new CryUpstreamError(500))).toBe('unreachable');
    expect(cryFailureFor(new CryUpstreamError(502))).toBe('unreachable');
    expect(cryFailureReply('unreachable').status).toBe(502);
  });
});

describe('POST /cry/analyze preserves the upstream status', () => {
  it('a classifier with no model answers 503, not 502', async () => {
    const app = makeApp({ cryAnalyze: async () => { throw new CryUpstreamError(503); } });
    const res = await analyse(app);
    expect(res.statusCode).toBe(503);
    expect(res.json()).toEqual({ error: 'cry_service_unavailable', reason: 'model_unavailable' });
    await app.close();
  });

  it('a connection that never got there is 502', async () => {
    const app = makeApp({ cryAnalyze: async () => { throw new Error('connect ECONNREFUSED'); } });
    const res = await analyse(app);
    expect(res.statusCode).toBe(502);
    expect(res.json().error).toBe('cry_upstream_unavailable');
    await app.close();
  });

  it('audio the classifier could not read is 400, not "the service is down"', async () => {
    const app = makeApp({ cryAnalyze: async () => { throw new CryUpstreamError(400); } });
    const res = await analyse(app);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('cry_audio_unreadable');
    await app.close();
  });

  it('the success path is untouched', async () => {
    const app = makeApp({ cryAnalyze: async () => ({ status: 'success', primary_reason: 'hungry', confidence: 0.84 }) });
    const res = await analyse(app);
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().primary_reason).toBe('hungry');
    await app.close();
  });

  it('with no forwarder wired at all it is still 503', async () => {
    const app = makeApp({});
    const res = await analyse(app);
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('cry_service_unavailable');
    await app.close();
  });
});

describe('GET /cry/availability', () => {
  it('reports false, without any audio, when the model is not loaded', async () => {
    const analyzer = vi.fn(async () => ({}));
    const app = makeApp({ cryAnalyze: analyzer, cryAvailable: async () => false });
    const res = await availability(app);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ available: false, reason: 'model_unavailable' });
    // The whole point: the phone learns this WITHOUT uploading a recording.
    expect(analyzer).not.toHaveBeenCalled();
    await app.close();
  });

  it('reports true when the classifier has a model', async () => {
    const app = makeApp({ cryAnalyze: async () => ({}), cryAvailable: async () => true });
    expect((await availability(app)).json()).toEqual({ available: true, reason: null });
    await app.close();
  });

  it('a probe we could not send is 502, not "unavailable"', async () => {
    // Flattening this into { available: false } would make the app latch
    // "permanently unavailable" onto a lift with no signal.
    const app = makeApp({ cryAnalyze: async () => ({}), cryAvailable: async () => { throw new Error('offline'); } });
    const res = await availability(app);
    expect(res.statusCode).toBe(502);
    expect(res.json().error).toBe('cry_upstream_unavailable');
    await app.close();
  });

  it('says false when the feature is not wired in this deployment', async () => {
    const app = makeApp({});
    expect((await availability(app)).json()).toEqual({ available: false, reason: 'not_configured' });
    await app.close();
  });

  it('a signed-out caller cannot probe either', async () => {
    const app = makeApp({ cryAnalyze: async () => ({}), cryAvailable: async () => true, signedIn: false });
    expect((await availability(app)).statusCode).toBe(401);
    await app.close();
  });
});
