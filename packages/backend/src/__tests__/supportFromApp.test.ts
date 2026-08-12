/**
 * Frame 43 — «Поддержка · оператор», the receiving end of frame 12.
 *
 * The defect this covers: the desk was ONE-WAY. POST /admin/support/:id/reply
 * has written into support_replies and set the ticket to «ждём клиента» since
 * frame 12 shipped — waiting on a customer who had no surface anywhere that
 * could show her the answer. The migration's 'app' channel had never been
 * written by anything.
 *
 * So the assertions here are the JOINS, driven over HTTP end to end: a ticket
 * raised in the app reaching the operator's queue, her answer reaching the app,
 * and the customer's answer landing back in the queue rather than in a status
 * nobody looks at. Unit-level fakes cannot fail on any of those.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer, type ServerDeps } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

/** A second signed-in account, for the authorization tests. */
const OTHER_USER = '22222222-2222-2222-2222-222222222222';

let app: FastifyInstance;
let repo: Repository;
let cookie = '';
/** Every push the panel's reply route asked for. */
let pushes: Array<{ userId: string; subject: string; body: string }> = [];

function makeApp(notify?: ServerDeps['notifySupportReply']) {
  repo = createMemoryRepository();
  pushes = [];
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
      // Which account is calling, so one signed-in woman asking for another's
      // ticket is a case this suite can actually reach.
      authUser: async (req) => ({
        userId: (req.headers['x-test-user'] as string) || DEMO_USER,
      }),
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
      notifySupportReply: notify ?? (async (userId, ticket, body) => {
        pushes.push({ userId, subject: ticket.subject, body });
      }),
    },
    { logger: false },
  );
}

async function signInStaff() {
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(r.statusCode).toBe(200);
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
}

beforeEach(async () => {
  app = makeApp();
  await signInStaff();
});

// ---- the two sides -------------------------------------------------------
const her = (user = DEMO_USER) => ({
  get: (url: string) =>
    app.inject({ method: 'GET', url, headers: { 'x-test-user': user } }),
  post: (url: string, payload: Record<string, unknown>) =>
    app.inject({ method: 'POST', url, headers: { 'x-test-user': user }, payload }),
});
const desk = {
  get: (url: string) => app.inject({ method: 'GET', url, headers: { cookie } }),
  post: (url: string, payload: Record<string, unknown>) =>
    app.inject({ method: 'POST', url, headers: { cookie }, payload }),
  patch: (url: string, payload: Record<string, unknown>) =>
    app.inject({ method: 'PATCH', url, headers: { cookie }, payload }),
};

/** Raise one from the app and hand back its id. */
async function raise(subject = 'Не приходит код', body = 'Жду 10 минут.') {
  const r = await her().post('/support', { subject, body, appContext: 'Приложение: 0.1.0' });
  expect(r.statusCode).toBe(201);
  return r.json().id as string;
}

describe('она пишет из приложения', () => {
  it('lands in the operator queue, on the app channel, under her name', async () => {
    const id = await raise();
    const board = (await desk.get('/admin/support')).json();
    const mine = board.items.find((t: { id: string }) => t.id === id);
    expect(mine).toBeTruthy();
    // «Приложение» — the channel value that had never been written by anything.
    expect(mine.channel).toBe('app');
    // From the PROFILE, not from the request: the name and number are how the
    // operator finds the account, and a client-supplied phone would let anyone
    // file a ticket under somebody else's number.
    const profile = await repo.getProfile(DEMO_USER);
    expect(mine.customerName).toBe(profile!.displayName);
    expect(mine.phone).toBe(profile!.phone);
    await app.close();
  });

  it('carries what the app knew, so nobody asks «какая у вас версия»', async () => {
    const id = await raise();
    const one = (await desk.get(`/admin/support/${id}`)).json();
    expect(one.ticket.appContext).toContain('0.1.0');
    await app.close();
  });

  it('counts as ours to answer the moment it arrives', async () => {
    const before = (await desk.get('/admin/support')).json().waiting;
    await raise();
    expect((await desk.get('/admin/support')).json().waiting).toBe(before + 1);
    await app.close();
  });

  it('refuses an empty message rather than filing a blank ticket', async () => {
    expect((await her().post('/support', { subject: 'x', body: '   ' })).statusCode).toBe(400);
    expect((await her().post('/support', { subject: '  ', body: 'x' })).statusCode).toBe(400);
    await app.close();
  });

  it('refuses an anonymous caller', async () => {
    // authUser is header-driven here, so this proves the guard, not the fake:
    // the route is registered under requireUser and there is no unsigned path.
    const noAuth = buildServer(
      {
        repo: createMemoryRepository(),
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
      },
      { logger: false },
    );
    expect((await noAuth.inject({ method: 'GET', url: '/support' })).statusCode).toBe(401);
    expect((await noAuth.inject({
      method: 'POST', url: '/support', payload: { subject: 'a', body: 'b' },
    })).statusCode).toBe(401);
    await noAuth.close();
    await app.close();
  });
});

