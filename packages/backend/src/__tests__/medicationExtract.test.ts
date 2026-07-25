/**
 * Photo → medication: POST /medications/extract authenticates the caller, hands
 * the image to the injected extractor, and returns the structured medication. A
 * missing extractor 503s; a bad media type or empty image 400s; upstream failure
 * is a clean 502. Separately, sanitizeMedication trims text and clamps the
 * doses-per-day into the app's 1..6 range.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { sanitizeMedication, type ExtractedMedication, type MedicationExtractor } from '../ai/medicationVision';

const MED: ExtractedMedication = { name: 'Фолиевая кислота', dose: '400 мкг', perDay: 1, note: 'рецепт' };

function makeApp(opts: { authed?: boolean; extract?: MedicationExtractor | undefined } = {}): FastifyInstance {
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
      extractMedication: extract,
    },
    { logger: false },
  );
}

const B64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]).toString('base64');
const payload = (over: Record<string, unknown> = {}) => ({ imageBase64: B64, mediaType: 'image/jpeg', ...over });

describe('POST /medications/extract', () => {
  it('reads the photo and returns the structured medication', async () => {
    let seenType = '';
    let seenB64 = '';
    const app = makeApp({ extract: async (b64, mediaType) => { seenB64 = b64; seenType = mediaType; return MED; } });
    const res = await app.inject({ method: 'POST', url: '/medications/extract', payload: payload() });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(MED);
    expect(seenType).toBe('image/jpeg');
    expect(seenB64).toBe(B64);
    await app.close();
  });

  it('refuses an unauthenticated caller', async () => {
    const app = makeApp({ authed: false, extract: async () => MED });
    const res = await app.inject({ method: 'POST', url: '/medications/extract', payload: payload() });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('503s when no vision model is configured', async () => {
    const app = makeApp({ extract: undefined });
    const res = await app.inject({ method: 'POST', url: '/medications/extract', payload: payload() });
    expect(res.statusCode).toBe(503);
    await app.close();
  });

  it('400s an unsupported media type', async () => {
    const app = makeApp({ extract: async () => MED });
    const res = await app.inject({ method: 'POST', url: '/medications/extract', payload: payload({ mediaType: 'image/gif' }) });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('surfaces an upstream failure as 502', async () => {
    const app = makeApp({ extract: async () => { throw new Error('vision down'); } });
    const res = await app.inject({ method: 'POST', url: '/medications/extract', payload: payload() });
    expect(res.statusCode).toBe(502);
    await app.close();
  });
});

describe('sanitizeMedication', () => {
  it('keeps a plausible medication, trimming whitespace', () => {
    const m = sanitizeMedication({ name: '  Магний B6 ', dose: ' 2 таблетки ', perDay: 2, note: 'коробка' });
    expect(m).toEqual({ name: 'Магний B6', dose: '2 таблетки', perDay: 2, note: 'коробка' });
  });

  it('clamps doses-per-day into 1..6 and drops empty/non-string text', () => {
    expect(sanitizeMedication({ perDay: 99, name: '', dose: '   ', note: null }).perDay).toBe(6);
    expect(sanitizeMedication({ perDay: 0, name: 'X' }).perDay).toBe(1);
    expect(sanitizeMedication({ perDay: 'twice' as unknown as number }).perDay).toBeNull();
    const blank = sanitizeMedication({ name: '', dose: '   ' });
    expect(blank.name).toBeNull();
    expect(blank.dose).toBeNull();
  });
});
