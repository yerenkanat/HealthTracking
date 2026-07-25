/**
 * Photo → vitals: POST /vitals/extract authenticates the caller, hands the image
 * to the injected vision extractor, and returns the structured reading. A missing
 * extractor (no API key) 503s; a wrong media type 415s; an empty body 400s; an
 * upstream failure surfaces as a clean 502. Separately, sanitizeVitals drops any
 * value the model reports outside the app's plausibility ranges.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { sanitizeVitals, type ExtractedVitals, type VitalsExtractor } from '../ai/vitalsVision';

const READING: ExtractedVitals = {
  systolic: 118, diastolic: 76, heartRate: 72, spo2: 98, temperature: 36.6, glucose: 5.4, note: 'глюкометр',
};

function makeApp(opts: { authed?: boolean; extract?: VitalsExtractor | undefined } = {}): FastifyInstance {
  const { authed = true, extract } = opts;
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => (authed ? { userId: 'u1' } : null),
      authAdmin: async () => null,
      extractVitals: extract,
    },
    { logger: false },
  );
}

const B64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]).toString('base64'); // stand-in JPEG
const payload = (over: Record<string, unknown> = {}) => ({ imageBase64: B64, mediaType: 'image/jpeg', ...over });

describe('POST /vitals/extract', () => {
  it('reads the photo and returns the structured vitals', async () => {
    let seenType = '';
    let seenB64 = '';
    const app = makeApp({
      extract: async (b64, mediaType) => { seenB64 = b64; seenType = mediaType; return READING; },
    });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload() });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(READING);
    expect(seenType).toBe('image/jpeg');
    expect(seenB64).toBe(B64); // handed the image through as base64
    await app.close();
  });

  it('refuses an unauthenticated caller', async () => {
    const app = makeApp({ authed: false, extract: async () => READING });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload() });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('503s when no vision model is configured', async () => {
    const app = makeApp({ extract: undefined });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload() });
    expect(res.statusCode).toBe(503);
    await app.close();
  });

  it('400s an unsupported media type', async () => {
    const app = makeApp({ extract: async () => READING });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload({ mediaType: 'image/gif' }) });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('400s an empty image', async () => {
    const app = makeApp({ extract: async () => READING });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload({ imageBase64: '' }) });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('surfaces an upstream failure as 502', async () => {
    const app = makeApp({ extract: async () => { throw new Error('vision down'); } });
    const res = await app.inject({ method: 'POST', url: '/vitals/extract', payload: payload() });
    expect(res.statusCode).toBe(502);
    await app.close();
  });
});

describe('sanitizeVitals', () => {
  it('passes plausible values through, rounding sensibly', () => {
    const v = sanitizeVitals({ systolic: 118, diastolic: 76, heartRate: 72, spo2: 98, temperature: 36.65, glucose: 5.44, note: 'ok' });
    expect(v).toEqual({ systolic: 118, diastolic: 76, heartRate: 72, spo2: 98, temperature: 36.7, glucose: 5.4, note: 'ok' });
  });

  it('drops values outside the app plausibility ranges', () => {
    const v = sanitizeVitals({ systolic: 1200, diastolic: 76, heartRate: 0, spo2: 130, temperature: 3.6, glucose: 500, note: null });
    expect(v).toEqual({ systolic: null, diastolic: 76, heartRate: null, spo2: null, temperature: null, glucose: null, note: null });
  });

  it('ignores non-numeric fields and truncates a long note', () => {
    const v = sanitizeVitals({ glucose: 'five' as unknown as number, note: 'x'.repeat(500) });
    expect(v.glucose).toBeNull();
    expect(v.systolic).toBeNull();
    expect(v.note).toHaveLength(160);
  });
});
