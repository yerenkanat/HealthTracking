/**
 * Frame 06 «Маркетинг» → screen 39 «Центр уведомлений», driven end to end.
 *
 * The unit tests next door can prove [matchesSegment] and [validateSegment]
 * answer correctly and still leave this feature broken in the only way that
 * costs anything: a message written in the back office that never reaches a
 * phone, or reaches the same phone twice. So every assertion here goes over
 * HTTP against the REAL memory repository, and the ones that matter read the
 * result back from the other end — `GET /announcements`, as she sees it.
 *
 * The three rules the whole feature rests on:
 *
 *   1. «Не чаще раза в неделю», ACROSS broadcasts. Two campaigns published on
 *      the same afternoon are the case it exists for.
 *   2. Publication needs the Kazakh half — the content editor's own rule.
 *   3. A segment may name language, срок and детский возраст, and NOTHING from
 *      the health record.
 *
 * There is a fourth, and it is the reason the counts are asserted rather than
 * the status codes: the panel must print «доставлено» and «пропущено» as two
 * numbers. A single «отправлено 40» over an audience entirely inside the gap
 * is the confident wrong number this screen must never show.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';
import { BROADCAST_MIN_GAP_DAYS } from '../admin/broadcasts';

/** Pregnant, Russian. Also the demo account, so the fixture is the whole world. */
const MAMA_RU = DEMO_USER;
/** Pregnant, Kazakh. */
const MAMA_KK = '22222222-2222-2222-2222-222222222222';
/** Not pregnant; one baby of four months. */
const MAMA_BABY = '33333333-3333-3333-3333-333333333333';

const day = (n: number) => new Date(Date.now() + n * 86_400_000).toISOString().slice(0, 10);

let repo: Repository;
let app: FastifyInstance;
let cookie: string;
/** Every push the publish route handed to the notifier. */
let pushed: Array<{ userIds: string[]; id: string; ru: { title: string; body: string }; kk: { title: string; body: string } }>;

function profileFor(locale: string, dueDate: string | null) {
  return {
    displayName: 'Мама', dueDate, locale,
    birthDate: null, city: null, address: null, doctorPhone: null,
    avgCycleLength: null, avgPeriodLength: null,
  };
}

/**
 * A server whose signed-in user is whoever the `x-test-user` header names.
 *
 * The app half of this feature is user-scoped, and a fixture that always
 * answers DEMO_USER cannot tell «she received it» from «somebody received it»
 * — which is the exact confusion `broadcast_deliveries` exists to prevent.
 */
function build(role: string | null = null): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async (req: FastifyRequest) => ({
        userId: String(req.headers['x-test-user'] ?? MAMA_RU),
      }),
      authAdmin: role
        ? async () => ({ staffId: 's-limited', role: role as 'warehouse' })
        : async (req) => {
          const token = readSessionCookie(req.headers.cookie);
          if (!token) return null;
          return repo.staffBySessionToken(hashToken(token));
        },
      notifyBroadcast: async (userIds, message) => void pushed.push({ userIds, ...message }),
    },
    { logger: false },
  );
}

