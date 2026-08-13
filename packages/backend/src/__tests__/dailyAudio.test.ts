/**
 * Daily calendar audio end-to-end: an admin uploads a clip for a (track, day,
 * locale); it then streams from the public /audio route, shows up in the API's
 * coverage list and the personalised "today" endpoint's audioUrl, and delete
 * removes it. Auth and content-type guards are checked too.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const STAFF = { staffId: 's1', role: 'admin' as const };
let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

function app(opts: { admin?: boolean; contentApiKey?: string } = {}): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => (opts.admin === false ? null : STAFF),
      contentApiKey: opts.contentApiKey,
    },
    { logger: false },
  );
}

const mp3 = { 'content-type': 'audio/mpeg' };
const clip = Buffer.from([0x49, 0x44, 0x33, 1, 2, 3, 4, 5, 6, 7, 8, 9]); // stand-in MP3 bytes

describe('daily calendar audio', () => {
  it('uploads a clip, streams it back, lists it, and exposes audioUrl in /today', async () => {
    const a = app();
    const up = await a.inject({ method: 'POST', url: '/admin/audio/pregnancy/20/ru?title=Week%2020', headers: mp3, payload: clip });
    expect(up.statusCode).toBe(201);

    // Public stream returns the exact bytes + content type.
    const play = await a.inject({ method: 'GET', url: '/audio/pregnancy/20/ru' });
    expect(play.statusCode).toBe(200);
    expect(play.headers['content-type']).toContain('audio/mpeg');
    expect(play.rawPayload.equals(clip)).toBe(true);

    // Admin coverage list + public API coverage.
    const adminList = (await a.inject({ method: 'GET', url: '/admin/audio?track=pregnancy' })).json().audio;
    expect(adminList).toEqual([expect.objectContaining({ day: 20, locale: 'ru', title: 'Week 20' })]);
    const apiList = (await a.inject({ method: 'GET', url: '/api/v1/audio/pregnancy' })).json();
    expect(apiList.count).toBe(1);
    expect(apiList.audio[0].url).toBe('/audio/pregnancy/20/ru');

    await a.close();
  });

  it("wires the clip into the personalised /today endpoint's audioUrl", async () => {
    const a = app();
    // Find the gestational day for a due date, upload for it, then confirm today links it.
    const today = (await a.inject({ method: 'GET', url: '/api/v1/pregnancy/today?dueDate=2026-12-09&from=2026-07-27&lang=ru' })).json();
    expect(today.audioUrl).toBeNull(); // nothing uploaded yet
    const day = today.day;
    await a.inject({ method: 'POST', url: `/admin/audio/pregnancy/${day}/ru`, headers: mp3, payload: clip });
    const after = (await a.inject({ method: 'GET', url: '/api/v1/pregnancy/today?dueDate=2026-12-09&from=2026-07-27&lang=ru' })).json();
    expect(after.audioUrl).toBe(`/audio/pregnancy/${day}/ru`);
    await a.close();
  });

  it('deletes a clip (then it 404s and leaves the list)', async () => {
    const a = app();
    await a.inject({ method: 'POST', url: '/admin/audio/child/5/kk', headers: mp3, payload: clip });
    expect((await a.inject({ method: 'GET', url: '/audio/child/5/kk' })).statusCode).toBe(200);
    const del = await a.inject({ method: 'DELETE', url: '/admin/audio/child/5/kk' });
    expect(del.statusCode).toBe(200);
    expect((await a.inject({ method: 'GET', url: '/audio/child/5/kk' })).statusCode).toBe(404);
    expect((await a.inject({ method: 'GET', url: '/api/v1/audio/child' })).json().count).toBe(0);
    await a.close();
  });

  it('guards auth, content type, and empty body', async () => {
    expect((await app({ admin: false }).inject({ method: 'POST', url: '/admin/audio/pregnancy/1/ru', headers: mp3, payload: clip })).statusCode).toBe(401);
    expect((await app({ admin: false }).inject({ method: 'DELETE', url: '/admin/audio/pregnancy/1/ru' })).statusCode).toBe(401);
    // wrong media type
    expect((await app().inject({ method: 'POST', url: '/admin/audio/pregnancy/1/ru', headers: { 'content-type': 'text/plain' }, payload: 'x' })).statusCode).toBe(415);
    // bad day / track
    expect((await app().inject({ method: 'POST', url: '/admin/audio/pregnancy/999/ru', headers: mp3, payload: clip })).statusCode).toBe(400);
    expect((await app().inject({ method: 'GET', url: '/audio/nope/1/ru' })).statusCode).toBe(400);
    expect((await app().inject({ method: 'GET', url: '/audio/pregnancy/1/ru' })).statusCode).toBe(404);
  });

  // ---- The app-facing catalogue: GET /audio/:track --------------------------
  //
  // Screen 44's «Все записи · N» and the library behind it. The same JSON has
  // existed at /api/v1/audio/:track since the beginning, but that surface is
  // key-gated for integrators, so the app could not read it and every mother
  // could reach exactly one clip: today's.
  describe('the app-facing catalogue', () => {
    it('answers with no staff session and no API key, while the partner copy stays gated', async () => {
      // Both guards ON: nobody is signed in as staff, and /api/v1 demands a key.
      const a = app({ admin: false, contentApiKey: 'partner-secret' });
      await repo.upsertDailyAudio({ track: 'pregnancy', day: 20, locale: 'ru', title: 'Week 20', mime: 'audio/mpeg', bytes: clip });

      const open = await a.inject({ method: 'GET', url: '/audio/pregnancy' });
      expect(open.statusCode).toBe(200);
      expect(open.json().count).toBe(1);

      // The point of the new route: the one the app could NOT use is still shut.
      expect((await a.inject({ method: 'GET', url: '/api/v1/audio/pregnancy' })).statusCode).toBe(401);
      await a.close();
    });

    it('lists every day of the track, both locales, ordered by day, with a playable url', async () => {
      const a = app();
      for (const [day, locale] of [[30, 'ru'], [7, 'kk'], [7, 'ru']] as const) {
        await a.inject({ method: 'POST', url: `/admin/audio/pregnancy/${day}/${locale}?title=d${day}${locale}`, headers: mp3, payload: clip });
      }
      const body = (await a.inject({ method: 'GET', url: '/audio/pregnancy' })).json();
      expect(body.track).toBe('pregnancy');
      expect(body.count).toBe(3);
      expect(body.audio.map((x: { day: number; locale: string }) => `${x.day}${x.locale}`)).toEqual(['7kk', '7ru', '30ru']);
      // Sizes are real, so a client can warn before pulling a big clip on 3G.
      expect(body.audio[0].size).toBe(clip.length);

      // The url it hands out has to actually stream.
      const first = body.audio[0];
      const play = await a.inject({ method: 'GET', url: first.url });
      expect(play.statusCode).toBe(200);
      expect(play.rawPayload.equals(clip)).toBe(true);
      await a.close();
    });

    it('is empty rather than absent for a track with nothing uploaded, and 400s an unknown track', async () => {
      const a = app();
      // An empty catalogue is a real answer — «записей пока нет» — and the app
      // draws an empty state from it. Only a bad track is an error.
      expect((await a.inject({ method: 'GET', url: '/audio/child' })).json()).toEqual({ track: 'child', count: 0, audio: [] });
      expect((await a.inject({ method: 'GET', url: '/audio/nope' })).statusCode).toBe(400);
      await a.close();
    });

    it('carries no bytes — the list is metadata a phone can hold in memory', async () => {
      const a = app();
      await a.inject({ method: 'POST', url: '/admin/audio/child/3/ru', headers: mp3, payload: clip });
      const raw = (await a.inject({ method: 'GET', url: '/audio/child' })).body;
      expect(raw).not.toContain('bytes');
      expect(raw.length).toBeLessThan(400);
      await a.close();
    });
  });
});
