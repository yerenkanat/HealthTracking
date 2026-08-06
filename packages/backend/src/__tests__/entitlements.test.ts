/**
 * Who can see the Ма!Ма! course.
 *
 * The combo costs 39 000 ₸ against 29 800 for the hardware alone; the
 * difference is the course, presented on the landing as a 40 000 ₸ gift. So the
 * entitlement and the price are the same fact, and getting this wrong either
 * gives away the thing people paid for or withholds it from people who did pay.
 *
 * The join between an order and an account is the PHONE — captured at checkout,
 * used to sign in — so these tests care a lot about a number typed four
 * different ways being one person.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';
import { MAMA_COURSE } from '../routes/entitlements';

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

beforeEach(async () => {
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
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

/** The demo profile's phone, which is what /account/entitlements keys on. */
const MY_PHONE = '+77001112233';

const mine = async () =>
  (await app.inject({ method: 'GET', url: '/account/entitlements' })).json().features;

const grant = (phone: string, note?: string) =>
  app.inject({
    method: 'POST', url: '/admin/entitlements',
    payload: { phone, feature: MAMA_COURSE, note }, headers: { cookie },
  });

describe('the app asks what it owns', () => {
  it('owns nothing until somebody grants it', async () => {
    // The safe direction to fail. A course given away by default is a course
    // nobody needs to buy the combo for.
    expect(await mine()).toEqual([]);
  });

  it('sees the course once it is granted to her number', async () => {
    expect((await grant(MY_PHONE)).statusCode).toBe(200);
    expect(await mine()).toContain(MAMA_COURSE);
  });

  it('loses it again when it is revoked', async () => {
    await grant(MY_PHONE);
    const res = await app.inject({
      method: 'DELETE', url: `/admin/entitlements/${MAMA_COURSE}/77001112233`,
      headers: { cookie },
    });
    expect(res.statusCode).toBe(200);
    expect(await mine()).toEqual([]);
  });

  it('is not somebody else\'s course', async () => {
    await grant('+7 705 999 88 77');
    expect(await mine(), 'a grant to another number unlocked this account').toEqual([]);
  });

  it('refuses to answer at all without a session', async () => {
    const anon = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
    expect((await anon.inject({ method: 'GET', url: '/account/entitlements' })).statusCode).toBe(401);
  });
});

describe('the number is the person', () => {
  it.each([
    ['+7 700 111 22 33', 'as it displays'],
    ['8 700 111 22 33', 'the domestic prefix'],
    ['7700 111 2233', 'spaces anywhere'],
    ['77001112233', 'bare digits'],
  ])('a grant typed %s (%s) reaches the same account', async (typed) => {
    // Orders are taken over WhatsApp and typed by hand. If these were four
    // different customers, the entitlement would be a lottery.
    expect((await grant(typed)).statusCode).toBe(200);
    expect(await mine()).toContain(MAMA_COURSE);
  });

  it('refuses something that is not a phone number', async () => {
    expect((await grant('77')).statusCode).toBe(400);
  });
});

describe('who may grant it', () => {
  it('not an anonymous caller', async () => {
    const res = await app.inject({
      method: 'POST', url: '/admin/entitlements',
      payload: { phone: MY_PHONE, feature: MAMA_COURSE },
    });
    expect(res.statusCode).toBe(401);
    expect(await mine()).toEqual([]);
  });

  it('not a support account — this gives away a 40 000 ₸ course', async () => {
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '77011112233', displayName: 'Айгерім', role: 'support', password: 'nurse-password' },
    });
    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: '77011112233', password: 'nurse-password' },
    });
    const theirs = String(login.headers['set-cookie'] ?? '').split(';')[0];

    const res = await app.inject({
      method: 'POST', url: '/admin/entitlements',
      payload: { phone: MY_PHONE, feature: MAMA_COURSE }, headers: { cookie: theirs },
    });
    expect(res.statusCode).toBe(403);
  });

  it('records who granted it, and keeps that on a re-grant', async () => {
    // Provenance is the point: an unexplained entitlement should be traceable
    // rather than guessed at. Re-granting must not overwrite the first author.
    await grant(MY_PHONE, 'заказ по WhatsApp, оплачено');
    await grant(MY_PHONE, 'второй раз');

    const { entitlements } = (await app.inject({
      method: 'GET', url: '/admin/entitlements', headers: { cookie },
    })).json();
    const row = entitlements.find((e: { phone: string }) => e.phone === '77001112233');
    expect(row.grantedBy).toBeTruthy();
    expect(row.note).toBe('заказ по WhatsApp, оплачено');
  });
});