beforeEach(async () => {
  repo = createMemoryRepository();
  pushed = [];

  // The fake seeds the demo account with seven children so the «Дети»
  // dashboard has a distribution to draw. Their birthdays are FIXED dates, so
  // «мамы детей до года» would answer differently in six months' time and this
  // file would start failing on a Tuesday for no reason anybody could see.
  // Cleared, so the population below is the whole world.
  for (const c of await repo.listChildren(MAMA_RU)) await repo.deleteChild(c.id);

  // The population, written through the same methods the app writes them with,
  // so the audience is assembled from the columns the schema really has.
  await repo.upsertProfile(MAMA_RU, profileFor('ru-KZ', day(60)));
  await repo.upsertProfile(MAMA_KK, profileFor('kk', day(90)));
  await repo.upsertProfile(MAMA_BABY, profileFor('ru-KZ', null));
  await repo.upsertChild(MAMA_BABY, {
    id: 'child-1', name: 'Алуа', gender: 'girl', dateOfBirth: day(-120),
  });

  app = build();
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(res.statusCode, 'the staff account could not sign in').toBe(200);
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const staff = (method: 'GET' | 'POST' | 'PUT', url: string, payload?: unknown) =>
  app.inject({ method, url, payload: payload as never, headers: { cookie } });

const asUser = (userId: string) =>
  app.inject({ method: 'GET', url: '/announcements', headers: { 'x-test-user': userId } });

/** A complete, publishable draft. */
function draft(id: string, over: Record<string, unknown> = {}) {
  return {
    id,
    titleRu: 'Второй скрининг', bodyRu: 'Окно 18–21 неделя — запишитесь заранее.',
    titleKk: 'Екінші скрининг', bodyKk: '18–21 апта — алдын ала жазылыңыз.',
    segment: { audience: 'pregnant' },
    ...over,
  };
}

const list = async () =>
  (await staff('GET', '/admin/broadcasts')).json().broadcasts as Array<Record<string, unknown>>;

describe('a draft is stored and read back', () => {
  it('round-trips through the panel\'s own routes', async () => {
    expect(await list()).toEqual([]);

    const created = await staff('POST', '/admin/broadcasts', draft('bc-1'));
    expect(created.statusCode).toBe(201);

    const [row] = await list();
    expect(row.titleRu).toBe('Второй скрининг');
    expect(row.titleKk).toBe('Екінші скрининг');
    expect(row.segment).toEqual({ audience: 'pregnant' });
    expect(row.status).toBe('draft');
    // Nothing has gone out, and the column that says so is the ledger's.
    expect(row.delivered).toBe(0);
    expect(row.publishedAt).toBeNull();
    expect(pushed).toEqual([]);
  });

  it('an edit is a PUT, and re-creating the same id is refused rather than silently overwriting', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    const again = await staff('POST', '/admin/broadcasts', draft('bc-1', { titleRu: 'Другое' }));
    expect(again.statusCode).toBe(409);
    expect((await list())[0].titleRu).toBe('Второй скрининг');

    const edited = await staff('PUT', '/admin/broadcasts/bc-1', draft('bc-1', { titleRu: 'Другое' }));
    expect(edited.statusCode).toBe(200);
    expect((await list())[0].titleRu).toBe('Другое');
  });
});

describe('«не чаще раза в неделю»', () => {
  it('publishing twice inside seven days delivers to a mother once', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    const first = (await staff('POST', '/admin/broadcasts/bc-1/publish')).json();
    // Two pregnant women in the fixture; the mother of a baby is not one.
    expect(first).toMatchObject({ matched: 2, excluded: 0, delivered: 2 });

    // A different broadcast — the gap is ACROSS them, which is the whole point.
    await staff('POST', '/admin/broadcasts', draft('bc-2', { titleRu: 'Ещё раз про скрининг' }));
    const second = (await staff('POST', '/admin/broadcasts/bc-2/publish')).json();
    expect(second).toMatchObject({ matched: 2, excluded: 2, delivered: 0 });
    expect(second.minGapDays).toBe(BROADCAST_MIN_GAP_DAYS);

    // And the number the panel prints is BOTH, so «ушло 0 из 2» is sayable.
    const rows = await list();
    expect(rows.find((r) => r.id === 'bc-1')!.delivered).toBe(2);
    expect(rows.find((r) => r.id === 'bc-2')!.delivered).toBe(0);

    // The end that matters: her phone. One message, not two.
    const mine = (await asUser(MAMA_RU)).json().announcements as Array<{ id: string }>;
    expect(mine.map((a) => a.id)).toEqual(['bc-1']);
  });

  it('re-publishing the SAME broadcast is refused outright, not merely deduplicated', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    const again = await staff('POST', '/admin/broadcasts/bc-1/publish');
    expect(again.statusCode).toBe(409);
    expect(String(again.json().message)).toContain('уже отправлена');
    expect((await asUser(MAMA_RU)).json().announcements).toHaveLength(1);
  });

  it('a published broadcast can no longer be edited — the text is already on a phone', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    const edit = await staff('PUT', '/admin/broadcasts/bc-1', draft('bc-1', { titleRu: 'Подменённый текст' }));
    expect(edit.statusCode).toBe(409);
    expect((await list())[0].titleRu).toBe('Второй скрининг');
  });

  it('the preview says how many would be skipped, before anybody presses send', async () => {
    const seg = encodeURIComponent(JSON.stringify({ audience: 'pregnant' }));
    const before = (await staff('GET', `/admin/broadcasts/new/preview?segment=${seg}`)).json();
    expect(before).toMatchObject({ matched: 2, excluded: 0, deliverable: 2 });
    expect(before.describe).toBe('Беременные');

    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');

    const after = (await staff('GET', `/admin/broadcasts/new/preview?segment=${seg}`)).json();
    expect(after).toMatchObject({ matched: 2, excluded: 2, deliverable: 0 });
  });
});

describe('the bilingual gate', () => {
  it('refuses to publish without the Kazakh half and names what is missing', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1', { titleKk: '', bodyKk: '' }));
    const res = await staff('POST', '/admin/broadcasts/bc-1/publish');
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
    expect(String(res.json().message)).toContain('казахской версии');

    // ...and it is still a draft that reached nobody, rather than a half-sent one.
    expect((await list())[0].status).toBe('draft');
    expect((await asUser(MAMA_RU)).json().announcements).toEqual([]);
    expect(pushed).toEqual([]);
  });

  it('a Kazakh title with no Kazakh body is still refused', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1', { bodyKk: '' }));
    const res = await staff('POST', '/admin/broadcasts/bc-1/publish');
    expect(res.statusCode).toBe(400);
    expect(res.json().problems).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: 'summary' })]),
    );
  });

  it('a draft may legitimately be saved half-translated — the gate is publication', async () => {
    const res = await staff('POST', '/admin/broadcasts', draft('bc-1', { titleKk: null, bodyKk: null }));
    expect(res.statusCode).toBe(201);
    expect((await list())[0].titleKk).toBeNull();
  });
});

