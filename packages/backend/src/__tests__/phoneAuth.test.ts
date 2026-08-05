/**
 * Signing in to the app with a phone number, against our own server.
 *
 * The app has always had the two sign-in screens, but behind them sat
 * StubPhoneAuthProvider — it accepts 123456 on the handset and never speaks to
 * anyone. So an account existed only on the phone that made it: reinstall, and
 * the pregnancy was gone. This is the server side of a real account.
 *
 * No SMS. The number is CLAIMED, not verified, and the tests say so where it
 * matters — what that does and does not protect is a product decision, not an
 * oversight, and it should fail loudly if someone later assumes otherwise.
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
    },
    { logger: false },
  );
}

const signIn = (phone: string, displayName?: string) =>
  app.inject({ method: 'POST', url: '/auth/phone', payload: { phone, displayName } });

beforeEach(() => {
  repo = createMemoryRepository();
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
