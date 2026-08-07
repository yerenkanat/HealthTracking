/**
 * Signing in to the app with a phone number, against our own server.
 *
 * The app has always had the two sign-in screens, but behind them sat
 * StubPhoneAuthProvider — it accepts 123456 on the handset and never speaks to
 * anyone. So an account existed only on the phone that made it: reinstall, and
 * the pregnancy was gone. This is the server side of a real account.
 *
 * Sign-in is TWO steps: ask for a code, then prove you received it. It used to
 * be one — eleven digits in, a ninety-day session out — so anyone holding a
 * customer's number, which is on every parcel and every WhatsApp order, could
 * open her account and read her pregnancy, her children and where they are.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { makeAuthUser } from '../http/auth';
import { hashToken } from '../http/staffAuth';
import { MAX_CLAIMS } from '../routes/phoneAuth';

let repo: Repository;
let app: FastifyInstance;

/**
 * The code the server just "sent".
 *
 * A test sender, not the log-only one: these tests need to READ the code, and
 * the production senders deliberately never expose it — returning it in the
 * response "for tests" is how it ends up in the response.
 */
let lastCode = '';
/// A DIFFERENT code each time. A constant made two of these tests vacuous:
/// 'a code for one number does not open another' passed because both numbers
/// got the same digits.
let codeSeq = 0;

/** Wired exactly as index.ts wires it once a database exists. */
function build(): FastifyInstance {
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
      // No stub token, no dev header: production's posture.
      authUser: (req) => makeAuthUser({
        verifySessionToken: async (t) => repo.userBySessionToken(hashToken(t)),
        allowStubToken: false,
      })(req),
      authAdmin: async () => null,
      sms: {
        newCode: () => String(100000 + (codeSeq++)),
        send: async (_phone, code) => { lastCode = code; return true; },
      },
    },
    { logger: false },
  );
}

const start = (phone: string, displayName?: string) =>
  app.inject({ method: 'POST', url: '/auth/phone/start', payload: { phone, displayName } });

const verify = (phone: string, code: string, displayName?: string) =>
  app.inject({ method: 'POST', url: '/auth/phone/verify', payload: { phone, code, displayName } });

/** The whole flow, for tests that care about what a signed-in account can do. */
async function signIn(phone: string, displayName?: string) {
  const started = await start(phone, displayName);
  if (started.statusCode !== 200) return started;
  return verify(phone, lastCode, displayName);
}

beforeEach(() => {
  repo = createMemoryRepository();
  lastCode = '';
  codeSeq = 0;
  app = build();
});

describe('signing in', () => {
  it('a number nobody has used creates an account and returns a token', async () => {
    const res = await signIn('+7 707 345 22 44', 'Айгерім');
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.userId).toBeTruthy();
    expect(body.token).toBeTruthy();
    expect(body.phone).toBe('77073452244');
    expect(body.displayName).toBe('Айгерім');
  });

  it('the same number signs back into the SAME account', async () => {
    // The whole point. If this returned a new account each time, reinstalling
    // the app would silently orphan everything she had recorded.
    const first = (await signIn('77073452244', 'Айгерім')).json();
    const again = (await signIn('+7 (707) 345-22-44')).json();
    expect(again.userId).toBe(first.userId);
  });

  it.each([
    ['+7 707 345 22 44', 'as the phone displays it'],
    ['8 707 345 22 44', 'the domestic prefix'],
    ['7707 345 2244', 'spaces anywhere'],
  ])('accepts %s (%s) as the same person', async (typed) => {
    const canonical = (await signIn('77073452244')).json();
    expect((await signIn(typed)).json().userId).toBe(canonical.userId);
  });

  it('refuses something that is not a phone number', async () => {
    expect((await signIn('77')).statusCode).toBe(400);
    expect((await signIn('')).statusCode).toBe(400);
  });

  it('rate-limits how fast one number can be claimed', async () => {
    // Without a code to get wrong, this is the only thing standing between a
    // script and the whole eleven-digit Kazakh mobile space.
    for (let i = 0; i < MAX_CLAIMS; i++) await signIn('77073452244');
    const res = await signIn('77073452244');
    expect(res.statusCode).toBe(429);
    expect(res.json().retryAfterMinutes).toBeGreaterThan(0);
  });
});

