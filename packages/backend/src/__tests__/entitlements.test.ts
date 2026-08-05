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