describe('оператор отвечает', () => {
  it('the answer is readable IN THE APP, which is the whole point', async () => {
    const id = await raise();
    expect((await desk.post(`/admin/support/${id}/reply`,
      { body: 'Проверила — код уже отправлен повторно.' })).statusCode).toBe(200);

    const mine = (await her().get('/support')).json()
      .tickets.find((t: { id: string }) => t.id === id);
    expect(mine.status).toBe('waiting');
    expect(mine.replies).toHaveLength(1);
    expect(mine.replies[0].author).toBe('staff');
    expect(mine.replies[0].body).toContain('код уже отправлен');
    await app.close();
  });

  it('reaches her phone as a push, or the thread is a screen she never reopens', async () => {
    const id = await raise('Где мой заказ', 'Оплатила вчера.');
    await desk.post(`/admin/support/${id}/reply`, { body: 'Заказ собран, завтра до 18:00.' });
    expect(pushes).toEqual([
      { userId: DEMO_USER, subject: 'Где мой заказ', body: 'Заказ собран, завтра до 18:00.' },
    ]);
    await app.close();
  });

  it('SAVES the reply even when the push cannot be delivered', async () => {
    // No FCM credentials on this box is the normal case, not a failure of the
    // thing the operator did. Telling her «не отправилось» over a reply that is
    // already in the database is how somebody re-sends it three times.
    app = makeApp(async () => { throw new Error('no FCM credentials'); });
    await signInStaff();
    const id = await raise();
    const r = await desk.post(`/admin/support/${id}/reply`, { body: 'Проверяю.' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ ok: true });
    const mine = (await her().get('/support')).json()
      .tickets.find((t: { id: string }) => t.id === id);
    expect(mine.replies).toHaveLength(1);
    await app.close();
  });

  it('says nothing to a ticket with no account behind it', async () => {
    // A WhatsApp writer with no user_id has no app to be pushed to. Attempting
    // it would be a push aimed at nobody, reported as a failure every time.
    const r = await desk.post('/admin/support', {
      subject: 'Звонила', phone: '+7 701 000 00 00', channel: 'phone',
    });
    await desk.post(`/admin/support/${r.json().id}/reply`, { body: 'Перезвоним.' });
    expect(pushes).toEqual([]);
    await app.close();
  });
});

describe('она отвечает обратно', () => {
  it('takes the ticket out of «ждём клиента» and back into the queue', async () => {
    const id = await raise();
    await desk.post(`/admin/support/${id}/reply`, { body: 'Проверяю.' });
    expect((await desk.get(`/admin/support/${id}`)).json().ticket.status).toBe('waiting');

    expect((await her().post(`/support/${id}/reply`, { body: 'Кода всё ещё нет.' })).statusCode).toBe(200);

    const board = (await desk.get('/admin/support')).json();
    const mine = board.items.find((t: { id: string }) => t.id === id);
    // «ждём клиента» is precisely the state where the ball is in her court, and
    // she has just played it. Leaving it there files her answer where nobody is
    // looking — the one-way desk again with an extra step.
    expect(mine.status).toBe('open');
    expect(mine.waitingHours).not.toBeNull();
    await app.close();
  });

  it('starts the clock at HER message, not at the ticket', async () => {
    // The seeded ticket was raised five hours ago and answered since. Her reply
    // now must read as a wait of minutes: showing «5 ч" beside a message that
    // arrived this second is how an operator stops believing the column.
    const seeded = (await her().get('/support')).json().tickets
      .find((t: { subject: string }) => t.subject === 'Не приходит код при входе');
    expect(seeded).toBeTruthy();
    await desk.post(`/admin/support/${seeded.id}/reply`, { body: 'Отправила код заново.' });
    await her().post(`/support/${seeded.id}/reply`, { body: 'Всё ещё нет.' });

    const mine = (await desk.get('/admin/support')).json().items
      .find((t: { id: string }) => t.id === seeded.id);
    expect(mine.waitingHours).toBeLessThan(0.1);
    // And it is not reported as never having been answered — we answered once.
    expect(mine.neverAnswered).toBe(false);
    await app.close();
  });

  it('a ticket we already answered stays OFF the clock while she is silent', async () => {
    // The rule frame 12 rests on, unchanged by any of the above.
    const id = await raise();
    await desk.post(`/admin/support/${id}/reply`, { body: 'Проверяю.' });
    const mine = (await desk.get('/admin/support')).json().items
      .find((t: { id: string }) => t.id === id);
    expect(mine.waitingHours).toBeNull();
    expect(mine.overdue).toBe(false);
    await app.close();
  });

  it('reopens a CLOSED ticket rather than swallowing the message', async () => {
    const id = await raise();
    await desk.patch(`/admin/support/${id}`, { status: 'closed' });
    await her().post(`/support/${id}/reply`, { body: 'Проблема вернулась.' });

    const one = (await desk.get(`/admin/support/${id}`)).json();
    expect(one.ticket.status).toBe('open');
    // Reopening clears it, or a reopened ticket still claims it was closed.
    expect(one.ticket.closedAt).toBeNull();
    expect(one.replies.some((r: { body: string }) => r.body === 'Проблема вернулась.')).toBe(true);
    await app.close();
  });

  it('refuses an empty reply', async () => {
    const id = await raise();
    expect((await her().post(`/support/${id}/reply`, { body: '  ' })).statusCode).toBe(400);
    await app.close();
  });
});

