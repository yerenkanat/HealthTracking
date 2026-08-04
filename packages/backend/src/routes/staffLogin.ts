/**
 * Sign in to the back office with a phone number and a password.
 *
 * Three routes: POST /admin/login, POST /admin/logout, GET /admin/me. They are
 * the only /admin paths that do NOT require a session — everything else goes
 * through the guard in admin.ts.
 *
 * Deliberate choices, each because the alternative fails quietly:
 *
 *  - A wrong phone and a wrong password give the same answer and take the same
 *    time. Anything else turns the login into a way to ask "does this number
 *    have an account", and the numbers are guessable.
 *  - Attempts are counted per phone. A back office on the public internet with
 *    a phone number for a username needs it: Kazakh mobiles are eleven digits
 *    with a fixed prefix, so the space is small.
 *  - The session cookie is HttpOnly and SameSite=Strict, so the panel's own
 *    JavaScript cannot read it and another site cannot cause a request with it.
 */

import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository } from '../db/repository';
import {
  ATTEMPT_WINDOW_MS,
  MAX_ATTEMPTS,
  SESSION_TTL_MS,
  clearedCookie,
  hashToken,
  newSessionToken,
  normalizePhone,
  readSessionCookie,
  sessionCookie,
  verifyPassword,
} from '../http/staffAuth';

const loginBody = z.object({
  phone: z.string().min(4).max(32),
  password: z.string().min(1).max(200),
});

/** https unless we are on plain localhost, where a Secure cookie is dropped. */
function isSecure(req: FastifyRequest): boolean {
  const proto = (req.headers['x-forwarded-proto'] as string | undefined) ?? req.protocol;
  return proto === 'https';
}

export function registerStaffLoginRoutes(app: FastifyInstance, repo: Repository): void {
  app.post('/admin/login', async (req, reply) => {
    const parsed = loginBody.safeParse(req.body);
    // Not parsed.error: the shape of a bad request is not the caller's business.
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const phone = normalizePhone(parsed.data.phone);
    const since = new Date(Date.now() - ATTEMPT_WINDOW_MS);

    if ((await repo.recentFailedLogins(phone, since)) >= MAX_ATTEMPTS) {
      // 429 rather than 401: this one IS worth distinguishing, because the
      // person locked out is nearly always the real owner mistyping, and they
      // need to know waiting will help.
      return reply.code(429).send({
        error: 'too_many_attempts',
        retryAfterMinutes: Math.ceil(ATTEMPT_WINDOW_MS / 60000),
      });
    }

    const account = await repo.staffByPhone(phone);
    // Verify even when there is no account, against a hash that cannot match:
    // returning early would make "no such number" measurably faster than "wrong
    // password", which is the whole question an attacker is asking.
    const hash = account?.passwordHash ?? 'scrypt$00$00';
    const ok = (await verifyPassword(parsed.data.password, hash)) && account !== null && !account.disabled;

    await repo.recordLoginAttempt(phone, ok);
    if (!ok) return reply.code(401).send({ error: 'invalid_credentials' });

    const { token, hash: tokenHash } = newSessionToken();
    await repo.createStaffSession({
      tokenHash,
      staffId: account!.id,
      expiresAt: new Date(Date.now() + SESSION_TTL_MS),
      userAgent: String(req.headers['user-agent'] ?? ''),
    });
    await repo.writeAudit({ staffId: account!.id, action: 'staff_login' });

    return reply
      .header('set-cookie', sessionCookie(token, { secure: isSecure(req) }))
      .send({
        ok: true,
        staff: { id: account!.id, role: account!.role, displayName: account!.displayName, phone },
      });
  });

  app.post('/admin/logout', async (req, reply) => {
    const token = readSessionCookie(req.headers.cookie);
    if (token) await repo.deleteStaffSession(hashToken(token));
    return reply
      .header('set-cookie', clearedCookie({ secure: isSecure(req) }))
      .send({ ok: true });
  });

  /// Who am I — the panel calls this on load to decide between the login form
  /// and the dashboard. 401 when signed out, which is not an error condition.
  app.get('/admin/me', async (req, reply) => {
    const token = readSessionCookie(req.headers.cookie);
    const session = token ? await repo.staffBySessionToken(hashToken(token)) : null;
    if (!session) return reply.code(401).send({ error: 'unauthenticated' });
    return reply.send({ staffId: session.staffId, role: session.role });
  });
}