describe('a segment may not name the health record', () => {
  it('refuses a blood-pressure rule rather than dropping it', async () => {
    // Dropping it is the dangerous outcome: the row would store `{}`, the
    // panel would show the rule somebody typed, and the message would go to
    // everybody in the country.
    const res = await staff('POST', '/admin/broadcasts', draft('bc-1', { segment: { systolic: '>140' } }));
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('segment_health_forbidden');
    expect(String(res.json().message)).toContain('systolic');
    expect(String(res.json().message)).toContain('показатели здоровья');
    expect(await list()).toEqual([]);
  });

  it('refuses an unsupported non-health field too, and says which', async () => {
    const res = await staff('POST', '/admin/broadcasts', draft('bc-1', { segment: { city: 'Алматы' } }));
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('segment_unsupported_field');
    expect(String(res.json().message)).toContain('city');
    expect(await list()).toEqual([]);
  });

  it('the live recipient counter refuses one as well — the count is where somebody would probe', async () => {
    const seg = encodeURIComponent(JSON.stringify({ glucose: '>7' }));
    const res = await staff('GET', `/admin/broadcasts/new/preview?segment=${seg}`);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('segment_health_forbidden');
  });

  it('an edit cannot smuggle one in either', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    const res = await staff('PUT', '/admin/broadcasts/bc-1', draft('bc-1', { segment: { pulse: 'high' } }));
    expect(res.statusCode).toBe(400);
    expect((await list())[0].segment).toEqual({ audience: 'pregnant' });
  });
});

describe('who the segment actually covers', () => {
  const preview = async (segment: unknown) =>
    (await staff(
      'GET',
      `/admin/broadcasts/new/preview?segment=${encodeURIComponent(JSON.stringify(segment))}`,
    )).json();

  it('counts on the server, from locale, due date and a child\'s birthday', async () => {
    expect(await preview({})).toMatchObject({ matched: 3 });
    expect(await preview({ audience: 'pregnant' })).toMatchObject({ matched: 2 });
    expect(await preview({ audience: 'mothers' })).toMatchObject({ matched: 1 });
    expect(await preview({ audience: 'infants' })).toMatchObject({ matched: 1 });
    expect(await preview({ locale: 'kk' })).toMatchObject({ matched: 1 });
    expect(await preview({ audience: 'pregnant', locale: 'kk' })).toMatchObject({ matched: 1 });
  });

  it('a woman who has only signed up by phone is in «Все» — the audience is users, not profiles', async () => {
    // The pg query starts `FROM users u`; the fake assembled the audience from
    // the profile map, so an account created by sign-in and nothing else was
    // invisible to every test in this file. «Получат сейчас» would have said
    // one number on a dev box and production would have delivered another —
    // and the direction is the bad one: she is skipped in the only
    // implementation the tests run, and written to in the one that ships.
    const her = await repo.createUserWithPhone({ phone: '+77015550101', displayName: 'Жаңа' });
    expect(await preview({})).toMatchObject({ matched: 4 });

    await staff('POST', '/admin/broadcasts', draft('bc-all', { segment: { audience: 'all' } }));
    expect((await staff('POST', '/admin/broadcasts/bc-all/publish')).json())
      .toMatchObject({ matched: 4, delivered: 4 });
    expect((await asUser(her.id)).json().announcements).toHaveLength(1);

    // ...and «Все» only. Nothing is known about her срок or her children, so
    // the narrower segments must not claim her — the SQL says the same, since
    // her `due_date` is NULL and she has no `children` rows.
    expect(await preview({ audience: 'pregnant' })).toMatchObject({ matched: 2 });
    expect(await preview({ audience: 'mothers' })).toMatchObject({ matched: 1 });
    // A locale nobody set is Russian, in both implementations: `shortLocale`
    // here, the CASE in SEGMENT_WHERE there.
    expect(await preview({ locale: 'kk' })).toMatchObject({ matched: 1 });
    expect(await preview({ locale: 'ru' })).toMatchObject({ matched: 3 });
  });

  it('a Kazakh-only broadcast reaches the Kazakh mother and nobody else', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-kk', { segment: { locale: 'kk' } }));
    const res = (await staff('POST', '/admin/broadcasts/bc-kk/publish')).json();
    expect(res).toMatchObject({ matched: 1, delivered: 1 });
    expect((await asUser(MAMA_KK)).json().announcements).toHaveLength(1);
    expect((await asUser(MAMA_RU)).json().announcements).toEqual([]);
  });

  it('an overdue mother is not «беременна» — the database cannot vouch for it', async () => {
    await repo.upsertProfile(MAMA_KK, profileFor('kk', day(-3)));
    expect(await preview({ audience: 'pregnant' })).toMatchObject({ matched: 1 });
  });
});