describe('чужое обращение', () => {
  it('answers 403 for another woman\'s ticket, not the thread', async () => {
    const id = await raise('Личное', 'Мой номер карты не проходит.');
    const r = await her(OTHER_USER).post(`/support/${id}/reply`, { body: 'Подслушиваю.' });
    expect(r.statusCode).toBe(403);
    // And nothing was appended.
    expect((await desk.get(`/admin/support/${id}`)).json().replies).toHaveLength(0);
    await app.close();
  });

  it('answers 403 — not 404 — for a ticket that does not exist', async () => {
    // Replying "not found" for ids that don't exist and "forbidden" for ids
    // that do lets anyone enumerate which tickets are real.
    const missing = await her().post('/support/no-such-ticket/reply', { body: 'x' });
    const someone = await her(OTHER_USER).post(`/support/${await raise()}/reply`, { body: 'x' });
    expect(missing.statusCode).toBe(403);
    expect(someone.statusCode).toBe(403);
    await app.close();
  });

  it('never shows her a ticket with no account behind it', async () => {
    // A phone-only writer's ticket carries somebody's number and nobody's
    // user_id. Matching those to an app session by phone would hand a
    // stranger's support conversation to whoever signs in with that number.
    //
    // THE NUMBER IS HER OWN, and that is the whole test. With any other number
    // this passes against a repository that matches on the phone as well —
    // «чтобы обращения до регистрации тоже были видны» is a plausible change,
    // and the guard was decorative until the number could actually collide.
    // The production case it stands for: an operator logs a WhatsApp
    // conversation against a number that later changes hands, and whoever signs
    // in with it next reads the previous owner's support thread.
    const profile = await repo.getProfile(DEMO_USER);
    expect(profile?.phone).toBeTruthy();
    const r = await desk.post('/admin/support', {
      subject: 'Чужое', phone: profile!.phone, channel: 'whatsapp',
    });
    // The ticket really does carry her number and no account — otherwise the
    // assertion below would hold for the boring reason.
    const filed = (await desk.get(`/admin/support/${r.json().id}`)).json().ticket;
    expect(filed.phone).toBe(profile!.phone);
    expect(filed.userId).toBeNull();

    const mine = (await her().get('/support')).json().tickets;
    expect(mine.some((t: { id: string }) => t.id === r.json().id)).toBe(false);
    expect(mine.some((t: { subject: string }) => t.subject === 'Чужое')).toBe(false);
    await app.close();
  });

  it('lists only her own', async () => {
    await raise('Моё', 'Первое.');
    const other = await her(OTHER_USER).post('/support', { subject: 'Её', body: 'Второе.' });
    expect(other.statusCode).toBe(201);

    const mine = (await her().get('/support')).json().tickets;
    expect(mine.some((t: { subject: string }) => t.subject === 'Моё')).toBe(true);
    expect(mine.some((t: { subject: string }) => t.subject === 'Её')).toBe(false);
    await app.close();
  });
});

