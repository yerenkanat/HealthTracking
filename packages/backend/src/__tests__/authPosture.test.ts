/**
 * The boot guard's auth decision. The bug it locks: REAL_AUTH secures only the
 * USER path, so REAL_AUTH=1 alone must NOT be treated as "safe for production" —
 * authAdmin is a separate header stub. Reading REAL_AUTH as "all auth is real"
 * would ship a back-office anyone could enter with a forged x-staff-role header.
 */
import { describe, it, expect } from 'vitest';
import { authPosture } from '../authPosture.js';

describe('authPosture', () => {
  it('with no REAL_AUTH, both paths are stubs and it is not production-safe', () => {
    const p = authPosture({} as NodeJS.ProcessEnv);
    expect(p.userStub).toBe(true);
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });

  it('REAL_AUTH=1 makes the USER path real but the ADMIN path is still a stub', () => {
    const p = authPosture({ REAL_AUTH: '1' } as NodeJS.ProcessEnv);
    expect(p.userStub).toBe(false);
    expect(p.adminStub).toBe(true); // the whole point — REAL_AUTH does not cover staff auth
    expect(p.safeForProduction).toBe(false);
  });

  it('no env variable can wave the admin stub through', () => {
    // A stub must never be flipped safe by setting a flag — only by wiring a real
    // verifier (which changes the code, not the environment).
    const p = authPosture({ REAL_AUTH: '1', REAL_STAFF_AUTH: '1' } as NodeJS.ProcessEnv);
    expect(p.adminStub).toBe(true);
    expect(p.safeForProduction).toBe(false);
  });
});
