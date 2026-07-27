/**
 * Photo → appointment: POST /appointments/extract authenticates the caller,
 * hands the image to the injected extractor, and returns the structured
 * appointment. A missing extractor 503s; a bad media type 400s; upstream failure
 * is a clean 502. Separately, sanitizeAppointment accepts a date/time only in the
 * strict shapes the app can parse, and drops anything else.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { sanitizeAppointment, type ExtractedAppointment, type AppointmentExtractor } from '../ai/appointmentVision';

const APPT: ExtractedAppointment = {
  title: 'Приём гинеколога', date: '2026-08-14', time: '10:30', place: 'Поликлиника №5, каб. 210', note: 'талон',
};

function makeApp(opts: { authed?: boolean; extract?: AppointmentExtractor | undefined } = {}): FastifyInstance {
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
      extractAppointment: extract,
    },
    { logger: false },
  );
}

const B64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 5, 6, 7, 8]).toString('base64');
const payload = (over: Record<string, unknown> = {}) => ({ imageBase64: B64, mediaType: 'image/jpeg', ...over });

describe('POST /appointments/extract', () => {
  it('reads the photo and returns the structured appointment', async () => {
    let seenType = '';
    let seenB64 = '';
    const app = makeApp({ extract: async (b64, mediaType) => { seenB64 = b64; seenType = mediaType; return APPT; } });
    const res = await app.inject({ method: 'POST', url: '/appointments/extract', payload: payload() });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual(APPT);
    expect(seenType).toBe('image/jpeg');
    expect(seenB64).toBe(B64);
    await app.close();
  });

  it('refuses an unauthenticated caller', async () => {
    const app = makeApp({ authed: false, extract: async () => APPT });
    const res = await app.inject({ method: 'POST', url: '/appointments/extract', payload: payload() });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('503s when no vision model is configured', async () => {
    const app = makeApp({ extract: undefined });
    const res = await app.inject({ method: 'POST', url: '/appointments/extract', payload: payload() });
    expect(res.statusCode).toBe(503);
    await app.close();
  });

  it('400s an unsupported media type', async () => {
    const app = makeApp({ extract: async () => APPT });
    const res = await app.inject({ method: 'POST', url: '/appointments/extract', payload: payload({ mediaType: 'image/gif' }) });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('surfaces an upstream failure as 502', async () => {
    const app = makeApp({ extract: async () => { throw new Error('vision down'); } });
    const res = await app.inject({ method: 'POST', url: '/appointments/extract', payload: payload() });
    expect(res.statusCode).toBe(502);
    await app.close();
  });
});

describe('sanitizeAppointment', () => {
  it('keeps a well-formed appointment, trimming text', () => {
    const a = sanitizeAppointment({ title: '  Приём терапевта ', date: '2026-08-14', time: '09:05', place: ' каб. 12 ', note: 'слип' });
    expect(a).toEqual({ title: 'Приём терапевта', date: '2026-08-14', time: '09:05', place: 'каб. 12', note: 'слип' });
  });

  it('drops a date/time that is not in the strict, parseable shape', () => {
    expect(sanitizeAppointment({ date: '14.08.2026' }).date).toBeNull(); // dd.mm.yyyy, not ISO
    expect(sanitizeAppointment({ date: '2026-13-40' }).date).toBeNull(); // matches regex but not a real date
    expect(sanitizeAppointment({ date: '2026-08-14' }).date).toBe('2026-08-14');
    expect(sanitizeAppointment({ time: '9:5' }).time).toBeNull(); // not zero-padded HH:MM
    expect(sanitizeAppointment({ time: '25:00' }).time).toBeNull(); // out of range
    expect(sanitizeAppointment({ time: '23:59' }).time).toBe('23:59');
  });
});
