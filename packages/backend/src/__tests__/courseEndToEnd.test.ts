/**
 * Buying the комплект and getting the course, over HTTP, start to finish.
 *
 * Every step of this was already unit-tested and every unit test passed, and
 * the chain still did not work when it was run for real. The parts that failed
 * were the joins between them:
 *
 *   - POST /auth/phone minted a token nothing was wired to verify, so a
 *     signed-in app got 401 from every endpoint it needed;
 *   - the entitlement is looked up by the phone on the account, and the
 *     in-memory profile ignored the user id, so a signed-in caller was asked
 *     about somebody else's number.
 *
 * So this test deliberately goes through the front door for all four actors —
 * staff sign-in, the stockroom, the order desk, and the app — rather than
 * calling the repository. It is the only test that would have caught either.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

/** The code the server just "sent", so these tests can type it back. */
let lastSmsCode = '';
let smsSeq = 0;

let repo: Repository;
let app: FastifyInstance;
let staffCookie: string;

/** The customer, written the way somebody reads it out on the phone. */
const BUYER_SPOKEN = '+7 (701) 555-11-22';
/** The same number as the app sends it at sign-in. */
const BUYER_DIALLED = '+77015551122';

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
      // A capturing sender: these tests sign in for real, and the real senders
      // deliberately never reveal the code.
      sms: {
        newCode: () => String(424242 + smsSeq++),
        send: async (_p: string, code: string) => { lastSmsCode = code; return true; },
      },
      // Exactly what index.ts wires: a bearer token is a row in user_sessions.
      // Nothing else authenticates — no header shortcut, as in production.
      authUser: async (req) => {
        const h = String(req.headers.authorization ?? '');
        const token = h.startsWith('Bearer ') ? h.slice(7) : '';
        return token ? repo.userBySessionToken(hashToken(token)) : null;
      },
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        return token ? repo.staffBySessionToken(hashToken(token)) : null;
      },
    },
    { logger: false },
  );
  const login = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(login.statusCode, 'staff could not sign in').toBe(200);
  staffCookie = String(login.headers['set-cookie'] ?? '').split(';')[0];
});

const asStaff = (method: 'POST' | 'PUT' | 'PATCH' | 'GET', url: string, payload?: unknown) =>
  app.inject({ method, url, payload: payload as never, headers: { cookie: staffCookie } });

/** Sign the app in the way the phone does, and hand back its bearer token. */
async function signInApp(phone: string): Promise<string> {
  // Two steps now: ask for a code, then prove it arrived. The number alone is
  // no longer a credential — see routes/phoneAuth.ts.
  const started = await app.inject({
    method: 'POST', url: '/auth/phone/start', payload: { phone },
  });
  expect(started.statusCode, 'requesting a code failed').toBe(200);
  // No code required is what ships: step one already carries the session.
  if (started.json().codeRequired !== true) return started.json().token as string;
  const res = await app.inject({
    method: 'POST', url: '/auth/phone/verify', payload: { phone, code: lastSmsCode },
  });
  expect(res.statusCode, 'phone sign-in failed').toBe(200);
  const token = res.json().token as string;
  expect(token, 'sign-in returned no token').toBeTruthy();
  return token;
}

const course = (token: string) =>
  app.inject({ method: 'GET', url: '/course/lessons', headers: { authorization: `Bearer ${token}` } });

/** Put stock on the shelf through the panel, as staff would. */
async function stock(productId: string, qty: number): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const variantId = p.variants[0].id;
  const res = await asStaff('POST', '/admin/inventory/moves', { variantId, delta: qty, reason: 'receipt' });
  expect(res.statusCode).toBe(200);
  return variantId;
}

