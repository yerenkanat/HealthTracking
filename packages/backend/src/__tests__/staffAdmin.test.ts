/**
 * Managing colleagues from the panel.
 *
 * The interesting cases are all lockouts. Everything here is recoverable by
 * editing the database over SSH, which is exactly the position this feature
 * exists to get the owner out of — so a mistake that needs SSH to undo is a
 * failure of this file, not a support ticket.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashPassword, hashToken, readSessionCookie, verifyPassword } from '../http/staffAuth';

const OWNER = { phone: '77073452244', password: 'owner-password' };
const NURSE = { phone: '77011112233', password: 'nurse-password' };

let repo: Repository;
let app: FastifyInstance;

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
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
}

const login = async (phone: string, password: string) => {
  const res = await app.inject({ method: 'POST', url: '/admin/login', payload: { phone, password } });
  return String(res.headers['set-cookie'] ?? '').split(';')[0];
};

const roster = async (cookie: string) =>
  (await app.inject({ method: 'GET', url: '/admin/staff', headers: { cookie } })).json().staff;

const idOf = async (cookie: string, phone: string) =>
  (await roster(cookie)).find((a: { phone: string }) => a.phone === phone)?.id;

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.upsertStaffAccount({
    phone: OWNER.phone, passwordHash: await hashPassword(OWNER.password),
    role: 'admin', displayName: 'Ерен',
  });
  app = build();
});

describe('who may manage staff', () => {
  it('an admin sees the roster', async () => {
    const cookie = await login(OWNER.phone, OWNER.password);
    const list = await roster(cookie);
    expect(list.some((a: { phone: string }) => a.phone === OWNER.phone)).toBe(true);
  });

  it('never returns a password hash', async () => {
    // The roster is JSON in a browser. A hash there is a hash on 20 laptops.
    const cookie = await login(OWNER.phone, OWNER.password);
    const res = await app.inject({ method: 'GET', url: '/admin/staff', headers: { cookie } });
    expect(res.body).not.toMatch(/scrypt\$/);
    expect(res.body).not.toMatch(/passwordHash/);
  });

  it('a support account cannot see or change the roster', async () => {
    const admin = await login(OWNER.phone, OWNER.password);
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie: admin },
      payload: { ...NURSE, displayName: 'Айгерім', role: 'support' },
    });
    const theirs = await login(NURSE.phone, NURSE.password);

    expect((await app.inject({ method: 'GET', url: '/admin/staff', headers: { cookie: theirs } })).statusCode).toBe(403);
    expect((await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie: theirs },
      payload: { phone: '77019998877', displayName: 'X', role: 'admin', password: 'another-one' },
    })).statusCode).toBe(403);
  });

  it('signed out, the roster is not readable at all', async () => {
    expect((await app.inject({ method: 'GET', url: '/admin/staff' })).statusCode).toBe(401);
  });
});

describe('adding a colleague', () => {
  it('creates an account they can sign in with', async () => {
    const cookie = await login(OWNER.phone, OWNER.password);
    const res = await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '+7 701 111 22 33', displayName: 'Айгерім', role: 'clinician', password: NURSE.password },
    });
    expect(res.statusCode).toBe(200);

    // Typed with spaces and a +7; they sign in with the same number bare.
    const theirs = await login(NURSE.phone, NURSE.password);
    expect(theirs).toContain('umay_staff');
    expect((await app.inject({ method: 'GET', url: '/admin/me', headers: { cookie: theirs } })).json().role)
      .toBe('clinician');
  });

  it('refuses a number that already has an account', async () => {
    // Upsert here would silently reset a working colleague's password to
    // whatever the admin typed, and lock them out of a session they are in.
    const cookie = await login(OWNER.phone, OWNER.password);
    const res = await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: OWNER.phone, displayName: 'Someone else', role: 'support', password: 'brand-new-password' },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('phone_taken');

    // And the existing account is untouched.
    const acct = await repo.staffByPhone(OWNER.phone);
    expect(await verifyPassword(OWNER.password, acct!.passwordHash), 'the owner password still works').toBe(true);
    expect(acct!.role).toBe('admin');
  });

  it('refuses a password too short to be worth having', async () => {
    const cookie = await login(OWNER.phone, OWNER.password);
    const res = await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '77019998877', displayName: 'X', role: 'support', password: 'short' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('weak_password');
    expect(res.json().minPasswordLength).toBeGreaterThanOrEqual(8);
  });
});

describe('the lockouts that cannot be undone from here', () => {
  it('will not let an admin disable themselves', async () => {
    const cookie = await login(OWNER.phone, OWNER.password);
    const me = await idOf(cookie, OWNER.phone);
    const res = await app.inject({
      method: 'PATCH', url: `/admin/staff/${me}`, headers: { cookie }, payload: { disabled: true },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('cannot_lock_yourself_out');
    expect((await repo.staffById(me))!.disabled).toBe(false);
  });

  it('will not let an admin demote themselves', async () => {
    const cookie = await login(OWNER.phone, OWNER.password);
    const me = await idOf(cookie, OWNER.phone);
    const res = await app.inject({
      method: 'PATCH', url: `/admin/staff/${me}`, headers: { cookie }, payload: { role: 'support' },
    });
    expect(res.statusCode).toBe(409);
    expect((await repo.staffById(me))!.role).toBe('admin');
  });

  it('will not let the last admin be disabled by another admin', async () => {
    // Two admins, each disabling the other in turn: the second must fail, or
    // the business is left with a back office nobody can open.
    const first = await login(OWNER.phone, OWNER.password);
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie: first },
      payload: { ...NURSE, displayName: 'Айгерім', role: 'admin' },
    });
    const second = await login(NURSE.phone, NURSE.password);
    const firstId = await idOf(first, OWNER.phone);
    const secondId = await idOf(first, NURSE.phone);

    // Second admin disables the first: allowed, one admin remains.
    expect((await app.inject({
      method: 'PATCH', url: `/admin/staff/${firstId}`, headers: { cookie: second }, payload: { disabled: true },
    })).statusCode).toBe(200);

    // Now the second is the only one left, and cannot be removed by anyone.
    const res = await app.inject({
      method: 'PATCH', url: `/admin/staff/${secondId}`, headers: { cookie: second }, payload: { disabled: true },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toMatch(/last_admin|cannot_lock_yourself_out/);
    expect((await repo.staffById(secondId))!.disabled).toBe(false);
  });

  it('disabling a colleague signs their browser out immediately', async () => {
    // Without this, "revoke access" means "revoke access in up to 12 hours".
    const admin = await login(OWNER.phone, OWNER.password);
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie: admin },
      payload: { ...NURSE, displayName: 'Айгерім', role: 'support' },
    });
    const theirs = await login(NURSE.phone, NURSE.password);
    expect((await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie: theirs } })).statusCode).toBe(200);

    const res = await app.inject({
      method: 'PATCH', url: `/admin/staff/${await idOf(admin, NURSE.phone)}`,
      headers: { cookie: admin }, payload: { disabled: true },
    });

    expect((await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie: theirs } })).statusCode).toBe(401);
    // Their session row is gone, not merely refused. Reverting the deletion
    // leaves this test green on the 401 alone — the disabled flag is checked on
    // every lookup — while dead sessions accumulate against an account that
    // could later be re-enabled, handing back a live cookie nobody remembers.
    expect(res.json().signedOut, 'the session row should have been deleted').toBeGreaterThan(0);
    // And they cannot simply sign in again.
    expect((await app.inject({
      method: 'POST', url: '/admin/login', payload: { phone: NURSE.phone, password: NURSE.password },
    })).statusCode).toBe(401);
  });
});

describe('changing your own password', () => {
  it('needs the current one', async () => {
    // An unattended signed-in browser must not be enough to take the account.
    const cookie = await login(OWNER.phone, OWNER.password);
    const res = await app.inject({
      method: 'POST', url: '/admin/staff/me/password', headers: { cookie },
      payload: { currentPassword: 'not it', newPassword: 'a-better-password' },
    });
    expect(res.statusCode).toBe(403);
    expect(await verifyPassword(OWNER.password, (await repo.staffByPhone(OWNER.phone))!.passwordHash)).toBe(true);
  });

  it('changes it, keeps this browser signed in, and drops the others', async () => {
    const laptop = await login(OWNER.phone, OWNER.password);
    const phone = await login(OWNER.phone, OWNER.password);   // a second device

    const res = await app.inject({
      method: 'POST', url: '/admin/staff/me/password', headers: { cookie: laptop },
      payload: { currentPassword: OWNER.password, newPassword: 'a-better-password' },
    });
    expect(res.statusCode).toBe(200);

    // The point of changing a password is that whoever else knew it is out.
    expect((await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie: phone } })).statusCode)
      .toBe(401);
    // But it must not sign YOU out mid-task without warning.
    expect((await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie: laptop } })).statusCode)
      .toBe(200);
    // And the new password is the one that works.
    expect((await app.inject({
      method: 'POST', url: '/admin/login', payload: { phone: OWNER.phone, password: 'a-better-password' },
    })).statusCode).toBe(200);
    expect((await app.inject({
      method: 'POST', url: '/admin/login', payload: { phone: OWNER.phone, password: OWNER.password },
    })).statusCode).toBe(401);
  });

  it('is available to a support account too', async () => {
    // It is their password. Needing an admin to rotate it is how shared
    // passwords happen.
    const admin = await login(OWNER.phone, OWNER.password);
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie: admin },
      payload: { ...NURSE, displayName: 'Айгерім', role: 'support' },
    });
    const theirs = await login(NURSE.phone, NURSE.password);
    const res = await app.inject({
      method: 'POST', url: '/admin/staff/me/password', headers: { cookie: theirs },
      payload: { currentPassword: NURSE.password, newPassword: 'their-own-choice' },
    });
    expect(res.statusCode).toBe(200);
  });
});

describe('the roster shows what an owner needs to see', () => {
  it('records when someone last signed in', async () => {
    // "Who still uses this?" is the question that gets stale accounts closed.
    const cookie = await login(OWNER.phone, OWNER.password);
    const me = (await roster(cookie)).find((a: { phone: string }) => a.phone === OWNER.phone);
    expect(me.lastLoginAt, 'a sign-in just happened').not.toBeNull();
    expect(Number.isNaN(Date.parse(me.lastLoginAt))).toBe(false);
  });
});