describe('the course behind the gate', () => {
  const lesson = (over: Record<string, unknown> = {}) => ({
    titleRu: 'Первые дни дома',
    youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
    published: true,
    ...over,
  });

  const saveLesson = (body: Record<string, unknown>) =>
    app.inject({ method: 'PUT', url: '/admin/course/lessons', payload: body as never, headers: { cookie } });

  const asApp = () => app.inject({ method: 'GET', url: '/course/lessons' });

  it('is invisible to somebody who has not bought it', async () => {
    await saveLesson(lesson());
    const res = await asApp();
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.entitled).toBe(false);
    // 200 with an empty list, not 403: the app has to SAY what this is and how
    // to get it. A locked door with a sign sells the combo; one without looks
    // broken.
    expect(body.lessons, 'a paywalled lesson leaked to a non-buyer').toEqual([]);
  });

  it('opens once the combo is granted to her number', async () => {
    await saveLesson(lesson());
    await grant(MY_PHONE);
    const body = (await asApp()).json();
    expect(body.entitled).toBe(true);
    expect(body.lessons).toHaveLength(1);
    expect(body.lessons[0].titleRu).toBe('Первые дни дома');
    expect(body.lessons[0].youtubeUrl).toContain('youtu.be');
  });

  it('never shows a draft, even to a buyer', async () => {
    // A lesson is written over several sittings. Half of one appearing to
    // somebody who paid 39 000 is worse than it not being there yet.
    await saveLesson(lesson({ titleRu: 'Черновик', published: false }));
    await grant(MY_PHONE);
    expect((await asApp()).json().lessons).toEqual([]);
  });

  it('keeps the series in order', async () => {
    await saveLesson(lesson({ titleRu: 'Третий', sort: 30 }));
    await saveLesson(lesson({ titleRu: 'Первый', sort: 10 }));
    await saveLesson(lesson({ titleRu: 'Второй', sort: 20 }));
    await grant(MY_PHONE);
    expect((await asApp()).json().lessons.map((l: { titleRu: string }) => l.titleRu))
      .toEqual(['Первый', 'Второй', 'Третий']);
  });

  it('refuses a link that is not YouTube', async () => {
    // The owner has YouTube. Anything else is a mis-paste that would fail in
    // the app, where nobody can fix it.
    expect((await saveLesson(lesson({ youtubeUrl: 'https://example.com/video.mp4' }))).statusCode).toBe(400);
    expect((await saveLesson(lesson({ youtubeUrl: 'не ссылка' }))).statusCode).toBe(400);
  });

  it('refuses a YouTube link that is not a VIDEO', async () => {
    // The check used to ask only whether the string contained "youtube.com",
    // so a channel page, a playlist and a mistyped path all saved cleanly,
    // published to paying customers, and failed in the app.
    for (const url of [
      'https://www.youtube.com/@anabala',
      'https://www.youtube.com/playlist?list=PL123456',
      'https://www.youtube.com/results?search_query=роды',
      'https://youtu.be/',
      'https://youtu.be/tooshort',
      // The one that matters most: a lookalike host that contains the string.
      'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ',
    ]) {
      expect((await saveLesson(lesson({ youtubeUrl: url }))).statusCode, url).toBe(400);
    }
  });

  it('accepts the shapes a person actually pastes', async () => {
    for (const url of [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90s',
    ]) {
      expect((await saveLesson(lesson({ youtubeUrl: url }))).statusCode, url).toBe(200);
    }
  });

  it('can be edited and removed', async () => {
    const id = (await saveLesson(lesson())).json().id;
    await saveLesson(lesson({ id, titleRu: 'Переименовано' }));
    await grant(MY_PHONE);
    expect((await asApp()).json().lessons[0].titleRu).toBe('Переименовано');

    await app.inject({ method: 'DELETE', url: `/admin/course/lessons/${id}`, headers: { cookie } });
    expect((await asApp()).json().lessons).toEqual([]);
  });

  it('cannot be written by a support account', async () => {
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '77012223344', displayName: 'X', role: 'support', password: 'support-password' },
    });
    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: '77012223344', password: 'support-password' },
    });
    const theirs = String(login.headers['set-cookie'] ?? '').split(';')[0];
    const res = await app.inject({
      method: 'PUT', url: '/admin/course/lessons',
      payload: lesson() as never, headers: { cookie: theirs },
    });
    expect(res.statusCode).toBe(403);
  });
});