describe('what reaches her phone', () => {
  it('is scoped to the delivery ledger, not to the segment', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');

    // She was pregnant when it went out. Re-running the segment later must not
    // take a message she already read off her screen.
    await repo.upsertProfile(MAMA_RU, profileFor('ru-KZ', null));
    expect((await asUser(MAMA_RU)).json().announcements).toHaveLength(1);

    // ...and the mother of a baby, who never matched, still has nothing.
    expect((await asUser(MAMA_BABY)).json().announcements).toEqual([]);
  });

  it('carries both languages, so switching the app to Kazakh is not a bug she cannot fix', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    const [a] = (await asUser(MAMA_RU)).json().announcements as Array<Record<string, never>>;
    expect(a).toMatchObject({
      id: 'bc-1',
      ru: { title: 'Второй скрининг', body: 'Окно 18–21 неделя — запишитесь заранее.' },
      kk: { title: 'Екінші скрининг', body: '18–21 апта — алдын ала жазылыңыз.' },
    });
    expect(Date.parse(String((a as unknown as { at: string }).at))).not.toBeNaN();
  });

  it('a draft is invisible to everybody — saving is not sending', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    expect((await asUser(MAMA_RU)).json().announcements).toEqual([]);
    expect((await asUser(MAMA_KK)).json().announcements).toEqual([]);
  });
});

describe('the push, and what happens when it fails', () => {
  it('pushes to exactly the people the ledger accepted', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    expect(pushed).toHaveLength(1);
    expect([...pushed[0].userIds].sort()).toEqual([MAMA_KK, MAMA_RU].sort());
    expect(pushed[0].kk.title).toBe('Екінші скрининг');
  });

  it('a dead push does not turn a delivered broadcast into a failed one, and says so', async () => {
    // The message is in her notification centre either way — reporting «не
    // отправилось» because one token was stale would be a lie about what
    // happened, and reporting nothing would be a different one.
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
        authUser: async (req: FastifyRequest) => ({
          userId: String(req.headers['x-test-user'] ?? MAMA_RU),
        }),
        authAdmin: async (req) => {
          const token = readSessionCookie(req.headers.cookie);
          if (!token) return null;
          return repo.staffBySessionToken(hashToken(token));
        },
        notifyBroadcast: async () => { throw new Error('FCM refused the batch'); },
      },
      { logger: false },
    );
    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
    });
    cookie = String(login.headers['set-cookie'] ?? '').split(';')[0];

    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    const res = await staff('POST', '/admin/broadcasts/bc-1/publish');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ delivered: 2, pushed: false });
    expect((await asUser(MAMA_RU)).json().announcements).toHaveLength(1);
  });
});

describe('the audit trail', () => {
  it('records who sent what, to whom, and how many got it', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    const entries = (await repo.listAudit(50)).entries;
    const actions = entries.map((e) => e.action);
    expect(actions).toContain('broadcast_create');
    expect(actions).toContain('broadcast_publish');
    const publish = entries.find((e) => e.action === 'broadcast_publish')!;
    expect(publish.target).toBe('bc-1');
    expect(String(publish.reason)).toContain('Беременные');
    expect(String(publish.reason)).toContain('доставлено 2 из 2');
  });
});

describe('who may write to forty thousand people', () => {
  it('a role without `content` is refused every one of the four routes', async () => {
    app = build('warehouse');
    for (const [method, url] of [
      ['GET', '/admin/broadcasts'],
      ['POST', '/admin/broadcasts'],
      ['PUT', '/admin/broadcasts/bc-1'],
      ['POST', '/admin/broadcasts/bc-1/publish'],
      ['GET', '/admin/broadcasts/new/preview'],
    ] as const) {
      const res = await app.inject({ method, url, payload: draft('bc-1') as never });
      expect([401, 403], `${method} ${url} let a warehouse hand through`).toContain(res.statusCode);
    }
  });

  it('/announcements needs a session of her own', async () => {
    await staff('POST', '/admin/broadcasts', draft('bc-1'));
    await staff('POST', '/admin/broadcasts/bc-1/publish');
    // A stranger's id resolves to a real session in this fixture and still sees
    // nothing, because the ledger — not the endpoint — decides.
    const res = await asUser('99999999-9999-9999-9999-999999999999');
    expect(res.statusCode).toBe(200);
    expect(res.json().announcements).toEqual([]);
  });
});
