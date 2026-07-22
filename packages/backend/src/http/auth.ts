/**
 * Resolving the caller from a request — the seam between "who is asking" and the
 * routes, so the composition root can wire real token verification while tests
 * drive it with fakes.
 *
 * Order of trust:
 *   1. A `Bearer` token, verified by [verifyIdToken] when one is configured
 *      (Firebase in production). An unverifiable token is rejected.
 *   2. In dev only ([allowStubToken]), the stub session token `stub-token:<uid>`
 *      identifies the caller — so the app's real sign-in flow works end to end
 *      against the in-memory backend without a Firebase project.
 *   3. The legacy `x-user-id` dev header (`--dart-define=DEV_USER_ID`).
 *
 * Production must set REAL_AUTH=1 (→ allowStubToken:false) and a verifier; then
 * neither the stub token nor the dev header is honoured.
 */

export const STUB_TOKEN_PREFIX = 'stub-token:';

export interface HeaderCarrier {
  headers: Record<string, string | string[] | undefined>;
}

function header(req: HeaderCarrier, name: string): string | null {
  const v = req.headers[name];
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/** The bearer token from an Authorization header, or null. */
export function bearerToken(req: HeaderCarrier): string | null {
  const h = header(req, 'authorization');
  if (h && h.startsWith('Bearer ')) {
    const t = h.slice('Bearer '.length).trim();
    return t.length > 0 ? t : null;
  }
  return null;
}

export interface AuthUserOptions {
  /** Verifies a real ID token → userId, or null if invalid. Firebase in prod. */
  verifyIdToken?: (token: string) => Promise<string | null>;
  /** Honour the dev stub token `stub-token:<uid>`. False in production. */
  allowStubToken: boolean;
}

/** Build the `authUser` resolver the server is given. */
export function makeAuthUser(opts: AuthUserOptions) {
  return async (req: HeaderCarrier): Promise<{ userId: string } | null> => {
    const token = bearerToken(req);
    if (token) {
      if (opts.verifyIdToken) {
        const uid = await opts.verifyIdToken(token).catch(() => null);
        return uid ? { userId: uid } : null;
      }
      if (opts.allowStubToken && token.startsWith(STUB_TOKEN_PREFIX)) {
        const uid = token.slice(STUB_TOKEN_PREFIX.length);
        return uid.length > 0 ? { userId: uid } : null;
      }
      // A token we were given no way to verify — refuse rather than trust it.
      return null;
    }
    // Legacy dev header, only when no token was presented.
    const id = header(req, 'x-user-id');
    return id ? { userId: id } : null;
  };
}
