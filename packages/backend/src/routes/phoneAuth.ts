/**
 * Signing in to the app with a phone number.
 *
 * One endpoint, because that is the whole product decision: a mother types her
 * number and she is in. There is no code and no SMS — the number is CLAIMED,
 * not verified.
 *
 * That is worth stating plainly rather than hiding: today somebody could sign
 * in as a number that is not theirs. What that gets them is an empty account,
 * because nothing is there until they put it there; what it costs, if the real
 * owner later signs up, is that they find someone else's data. The endpoint is
 * the only place a verification step would live, so adding an SMS gateway
 * later changes this handler and nothing in the app.
 *
 * Until then the mitigations are narrow and honest: the number is normalised so
 * one person is one account, and claims are rate-limited per source so the
 * eleven-digit Kazakh mobile space cannot be walked.
 */

import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository } from '../db/repository';
import { hashToken, newSessionToken, normalizePhone } from '../http/staffAuth';

/** Ninety days. A phone is personal, and the app is opened at 3am one-handed. */
export const USER_SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;

/** Claims allowed from one source before it is told to slow down. */
export const MAX_CLAIMS = 20;
export const CLAIM_WINDOW_MS = 60 * 60 * 1000;

const body = z.object({
  phone: z.string().min(4).max(32),
  /** Optional: what she called herself during onboarding. */
  displayName: z.string().trim().max(80).optional(),
});

export function registerPhoneAuthRoutes(app: FastifyInstance, repo: Repository): void {
  app.post('/auth/phone', async (req, reply) => {
    const parsed = body.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const phone = normalizePhone(parsed.data.phone);
    // Ten digits is the shortest thing that can be a Kazakh mobile. Rejecting
    // here rather than creating an account for "77" costs nothing and stops a
    // typo becoming a permanent empty account.
    if (phone.length < 10) return reply.code(400).send({ error: 'bad_phone' });

    const since = new Date(Date.now() - CLAIM_WINDOW_MS);
    if ((await repo.recentPhoneClaims(phone, since)) >= MAX_CLAIMS) {
      return reply.code(429).send({
        error: 'too_many_attempts',
        retryAfterMinutes: Math.ceil(CLAIM_WINDOW_MS / 60000),
      });
    }
    await repo.recordPhoneClaim(phone);

    // Find or create. Signing in and registering are the same act here: there
    // is no separate "register" screen in the app, and asking a tired person to
    // remember which one she did last time would be a worse product.
    const user = await repo.userByPhone(phone)
      ?? await repo.createUserWithPhone({ phone, displayName: parsed.data.displayName ?? '' });

    const { token, hash } = newSessionToken();
    await repo.createUserSession({
      tokenHash: hash,
      userId: user.id,
      expiresAt: new Date(Date.now() + USER_SESSION_TTL_MS),
      userAgent: String(req.headers['user-agent'] ?? ''),
    });

    // The token goes in the body, not a cookie: the caller is a mobile app that
    // will send it as `Authorization: Bearer`, and it has no cookie jar.
    return reply.send({
      userId: user.id,
      phone,
      displayName: user.displayName,
      token,
      expiresInMs: USER_SESSION_TTL_MS,
    });
  });

  app.post('/auth/logout', async (req, reply) => {
    const token = bearer(req);
    if (token) await repo.deleteUserSession(hashToken(token));
    return reply.send({ ok: true });
  });
}

/** The Bearer token, or null. */
function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization;
  if (typeof h !== 'string' || !h.startsWith('Bearer ')) return null;
  const t = h.slice('Bearer '.length).trim();
  return t.length > 0 ? t : null;
}