/// The gate itself.
///
/// Every one of these was true before and is false now: typing a number was
/// the whole sign-in.
describe('the code is what proves it is her number', () => {
  it('a number alone gets no session', async () => {
    const res = await start('77073452244');
    expect(res.statusCode).toBe(200);
    // 200 means "a code is on its way", not "you are in".
    expect(res.json().token, 'a session came back from step one').toBeUndefined();
    expect(res.json().userId).toBeUndefined();
  });

  it('never puts the code in the response', async () => {
    // Returning it "for convenience" is how it ends up returned in production.
    const body = (await start('77073452244')).body;
    expect(body).not.toContain(lastCode);
  });

  it('a wrong code is refused', async () => {
    await start('77073452244');
    const res = await verify('77073452244', '000000');
    expect(res.statusCode).toBe(401);
    expect(res.json().error).toBe('wrong_code');
  });

  it('a code cannot be used twice', async () => {
    // Otherwise one intercepted SMS is a permanent key.
    await start('77073452244');
    expect((await verify('77073452244', lastCode)).statusCode).toBe(200);
    expect((await verify('77073452244', lastCode)).statusCode).toBe(401);
  });

  it('gives up after five wrong guesses', async () => {
    // Six digits is a million combinations; a bot does not need a million.
    await start('77073452244');
    for (let i = 0; i < 5; i++) {
      expect((await verify('77073452244', '000000')).json().error).toBe('wrong_code');
    }
    const res = await verify('77073452244', '000000');
    expect(res.json().error).toBe('too_many_attempts');
    // And the RIGHT code no longer helps: she asks for a new one.
    expect((await verify('77073452244', lastCode)).statusCode).toBe(401);
  });

  it("a code for one number does not open another", async () => {
    await start('77073452244');
    const hers = lastCode;
    await start('77011112233');
    expect((await verify('77011112233', hers)).statusCode).toBe(401);
  });

  it('asking again replaces the previous code', async () => {
    // So a code read over her shoulder stops working the moment she asks for
    // another.
    await start('77073452244');
    const first = lastCode;
    await start('77073452244');
    expect((await verify('77073452244', first)).statusCode).toBe(401);
    expect((await verify('77073452244', lastCode)).statusCode).toBe(200);
  });

  it('refuses anything that is not six digits without touching the code', async () => {
    await start('77073452244');
    for (const bad of ['', '12345', '1234567', 'abcdef', '12 34 56']) {
      expect((await verify('77073452244', bad)).statusCode, bad).toBe(400);
    }
    // A malformed guess must not burn an attempt — the real code still works.
    expect((await verify('77073452244', lastCode)).statusCode).toBe(200);
  });

  it('says the same thing whether or not the number has an account', async () => {
    // Otherwise this endpoint answers "is this person a customer of yours?"
    // about any number somebody has.
    await signIn('77073452244');
    const known = await start('77073452244');
    const unknown = await start('77011112233');
    expect(known.statusCode).toBe(unknown.statusCode);
    expect(known.body).toBe(unknown.body);
  });
});

/// With no gateway configured, nobody signs in — including the attacker.
describe('when no SMS can be sent', () => {
  it('refuses rather than falling back to letting her in', async () => {
    // The tempting "fallback" is the hole this whole flow closes.
    const noSms = buildServer(
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
        // sms omitted — exactly what index.ts passes off a dev box.
      },
      { logger: false },
    );
    const res = await noSms.inject({
      method: 'POST', url: '/auth/phone/start', payload: { phone: '77073452244' },
    });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('sms_unavailable');
  });
});

