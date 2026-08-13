/**
 * PUT /profile cannot change the sign-in identity.
 *
 * THE DEFECT. The route accepted a `phone` and passed it to upsertProfile,
 * which wrote `users.phone_e164` — the column POST /auth/phone resolves an
 * account by. A signed-in user could therefore CLAIM any number that had not
 * registered yet. When its real owner signed in for the first time,
 * userByPhone() found the claimant's row and handed her that person's session:
 * her pregnancy, her children, their live locations. The same number keys the
 * course entitlement and «Мои заказы», so a claim also collected purchases.
 *
 * Driven over HTTP against the real in-memory repository, both sides of the
 * join, because every piece of this was individually correct — the sign-in
 * route, the profile route, the entitlement lookup — and the hole was in what
 * one of them was allowed to write.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken } from '../http/staffAuth';
import { MAMA_COURSE } from '../routes/entitlements';

let repo: Repository;
let app: FastifyInstance;

/** The attacker: an ordinary account, signed in normally. */
const CLAIMANT = '+77015551122';
/**
 * Her target's number, in the form an attacker would actually SEND.
 *
 * This was `'+77029998877'`, which cannot collide with anything: the
 * vulnerable code stored the body's phone verbatim, so `phone_e164` would have
 * held `'+77029998877'` while sign-in resolves accounts by `normalizePhone()`
 * output — `'77029998877'`. The two never meet, and the assertion below was
 * exercising a claim no attacker would bother making. Digits-only is what a
 * client posts and what the column is keyed on.
 *
 * WHAT ACTUALLY GUARDS THIS, checked rather than assumed. Reintroducing the
 * hole does NOT make this file fail, and that is not a weakness — it cannot be
 * reintroduced at all. `ProfileEdit = Omit<ProfileRow, 'phone'>` turns a route
 * that tries into two compile errors, and `memoryRepository.upsertProfile`
 * separately ignores a passed phone and reads it back from `usersByPhone`. The
 * type is the guard; these tests are the description of what the guard is FOR,
 * and they run against the realistic input so that description is honest.
 */
const VICTIM = '77029998877';
/**
 * The same two as the server stores them. normalizePhone() keeps digits only,
 * so one person is one account however the number was typed.
 */
const CLAIMANT_E164 = '77015551122';
const VICTIM_E164 = '77029998877';

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
      // Exactly what index.ts wires: a bearer token is a row in user_sessions,
      // and nothing else authenticates.
      authUser: async (req) => {
        const h = String(req.headers.authorization ?? '');
        const token = h.startsWith('Bearer ') ? h.slice(7) : '';
        return token ? repo.userBySessionToken(hashToken(token)) : null;
      },
      // Nobody signs in as staff here; it is present because the entitlement
      // routes — which is where a stolen number would cash out — are only
      // registered when both resolvers exist.
      authAdmin: async () => null,
    },
    { logger: false },
  );
  await app.ready();
});

/** Sign in the way the phone does, and hand back the bearer token. */
async function signIn(phone: string): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/auth/phone/start', payload: { phone } });
  expect(res.statusCode, `sign-in failed for ${phone}`).toBe(200);
  const token = res.json().token as string;
  expect(token, 'sign-in returned no token').toBeTruthy();
  return token;
}

const as = (token: string) => ({ authorization: `Bearer ${token}` });

const profileOf = async (token: string) =>
  (await app.inject({ method: 'GET', url: '/profile', headers: as(token) })).json().profile;

/** A full, otherwise-valid profile save with a phone bolted on. */
const claim = (token: string, phone: string) =>
  app.inject({
    method: 'PUT', url: '/profile', headers: as(token),
    payload: {
      displayName: 'Мадина', phone, dueDate: '2026-12-01', city: 'Алматы',
      address: null, doctorPhone: '+77007654321', avgCycleLength: 30, avgPeriodLength: 6,
    },
  });

describe('PUT /profile cannot change the sign-in identity', () => {
  it('keeps the number sign-in recorded, whatever the body says', async () => {
    const token = await signIn(CLAIMANT);
    expect((await profileOf(token)).phone).toBe(CLAIMANT_E164);

    const res = await claim(token, VICTIM);
    // Not a 400: an older app still sends the field, and refusing its whole
    // profile backup would lose the due date over a key the server ignores.
    expect(res.statusCode, 'the save itself must still succeed').toBe(200);

    const after = await profileOf(token);
    expect(after.phone, 'PUT /profile changed the sign-in number').toBe(CLAIMANT_E164);
    // Everything she IS allowed to edit still saved, so this is a targeted
    // refusal and not a route that quietly stopped working.
    expect(after.displayName).toBe('Мадина');
    expect(after.dueDate).toBe('2026-12-01');
    expect(after.city).toBe('Алматы');
    expect(after.doctorPhone, 'doctorPhone is a number she calls, not one she is').toBe('+77007654321');
  });

  it('does not put the real owner inside the claimant’s account', async () => {
    // The whole point. The claim happens first, the victim signs in second —
    // which is the order that used to hand over the session.
    const claimant = await signIn(CLAIMANT);
    await app.inject({
      method: 'POST', url: '/children', headers: as(claimant),
      payload: { id: '44444444-4444-4444-4444-444444444444', name: 'Султан' },
    });
    await claim(claimant, VICTIM);

    const victim = await signIn(VICTIM);
    expect(victim, 'the victim was handed the claimant’s own session token').not.toBe(claimant);

    const hers = await profileOf(victim);
    expect(hers.phone, 'the victim signed in and got somebody else’s number').toBe(VICTIM_E164);

    const kids = (await app.inject({ method: 'GET', url: '/children', headers: as(victim) })).json();
    expect(kids.children, 'the victim can see the claimant’s child').toEqual([]);
  });

  it('does not collect a purchase keyed on the claimed number', async () => {
    // Entitlements are keyed on the phone because an order is placed before an
    // account exists. That makes a writable phone a way to buy nothing and own
    // everything.
    await repo.grantEntitlement({ phone: VICTIM_E164, feature: MAMA_COURSE, grantedBy: 'test' });

    const claimant = await signIn(CLAIMANT);
    await claim(claimant, VICTIM);

    const course = await app.inject({ method: 'GET', url: '/course/lessons', headers: as(claimant) });
    expect(course.json().entitled, 'the claimant inherited a course she never bought').toBe(false);
  });

  it('leaves the number out of the schema entirely, so nothing downstream sees it', async () => {
    // Belt and braces on the repository rather than the route: whatever the
    // route did, upsertProfile must not be able to write a phone. The type
    // forbids it at compile time; this proves the memory implementation does
    // not reconstruct one from the payload either.
    const token = await signIn(CLAIMANT);
    const me = await repo.userByPhone(CLAIMANT_E164);
    await repo.upsertProfile(me!.id, {
      displayName: 'Мадина', dueDate: null, locale: 'ru-KZ', birthDate: null,
      city: null, address: null, doctorPhone: null, avgCycleLength: null, avgPeriodLength: null,
    });
    expect((await profileOf(token)).phone).toBe(CLAIMANT_E164);
    expect((await repo.userByPhone(VICTIM_E164)), 'the victim’s number must still be free').toBeNull();
  });
});