describe('она прочитала', () => {
  /** Raise one and have the desk answer it, which is what lights the badge. */
  async function answered(body = 'Заказ придёт завтра до 18:00.') {
    const id = await raise('Где мой заказ', 'Оплатила вчера.');
    await desk.post(`/admin/support/${id}/reply`, { body });
    return id;
  }
  const ticketOf = async (id: string) =>
    (await her().get('/support')).json().tickets.find((t: { id: string }) => t.id === id);

  it('takes the badge DOWN, which nothing used to do', async () => {
    const id = await answered();
    // Before: an answer she has never opened. This is the state the «Есть
    // ответ поддержки · 1» badge is built from.
    expect((await ticketOf(id)).customerReadAt).toBeNull();

    const r = await her().post(`/support/${id}/read`, {});
    expect(r.statusCode).toBe(200);
    expect(r.json().readAt).toBeTruthy();

    const after = await ticketOf(id);
    expect(after.customerReadAt).not.toBeNull();
    // Newer than the answer, or the app cannot tell «прочитано» from «ответили
    // после того, как она прочитала».
    expect(after.customerReadAt >= after.replies[0].at).toBe(true);
    await app.close();
  });

  it('leaves the operator\'s queue exactly where it was', async () => {
    // «ждём клиента» is the desk's state and hers to answer — her opening the
    // screen must not move the ticket out of the board somebody works from,
    // and updated_at is what that board sorts on.
    const id = await answered();
    const before = await repo.getSupportTicket(id);
    await her().post(`/support/${id}/read`, {});
    const after = await repo.getSupportTicket(id);
    expect(after!.status).toBe('waiting');
    expect(after!.updatedAt).toBe(before!.updatedAt);
    expect(after!.answeredAt).toBe(before!.answeredAt);
    await app.close();
  });

  it('lights again for the NEXT answer', async () => {
    // The reason this is a timestamp and not a flag: a badge that could only be
    // switched off once would swallow every answer after the first.
    const id = await answered();
    await her().post(`/support/${id}/read`, {});
    const read = (await ticketOf(id)).customerReadAt;
    await new Promise((r) => setTimeout(r, 5));
    await desk.post(`/admin/support/${id}/reply`, { body: 'Курьер выехал.' });

    const after = await ticketOf(id);
    expect(after.customerReadAt).toBe(read);
    const last = after.replies[after.replies.length - 1].at;
    // Unread again: the newest answer is younger than the moment she read.
    expect(last > after.customerReadAt).toBe(true);
    await app.close();
  });

  it('counts her own reply as having read it', async () => {
    // She answered the answer. Relighting the badge over her own message is how
    // a woman opens the screen three times looking for something new.
    const id = await answered();
    await her().post(`/support/${id}/reply`, { body: 'Спасибо!' });
    expect((await ticketOf(id)).customerReadAt).not.toBeNull();
    await app.close();
  });

  it('answers 403 for a ticket that is not hers, and marks nothing', async () => {
    const id = await answered();
    expect((await her(OTHER_USER).post(`/support/${id}/read`, {})).statusCode).toBe(403);
    expect((await her().post('/support/no-such-ticket/read', {})).statusCode).toBe(403);
    expect((await repo.getSupportTicket(id))!.customerReadAt).toBeNull();
    await app.close();
  });
});

describe('what the app is told', () => {
  it('states the promise, from the same constant the panel shows', async () => {
    const mine = (await her().get('/support')).json();
    const board = (await desk.get('/admin/support')).json();
    // Two numbers for one promise drift, and the screen would disagree with the
    // operator's board within a month.
    expect(mine.slaHours).toBe(board.slaHours);
    await app.close();
  });

  it('does NOT hand her the operator\'s canned answers', async () => {
    // support_templates carry «{status}» / «{eta}» placeholders an operator
    // fills in. Shipping them to the customer would show her the machinery.
    const body = (await her().get('/support')).json();
    expect(JSON.stringify(body)).not.toContain('{status}');
    expect(body.templates).toBeUndefined();
    await app.close();
  });

  it('sends only the seven keys the app reads, not the back-office row', async () => {
    // The handler used to spread the raw SupportTicketRow, so every ticket
    // arrived carrying assigneeId — a staff_accounts UUID — plus her userId,
    // the phone and name the desk holds, appContext, channel and every
    // internal timestamp. The app parses seven keys and ignored the rest.
    //
    // Asserting the EXACT key set, not just the absence of today's offenders:
    // a spread hands over whatever columns the next migration adds, and a
    // deny-list would silently start leaking each new one. This fails on the
    // day someone adds a column, which is the day to decide about it.
    // Answered, so the row carries the fields an unanswered one would leave
    // null — assigneeId and answeredAt are only interesting once staff touch it.
    const id = await raise('Где заказ?', 'Жду неделю');
    await desk.post(`/admin/support/${id}/reply`, { body: 'Завтра до 18:00' });

    const t = (await her().get('/support')).json().tickets[0];
    expect(Object.keys(t).sort()).toEqual(
      ['body', 'createdAt', 'customerReadAt', 'id', 'replies', 'status', 'subject'],
    );
    // Named individually too, so a failure says which one came back rather
    // than printing two key lists and leaving the reader to diff them.
    expect(t.assigneeId, 'a staff account id reached the customer').toBeUndefined();
    expect(t.userId).toBeUndefined();
    expect(t.phone).toBeUndefined();
    expect(t.appContext).toBeUndefined();
    await app.close();
  });
});