describe('the token is what gets the data', () => {
  it('opens the API for the account it belongs to', async () => {
    const { token, userId } = (await signIn('77073452244')).json();
    const res = await app.inject({
      method: 'GET', url: '/children',
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.statusCode).toBe(200);
    expect(userId).toBeTruthy();
  });

  it('without it, nothing', async () => {
    expect((await app.inject({ method: 'GET', url: '/children' })).statusCode).toBe(401);
  });

  it('a made-up token is not a session', async () => {
    const res = await app.inject({
      method: 'GET', url: '/children',
      headers: { authorization: 'Bearer pretend-token' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('the x-user-id header is worth nothing', async () => {
    // It used to be everything. Anyone could read any family's data with it,
    // which is why the app API is closed at the edge until this test passes.
    const res = await app.inject({
      method: 'GET', url: '/children',
      headers: { 'x-user-id': '11111111-1111-1111-1111-111111111111' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('the dev stub token is worth nothing either', async () => {
    const res = await app.inject({
      method: 'GET', url: '/children',
      headers: { authorization: 'Bearer stub-token:11111111-1111-1111-1111-111111111111' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('stops working after signing out', async () => {
    const { token } = (await signIn('77073452244')).json();
    const auth = { authorization: `Bearer ${token}` };
    expect((await app.inject({ method: 'POST', url: '/auth/logout', headers: auth })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/children', headers: auth })).statusCode).toBe(401);
  });

  /// Signing out from the app, which cannot send the header.
  ///
  /// The app reads its bearer token out of the signed-in session on every
  /// request, and signing out clears that session — so a logout fired after
  /// the clear carries no header, and one fired before it loses the race with
  /// it. The request arrived unauthenticated, revoked nothing, and the session
  /// stayed valid for its full ninety days on a phone that had been handed on,
  /// sold or restored from a backup.
  it('revokes a token presented in the body, not only in the header', async () => {
    const { token } = (await signIn('77073452244')).json();
    const auth = { authorization: `Bearer ${token}` };

    const out = await app.inject({ method: 'POST', url: '/auth/logout', payload: { token } });
    expect(out.statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/children', headers: auth })).statusCode,
      'the session outlived the sign-out').toBe(401);
  });

  it('revokes only the session it was given', async () => {
    // Two devices, one account. Signing out of the tablet must not sign her
    // out of the phone she is holding.
    const a = (await signIn('77073452244')).json();
    const b = (await signIn('77073452244')).json();
    await app.inject({ method: 'POST', url: '/auth/logout', payload: { token: a.token } });

    expect((await app.inject({
      method: 'GET', url: '/children', headers: { authorization: `Bearer ${a.token}` },
    })).statusCode).toBe(401);
    expect((await app.inject({
      method: 'GET', url: '/children', headers: { authorization: `Bearer ${b.token}` },
    })).statusCode, 'the other device was signed out too').toBe(200);
  });

  it('says the same thing to a token that was never real', async () => {
    // A different answer here would let somebody test guesses against it.
    for (const payload of [{ token: 'never-issued' }, { token: '' }, {}]) {
      expect((await app.inject({ method: 'POST', url: '/auth/logout', payload })).statusCode,
        JSON.stringify(payload)).toBe(200);
    }
  });

  it('two people get two separate accounts, and cannot see each other', async () => {
    const a = (await signIn('77073452244')).json();
    const b = (await signIn('77011112233')).json();
    expect(a.userId).not.toBe(b.userId);
    expect(a.token).not.toBe(b.token);
  });
});

describe('what claiming a number does NOT do', () => {
  it('does not verify the number belongs to the caller', async () => {
    // Stated as a test so that nobody reads the sign-in and assumes otherwise.
    // Anyone can sign in as any number today; what they get is an empty
    // account. Adding an SMS gateway changes the handler behind this endpoint
    // and nothing in the app.
    const res = await signIn('77009998877');
    expect(res.statusCode, 'a number nobody owns is accepted, by design').toBe(200);
    expect(res.json().token).toBeTruthy();
  });
});
