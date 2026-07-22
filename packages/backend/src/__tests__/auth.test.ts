/**
 * Resolving the caller — the app sends a Bearer token once signed in; the
 * backend must verify a real one, honour the dev stub token only in dev, and
 * never trust a token it cannot check.
 */
import { describe, it, expect } from 'vitest';
import { makeAuthUser, bearerToken, STUB_TOKEN_PREFIX } from '../http/auth';

const req = (headers: Record<string, string>) => ({ headers });

describe('bearerToken', () => {
  it('extracts a Bearer token', () => {
    expect(bearerToken(req({ authorization: 'Bearer abc.def' }))).toBe('abc.def');
    expect(bearerToken(req({ authorization: 'Basic xxx' }))).toBeNull();
    expect(bearerToken(req({}))).toBeNull();
  });
});

describe('makeAuthUser — dev (stub token allowed, no verifier)', () => {
  const authUser = makeAuthUser({ allowStubToken: true });

  it('honours the app’s stub session token', async () => {
    const r = await authUser(req({ authorization: `Bearer ${STUB_TOKEN_PREFIX}u_42` }));
    expect(r).toEqual({ userId: 'u_42' });
  });

  it('rejects a bearer token it cannot verify or parse', async () => {
    expect(await authUser(req({ authorization: 'Bearer some.random.jwt' }))).toBeNull();
  });

  it('falls back to the x-user-id dev header when no token is sent', async () => {
    expect(await authUser(req({ 'x-user-id': 'dev-user' }))).toEqual({ userId: 'dev-user' });
  });

  it('is null with nothing to go on', async () => {
    expect(await authUser(req({}))).toBeNull();
  });
});

describe('makeAuthUser — production (verifier set, stub disallowed)', () => {
  it('trusts only a verified token', async () => {
    const authUser = makeAuthUser({
      allowStubToken: false,
      verifyIdToken: async (t) => (t === 'good' ? 'firebase-uid' : null),
    });
    expect(await authUser(req({ authorization: 'Bearer good' }))).toEqual({ userId: 'firebase-uid' });
    expect(await authUser(req({ authorization: 'Bearer bad' }))).toBeNull();
    // The stub token is NOT honoured in production, even if presented.
    expect(await authUser(req({ authorization: `Bearer ${STUB_TOKEN_PREFIX}u_42` }))).toBeNull();
  });

  it('does not trust the x-user-id header once a token is presented', async () => {
    const authUser = makeAuthUser({ allowStubToken: false, verifyIdToken: async () => null });
    // A presented-but-invalid token is refused rather than falling through to the header.
    expect(await authUser(req({ authorization: 'Bearer bad', 'x-user-id': 'sneaky' }))).toBeNull();
  });

  it('survives a verifier that throws', async () => {
    const authUser = makeAuthUser({
      allowStubToken: false,
      verifyIdToken: async () => { throw new Error('firebase down'); },
    });
    expect(await authUser(req({ authorization: 'Bearer x' }))).toBeNull();
  });
});