describe('a token from sign-in is a token the API accepts', () => {
  it('reaches the endpoints an app cannot work without', async () => {
    // The failure this guards: sign-in succeeds and then everything downstream
    // answers 401 — the most confusing shape a bug can take, because the thing
    // that authenticates is the one thing that works.
    const token = await signInApp(BUYER_DIALLED);
    for (const url of ['/children', '/profile', '/account/entitlements', '/course/lessons']) {
      const res = await app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${token}` } });
      expect(res.statusCode, `${url} rejected a valid session`).toBe(200);
    }
  });

  it('still refuses a token nobody minted', async () => {
    const res = await course('not-a-real-token');
    expect(res.statusCode).toBe(401);
  });

  it('answers about the caller, not about whoever signed in first', async () => {
    // The in-memory profile ignored the user id and returned one shared
    // account, so every signed-in caller was asked about the same phone.
    const a = await signInApp('+77015551122');
    const b = await signInApp('+77029998877');
    const pa = await app.inject({ method: 'GET', url: '/profile', headers: { authorization: `Bearer ${a}` } });
    const pb = await app.inject({ method: 'GET', url: '/profile', headers: { authorization: `Bearer ${b}` } });
    expect(pa.json().profile?.phone).not.toBe(pb.json().profile?.phone);
  });
});

describe('the комплект, from the order desk to her phone', () => {
  it('opens the course when the parcel goes out, and not before', async () => {
    const token = await signInApp(BUYER_DIALLED);

    // Nothing owned yet.
    expect((await course(token)).json()).toEqual({ entitled: false, lessons: [] });

    const w = await stock('watch', 5);
    const t = await stock('tracker', 5);

    // Staff take the order over the phone, typing the number as it was read
    // out — brackets, spaces and all.
    const placed = await asStaff('POST', '/admin/shop/orders', {
      customerName: 'Мадина', phone: BUYER_SPOKEN, city: 'Астана',
      address: 'пр. Кабанбай батыра 5, кв 12',
      bundleId: 'combo',
      items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }],
    });
    expect(placed.statusCode).toBe(201);
    expect(placed.json().totalMinor, 'the комплект is 39 000').toBe(3900000);

    // Placed is not paid-for-and-collected.
    expect((await course(token)).json()).toEqual({ entitled: false, lessons: [] });

    const orderId = (await repo.adminShopOrders(10))[0].id;
    expect((await asStaff('PATCH', `/admin/shop/orders/${orderId}`, { status: 'shipped' })).statusCode).toBe(200);

    // And now it is hers — matched across two different ways of writing the
    // same number.
    expect((await course(token)).json().entitled).toBe(true);
  });

  it('grants nothing when the two devices are bought separately', async () => {
    const token = await signInApp(BUYER_DIALLED);
    const w = await stock('watch', 5);
    const t = await stock('tracker', 5);

    const placed = await asStaff('POST', '/admin/shop/orders', {
      customerName: 'Мадина', phone: BUYER_SPOKEN, city: 'Астана', address: 'пр. Абая 1',
      items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }],
    });
    expect(placed.json().totalMinor, '29 800 for the hardware alone').toBe(2980000);

    const orderId = (await repo.adminShopOrders(10))[0].id;
    await asStaff('PATCH', `/admin/shop/orders/${orderId}`, { status: 'delivered' });

    expect((await course(token)).json().entitled,
      'if the parts unlocked the course the bundle would have no reason to exist').toBe(false);
  });

  it('shows the lessons once they are published', async () => {
    const token = await signInApp(BUYER_DIALLED);
    const w = await stock('watch', 5);
    const t = await stock('tracker', 5);
    await asStaff('POST', '/admin/shop/orders', {
      customerName: 'Мадина', phone: BUYER_SPOKEN, city: 'Астана', address: 'пр. Абая 1',
      bundleId: 'combo', items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }],
    });
    const orderId = (await repo.adminShopOrders(10))[0].id;
    await asStaff('PATCH', `/admin/shop/orders/${orderId}`, { status: 'shipped' });

    // Staff add a lesson in the panel.
    const added = await asStaff('PUT', '/admin/course/lessons', {
      titleRu: 'Первые 40 дней', titleKk: 'Алғашқы 40 күн',
      youtubeUrl: 'https://youtu.be/aaaaaaaaaaa', sort: 1, published: true,
    });
    expect(added.statusCode, 'the lesson editor refused a valid lesson').toBe(200);

    const body = (await course(token)).json();
    expect(body.entitled).toBe(true);
    expect(body.lessons).toHaveLength(1);
    expect(body.lessons[0].titleRu).toBe('Первые 40 дней');
  });

  it('does not hand the lessons to somebody who has not bought it', async () => {
    // The gate is the server's, not the app's: a paywall the client enforces
    // is one anybody can read the JSON around.
    const buyer = await signInApp(BUYER_DIALLED);
    const stranger = await signInApp('+77029998877');
    const w = await stock('watch', 5);
    const t = await stock('tracker', 5);
    await asStaff('POST', '/admin/shop/orders', {
      customerName: 'Мадина', phone: BUYER_SPOKEN, city: 'Астана', address: 'пр. Абая 1',
      bundleId: 'combo', items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }],
    });
    const orderId = (await repo.adminShopOrders(10))[0].id;
    await asStaff('PATCH', `/admin/shop/orders/${orderId}`, { status: 'shipped' });
    await asStaff('PUT', '/admin/course/lessons', {
      titleRu: 'Первые 40 дней', titleKk: 'Алғашқы 40 күн',
      youtubeUrl: 'https://youtu.be/aaaaaaaaaaa', sort: 1, published: true,
    });

    expect((await course(buyer)).json().lessons).toHaveLength(1);
    const other = (await course(stranger)).json();
    expect(other.entitled).toBe(false);
    expect(other.lessons, 'the lessons must not travel in the refusal').toEqual([]);
  });
});
