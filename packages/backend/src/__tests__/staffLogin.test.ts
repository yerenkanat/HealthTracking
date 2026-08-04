/**
 * Staff sign-in: phone number and password.
 *
 * This is the authorisation boundary for the back office, so the tests are
 * about what it REFUSES as much as what it allows. Until now the boundary was
 * Caddy's basic_auth plus a panel that trusted the x-staff-role header — so a
 * line in a reverse-proxy config was the whole model, and anything that reached
 * the route could call itself an admin.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashPassword, hashToken, normalizePhone, readSessionCookie } from '../http/staffAuth';

const PHONE = '77073452244';
const PASSWORD = 'correct horse battery';

let repo: Repository;
let app: FastifyInstance;

/** The panel's own auth, wired the way index.ts wires it in production. */
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
      authUser: async () => ({ userId: DEMO_USER }),
      // Sessions only — no header shortcut, which is production's posture.
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
}

const login = (phone: string, password: string) =>
  app.inject({ method: 'POST', url: '/admin/login', payload: { phone, password } });

/** The cookie value a browser would keep from a Set-Cookie header. */
function cookieFrom(res: { headers: Record<string, unknown> }): string {
  const raw = String(res.headers['set-cookie'] ?? '');
  return raw.split(';')[0];
}

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.upsertStaffAccount({
    phone: PHONE,
    passwordHash: await hashPassword(PASSWORD),
    role: 'admin',
    displayName: 'Ерен',
  });
  app = build();
});

describe('signing in', () => {
  it('accepts the phone and password, and returns a session', async () => {
    const res = await login(PHONE, PASSWORD);
    expect(res.statusCode).toBe(200);
    expect(res.json().staff.role).toBe('admin');

    const cookie = String(res.headers['set-cookie']);
    // HttpOnly so the panel's own script cannot read it; SameSite=Strict so no
    // other site can cause an authenticated request.
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');
  });

  it.each([
    ['+7 707 345 22 44', 'as the phone displays it'],
    ['8 707 345 22 44', 'the domestic prefix'],
    ['7707 345 2244', 'spaces anywhere'],
  ])('accepts %s (%s)', async (typed) => {
    // Staff type whatever their phone shows them, and all of these are the same
    // person. Rejecting the format would read as "wrong password".
    expect((await login(typed, PASSWORD)).statusCode).toBe(200);
  });

  it('refuses a wrong password', async () => {
    const res = await login(PHONE, 'not the password');
    expect(res.statusCode).toBe(401);
    expect(res.headers['set-cookie']).toBeUndefined();
  });

  it('answers an unknown phone exactly as it answers a wrong password', async () => {
    // Otherwise the login doubles as a way to ask "does this number have an
    // account", and Kazakh mobiles are eleven digits with a fixed prefix.
    const unknown = await login('77010000000', PASSWORD);
    const wrong = await login(PHONE, 'nope');
    expect(unknown.statusCode).toBe(wrong.statusCode);
    expect(unknown.json()).toEqual(wrong.json());
  });

  it('locks out after repeated failures, and says for how long', async () => {
    for (let i = 0; i < 8; i++) await login(PHONE, 'wrong');
    const res = await login(PHONE, PASSWORD);
    expect(res.statusCode).toBe(429);
    expect(res.json().retryAfterMinutes).toBeGreaterThan(0);
  });
});

describe('the session is what grants access', () => {
  it('refuses an admin route with no cookie', async () => {
    const res = await app.inject({ method: 'GET', url: '/admin/stats' });
    expect(res.statusCode).toBe(401);
  });

  it('refuses the x-staff-role header that used to be enough', async () => {
    // The header stub is off wherever a database is configured. Anyone could
    // send this; for a while, it was admin access.
    const res = await app.inject({
      method: 'GET',
      url: '/admin/stats',
      headers: { 'x-staff-id': 'anyone', 'x-staff-role': 'admin' },
    });
    expect(res.statusCode).toBe(401);
  });

  it('allows it with the cookie from a real sign-in', async () => {
    const cookie = cookieFrom(await login(PHONE, PASSWORD));
    const res = await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie } });
    expect(res.statusCode).toBe(200);
  });

  it('stops working after signing out', async () => {
    const cookie = cookieFrom(await login(PHONE, PASSWORD));
    expect((await app.inject({ method: 'POST', url: '/admin/logout', headers: { cookie } })).statusCode).toBe(200);

    const res = await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie } });
    expect(res.statusCode, 'the old cookie must be dead').toBe(401);
  });

  it('a made-up cookie is not a session', async () => {
    const res = await app.inject({
      method: 'GET', url: '/admin/stats',
      headers: { cookie: 'umay_staff=pretend-token' },
    });
    expect(res.statusCode).toBe(401);
  });
});

describe('/admin/me', () => {
  it('says who is signed in', async () => {
    const cookie = cookieFrom(await login(PHONE, PASSWORD));
    const res = await app.inject({ method: 'GET', url: '/admin/me', headers: { cookie } });
    expect(res.statusCode).toBe(200);
    expect(res.json().role).toBe('admin');
  });

  it('401s when signed out — the panel uses this to choose its screen', async () => {
    expect((await app.inject({ method: 'GET', url: '/admin/me' })).statusCode).toBe(401);
  });
});

describe('the phone normaliser', () => {
  it.each([
    ['+7 707 345 22 44', '77073452244'],
    ['8 (707) 345-22-44', '77073452244'],
    ['7073452244', '77073452244'],
    ['77073452244', '77073452244'],
  ])('%s → %s', (input, expected) => {
    expect(normalizePhone(input)).toBe(expected);
  });
});
