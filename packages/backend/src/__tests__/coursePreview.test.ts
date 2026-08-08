/**
 * Screen 34 — «Курс · без комплекта».
 *
 * The locked screen was one card asserting the course exists. Titles are
 * evidence where «двенадцать уроков» is only a claim, so the list is now shown
 * to somebody who has not bought.
 *
 * The test that matters is the one that proves the list does not ship the
 * thing it is charging for.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { FREE_LESSONS, isFreeLesson, previewLessons } from '../course/preview';
import type { CourseLesson, Repository } from '../db/repository';

const lesson = (n: number, over: Partial<CourseLesson> = {}): CourseLesson => ({
  id: `l${n}`,
  course: 'mama',
  titleRu: `Урок ${n}`,
  titleKk: null,
  youtubeUrl: `https://youtu.be/vid${n}`,
  summaryRu: null,
  summaryKk: null,
  sort: n,
  published: true,
  createdAt: `2026-08-0${n}T00:00:00.000Z`,
  ...over,
});

describe('the preview list', () => {
  it('gives away exactly one lesson', () => {
    // Enough to judge whether the teaching is any good — the only question a
    // preview can honestly answer — and not enough to be the course.
    expect(FREE_LESSONS).toBe(1);
    const p = previewLessons([lesson(1), lesson(2), lesson(3)]);
    expect(p.filter((x) => x.free)).toHaveLength(1);
    expect(p[0].free).toBe(true);
  });

  it('never carries the video of a locked lesson', () => {
    // A paywall that ships what it is paywalling is a decoration. The key is
    // ABSENT rather than empty, so a client cannot treat '' as a URL and a
    // reader of the JSON can see at a glance that nothing leaked.
    const p = previewLessons([lesson(1), lesson(2), lesson(3)]);
    expect(p[0].youtubeUrl).toBe('https://youtu.be/vid1');
    for (const locked of p.slice(1)) {
      expect(locked.free).toBe(false);
      expect('youtubeUrl' in locked).toBe(false);
    }
    // And nothing anywhere in the serialised payload.
    expect(JSON.stringify(p)).not.toContain('vid2');
    expect(JSON.stringify(p)).not.toContain('vid3');
  });

  it('still shows the titles, which are the whole point', () => {
    const p = previewLessons([lesson(1), lesson(2)]);
    expect(p.map((x) => x.titleRu)).toEqual(['Урок 1', 'Урок 2']);
  });

  it('decides "first" by sort order, not by array order', () => {
    // "The first lesson" has to mean the first one SHE sees. Trusting the
    // caller's ordering would unlock whichever happened to be at index 0.
    const p = previewLessons([lesson(3), lesson(1), lesson(2)]);
    expect(p[0].titleRu).toBe('Урок 1');
    expect(p[0].free).toBe(true);
    expect(p.find((x) => x.titleRu === 'Урок 3')?.free).toBe(false);
  });

  it('answers the player the same way it answered the list', () => {
    // The guard the play route needs: a client holding an id from an older
    // response must not be able to play a lesson that is now locked.
    const all = [lesson(3), lesson(1), lesson(2)];
    expect(isFreeLesson(all, 'l1')).toBe(true);
    expect(isFreeLesson(all, 'l2')).toBe(false);
    expect(isFreeLesson(all, 'nonexistent')).toBe(false);
  });

  it('copes with an empty course', () => {
    expect(previewLessons([])).toEqual([]);
  });
});

// ---------------------------------------------------------------------------

let app: FastifyInstance;
let repo: Repository;

beforeEach(() => {
  repo = createMemoryRepository();
  app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'owner' }),
    },
    { logger: false },
  );
});

describe('GET /course/lessons without an entitlement', () => {
  it('sends the titles and exactly one playable video', async () => {
    await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Айгерім', phone: '+7 707 345 22 44' },
    });
    for (const n of [1, 2, 3]) {
      await app.inject({
        method: 'PUT', url: '/admin/course/lessons',
        payload: {
          titleRu: `Урок ${n}`,
          // Both languages. The CMS refuses to publish without the Kazakh
          // title — «ничего не уходит в одном языке» — and a fixture that
          // omitted it silently created nothing.
          titleKk: `Сабақ ${n}`,
          youtubeUrl: `https://www.youtube.com/watch?v=abcdefghij${n}`,
          sort: n, published: true,
        },
      });
    }

    const b = (await app.inject({ method: 'GET', url: '/course/lessons' })).json();
    expect(b.entitled).toBe(false);
    expect(b.preview).toHaveLength(3);
    expect(b.preview[0].free).toBe(true);
    expect(b.freeLessons).toBe(1);

    // The locked videos are nowhere in the response.
    const raw = JSON.stringify(b);
    expect(raw).toContain('abcdefghij1');
    expect(raw).not.toContain('abcdefghij2');
    expect(raw).not.toContain('abcdefghij3');
    await app.close();
  });

  it('is still an honest empty when the course has no lessons', async () => {
    await app.inject({
      method: 'PUT', url: '/profile',
      payload: { displayName: 'Айгерім', phone: '+7 707 345 22 44' },
    });
    const b = (await app.inject({ method: 'GET', url: '/course/lessons' })).json();
    expect(b.entitled).toBe(false);
    expect(b.preview).toEqual([]);
    await app.close();
  });
});
