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

  // Granting needs the `orders` capability, not an owner login.
  //
  // This used to be admin-only, and the reason was sound — it gives away a
  // 40 000 ₸ course. But the whole point of granting by hand is the WhatsApp
  // order paid on delivery with no row in shop_orders, and that is the
  // operator's job every day. Admin-only meant they asked the owner or the
  // owner's password got shared, which is worse than either. What actually
  // bounds it is the capability plus the audit row naming who granted it.
  //
  // A warehouse hand still cannot: they have `stock` and nothing else.
  it('not a warehouse account — this gives away a 40 000 ₸ course', async () => {
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '77011112233', displayName: 'Айгерім', role: 'warehouse', password: 'nurse-password' },
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
    titleKk: 'Үйдегі алғашқы күндер',
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

  it('can be edited, and taken down by unpublishing rather than deleting', async () => {
    const id = (await saveLesson(lesson())).json().id;
    await saveLesson(lesson({ id, titleRu: 'Переименовано' }));
    await grant(MY_PHONE);
    expect((await asApp()).json().lessons[0].titleRu).toBe('Переименовано');

    // Published: deleting it is refused. Customers paid for this course, and a
    // lesson vanishing from it mid-week is a refund conversation.
    const refused = await app.inject({
      method: 'DELETE', url: `/admin/course/lessons/${id}`, headers: { cookie },
    });
    expect(refused.statusCode).toBe(409);
    expect(refused.json().error).toBe('has_history');
    expect((await asApp()).json().lessons).toHaveLength(1);

    // Unpublishing is what somebody actually wants, and it is reversible.
    await saveLesson(lesson({ id, titleRu: 'Переименовано', published: false }));
    expect((await asApp()).json().lessons).toEqual([]);

    // A draft nobody has watched has no history, so it can go for good.
    const gone = await app.inject({
      method: 'DELETE', url: `/admin/course/lessons/${id}`, headers: { cookie },
    });
    expect(gone.statusCode, gone.body).toBe(200);
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

  /// Where she got to.
  ///
  /// A thirty-lesson course with no memory of any of it is a course nobody
  /// finishes: she closes the app in the middle of lesson 7 and comes back to
  /// an undifferentiated list. Progress is keyed by PHONE, like the
  /// entitlement — a reinstall or a new device signs in with the same number
  /// and finds its place.
  describe('how far she got', () => {
    const save = (body: Record<string, unknown>) =>
      app.inject({ method: 'POST', url: '/course/progress', payload: body as never });

    const lessonId = async () => {
      const id = (await saveLesson(lesson())).json().id;
      await grant(MY_PHONE);
      return id as string;
    };

    it('comes back with the lessons, in the same request', async () => {
      // Two round trips would paint every lesson unwatched first, which is the
      // exact thing this exists to stop.
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 125 });

      const body = (await asApp()).json();
      expect(body.progress).toHaveLength(1);
      expect(body.progress[0].lessonId).toBe(id);
      expect(body.progress[0].positionSeconds).toBe(125);
      expect(body.progress[0].completed).toBe(false);
    });

    it('never moves her position backwards', async () => {
      // The player reports 0 while it is still loading. One stray beat of that
      // would throw away twenty minutes of watching.
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 1200 });
      await save({ lessonId: id, positionSeconds: 0 });

      expect((await asApp()).json().progress[0].positionSeconds).toBe(1200);
    });

    it('never un-finishes a finished lesson', async () => {
      // Watched is a fact about the past. Reopening it to check something must
      // not take the tick away.
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 600, completed: true });
      await save({ lessonId: id, positionSeconds: 5, completed: false });

      expect((await asApp()).json().progress[0].completed).toBe(true);
    });

    it('keeps a duration it already knows when the player does not report one', async () => {
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 10, durationSeconds: 900 });
      await save({ lessonId: id, positionSeconds: 20 });

      expect((await asApp()).json().progress[0].durationSeconds).toBe(900);
    });

    it('is refused to somebody who has not bought the course', async () => {
      // It is a write keyed by phone. Ungated, any account could write rows
      // against lessons it cannot even see.
      const id = (await saveLesson(lesson())).json().id;
      expect((await save({ lessonId: id, positionSeconds: 10 })).statusCode).toBe(403);
    });

    it('refuses nonsense rather than storing it', async () => {
      const id = await lessonId();
      expect((await save({ lessonId: id, positionSeconds: -5 })).statusCode).toBe(400);
      expect((await save({ lessonId: id, positionSeconds: 99999999 })).statusCode).toBe(400);
      // A lesson id from an older app that is not a UUID: the column is one, so
      // this must be a 400 and never a 500 from Postgres.
      expect((await save({ lessonId: 'lesson-3', positionSeconds: 10 })).statusCode).toBe(400);
    });

    it('is what stops the lesson being deleted at all', async () => {
      // This used to delete the lesson through the route and assert her
      // progress cascaded away with it. The cascade is real and still tested
      // below — but it is the REASON the route now refuses. Her rows point at
      // this id, so removing the lesson takes away a place she got to, and her
      // "6 of 12 completed" quietly becomes 5 of 11.
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 60 });
      // Unpublish first, to isolate the watch-history rule from the
      // published rule — otherwise this passes for the wrong reason.
      await saveLesson(lesson({ id, published: false }));

      const res = await app.inject({
        method: 'DELETE', url: `/admin/course/lessons/${id}`, headers: { cookie },
      });
      expect(res.statusCode).toBe(409);
      expect(res.json()).toMatchObject({ error: 'has_history', published: false, watchers: 1 });
      expect(res.json().message).toContain('прогресс');
    });

    it('cascades when a lesson really is removed', async () => {
      // The rule above is enforced at the route. The storage layer still has to
      // cascade, or the day somebody deletes a lesson by hand in psql an orphan
      // row keeps counting towards a "12 started" for a lesson that is gone.
      const id = await lessonId();
      await save({ lessonId: id, positionSeconds: 60 });
      await repo.deleteCourseLesson(id);
      expect((await asApp()).json().progress).toEqual([]);
    });

    it('tells the back office who is actually watching', async () => {
      // Access answers "did she pay". This answers "is she watching it" — the
      // question that decides whether the комплект's premium delivers anything.
      const one = (await saveLesson(lesson({ titleRu: 'Первый', sort: 10 }))).json().id;
      const two = (await saveLesson(lesson({ titleRu: 'Второй', sort: 20 }))).json().id;
      await grant(MY_PHONE);
      await save({ lessonId: one, positionSeconds: 900, completed: true });
      await save({ lessonId: two, positionSeconds: 30 });

      const res = await app.inject({
        method: 'GET', url: '/admin/course/progress', headers: { cookie },
      });
      expect(res.statusCode).toBe(200);
      const rows = res.json().progress;
      expect(rows).toHaveLength(1);
      expect(rows[0].phone).toBe('77001112233');
      expect(rows[0].started).toBe(2);
      expect(rows[0].completed).toBe(1);
      expect(rows[0].lastLessonTitle).toBe('Второй');
    });

    it('does not hand that list to anyone without a session', async () => {
      expect((await app.inject({ method: 'GET', url: '/admin/course/progress' })).statusCode)
        .toBe(401);
    });
  });
});
