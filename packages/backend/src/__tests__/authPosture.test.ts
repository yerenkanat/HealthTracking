/**
 * The boot guard's auth decision — the thing that refuses to start a production
 * server whose authentication anyone could forge.
 *
 * The two paths fail differently and are reported separately. A stubbed USER
 * path exposes families' data to whoever can send a header; a stubbed ADMIN
 * path hands over the back office. REAL_AUTH covers only the first, and reading
 * it as "all auth is real" is what would ship the second wide open.
 *
 * Staff auth stopped being a stub the day sign-in shipped: phone, password,
 * session cookie. What survives is the x-staff-role shortcut for local
 * development, honoured only where there is no database to hold an account —
 * so the admin path is a stub exactly when Postgres is absent.
 */
import { describe, it, expect } from 'vitest';
import { authPosture } from '../authPosture.js';

const env = (o: Record<string, string>) => o as unknown as NodeJS.ProcessEnv;
const DB = { DATABASE_URL: 'postgres://user@host/db' };

describe('authPosture', () => {
  it('with nothing configured, both paths are stubs', () => {
    const p = authPosture(env({}));
    expect(p.userStub).toBe(true);
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });

  it('REAL_AUTH=1 alone does not make the admin path real', () => {
    // A local run with REAL_AUTH set but no database still honours the staff
    // header shortcut, because there is no account to sign in to.
    const p = authPosture(env({ REAL_AUTH: '1' }));
    expect(p.userStub).toBe(false);
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });

  it('a database makes the admin path real — that is where accounts live', () => {
    const p = authPosture(env({ ...DB }));
    expect(p.adminStub, 'staff sign-in is real wherever Postgres is configured').toBe(false);
    // The user path is still a stub, so the server is still not safe to serve.
    expect(p.userStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });

  it('USE_MEMORY_DB puts the admin path back to a stub, database or not', () => {
    // This is the switch that turns the header shortcut on, so it has to be
    // read as "the back office is forgeable" even with DATABASE_URL present.
    const p = authPosture(env({ ...DB, USE_MEMORY_DB: 'true', REAL_AUTH: '1' }));
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });

  it('is production-safe only when both paths are real', () => {
    const p = authPosture(env({ ...DB, REAL_AUTH: '1' }));
    expect(p.userStub).toBe(false);
    expect(p.adminStub).toBe(false);
    expect(p.safeForProduction).toBe(true);
  });

  it('no invented flag can wave a stub through', () => {
    // The posture is derived from what is actually configured. A variable
    // someone adds in a hurry — REAL_STAFF_AUTH, AUTH_OK, whatever — must not
    // be able to declare the server safe.
    const p = authPosture(env({ REAL_STAFF_AUTH: '1', AUTH_OK: 'yes', SAFE: 'true' }));
    expect(p.userStub).toBe(true);
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });
});
