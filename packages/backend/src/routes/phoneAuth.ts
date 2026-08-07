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
import { randomInt } from 'node:crypto';
import { hashToken, newSessionToken, normalizePhone } from '../http/staffAuth';

/** Ninety days. A phone is personal, and the app is opened at 3am one-handed. */
export const USER_SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;

/** Claims allowed from one source before it is told to slow down. */
export const MAX_CLAIMS = 20;
export const CLAIM_WINDOW_MS = 60 * 60 * 1000;

/**
 * How long a code is worth typing. Five minutes: long enough for an SMS to
 * arrive on a slow network and be typed one-handed, short enough that a message
 * left on a lock screen stops being a key.
 */
export const CODE_TTL_MS = 5 * 60 * 1000;

/**
 * Wrong guesses before the code is dead.
 *
 * Six digits is a million combinations, but a bot does not need a million
 * tries — it needs enough. Five, then she asks for a new one.
 */
export const MAX_CODE_ATTEMPTS = 5;

const body = z.object({
  phone: z.string().min(4).max(32),
  /** Optional: what she called herself during onboarding. */
  displayName: z.string().trim().max(80).optional(),
});

const verifyBody = body.extend({
  /** Exactly the shape [SmsSender.newCode] produces; anything else is a typo. */
  code: z.string().trim().regex(/^\d{6}$/),
});

/**
 * Sending the code, and inventing it.
 *
 * An interface because the gateway is the one part that needs an account with
 * somebody: everything around it — storage, expiry, attempt limits, the
 * screens — is finished and testable without one. Swapping in a real provider
 * later changes this object and nothing else.
 */
export interface SmsSender {
  /** A fresh six-digit code. */
  newCode(): string;
  /** True when the message was accepted for delivery. */
  send(phoneE164: string, code: string): Promise<boolean>;
}

/**
 * The development sender: writes the code to the server log and sends nothing.
 *
 * It exists so the flow can be exercised end to end without a gateway. It must
 * never be the sender in production — a code nobody receives is an account
 * nobody can open — so [registerPhoneAuthRoutes] requires the caller to pass a
 * sender explicitly rather than defaulting to this one.
 */
export function logOnlySmsSender(log: (msg: string) => void): SmsSender {
  return {
    newCode: () => String(randomInt(0, 1_000_000)).padStart(6, '0'),
    send: async (phone, code) => {
      log(`[dev-sms] code for ${phone}: ${code}`);
      return true;
    },
  };
}

export function registerPhoneAuthRoutes(
  app: FastifyInstance,
  repo: Repository,
  sms: SmsSender,
): void {
  /**
   * Step one: send a code to the number.
   *
   * Answers the same thing whether or not the number has an account. Telling
   * them apart turns this endpoint into a way to ask "is this customer of
   * yours?" about any number somebody has.
   *
   * The code is never in the response. Returning it "for convenience in dev" is
   * how it ends up returned in production.
   */
  app.post('/auth/phone/start', async (req, reply) => {
    const parsed = body.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const phone = normalizePhone(parsed.data.phone);
    if (phone.length < 10) return reply.code(400).send({ error: 'bad_phone' });

    const since = new Date(Date.now() - CLAIM_WINDOW_MS);
    if ((await repo.recentPhoneClaims(phone, since)) >= MAX_CLAIMS) {
      return reply.code(429).send({
        error: 'too_many_attempts',
        retryAfterMinutes: Math.ceil(CLAIM_WINDOW_MS / 60000),
      });
    }
    await repo.recordPhoneClaim(phone);

    const code = sms.newCode();
    await repo.putPhoneCode({
      phone,
      codeHash: hashToken(code),
      expiresAt: new Date(Date.now() + CODE_TTL_MS),
    });

    const sent = await sms.send(phone, code).catch(() => false);
    if (!sent) {
      // Say so rather than leaving her on a code screen waiting for a message
      // that was never sent. This is also what an unconfigured gateway looks
      // like, and it must not be mistaken for "wrong number".
      return reply.code(503).send({ error: 'sms_unavailable' });
    }
    return reply.send({ ok: true, expiresInSec: Math.floor(CODE_TTL_MS / 1000) });
  });

  /**
   * Step two: the code proves she has the phone. Only now is a session issued.
   *
   * This used to be the whole of `POST /auth/phone`: eleven digits in, a
   * ninety-day session out. A customer's number is on every parcel, every
   * WhatsApp order and every delivery manifest, so anyone holding one could
   * open her account and read her pregnancy, her children and where they are
   * right now.
   */
  app.post('/auth/phone/verify', async (req, reply) => {
    const parsed = verifyBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const phone = normalizePhone(parsed.data.phone);
    if (phone.length < 10) return reply.code(400).send({ error: 'bad_phone' });

    const outcome = await repo.usePhoneCode(phone, hashToken(parsed.data.code), new Date());
    if (outcome !== 'ok') {
      // 'none' and 'expired' are the same thing to her — the code she has is no
      // longer worth typing — and collapsing them keeps the answer from saying
      // whether a code was ever requested for this number.
      const error = outcome === 'too_many' ? 'too_many_attempts'
        : outcome === 'wrong' ? 'wrong_code'
          : 'code_expired';
      return reply.code(401).send({ error });
    }

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

  /**
   * Revoke this session.
   *
   * The token may arrive in the Authorization header OR in the body, and the
   * body is not a convenience — it is what makes the client able to call this
   * at all.
   *
   * The app reads its bearer token fresh out of the signed-in session on every
   * request. Signing out clears that session, so a logout fired after the
   * clear carries no header, and one fired before it races the clear: the
   * header is built in a microtask that runs after the synchronous sign-out
   * has already emptied the field. Either way the request arrived
   * unauthenticated and revoked nothing — which is exactly how the session
   * survived every sign-out until now.
   *
   * Presenting a token in a body is no weaker than presenting it in a header:
   * it is the same secret, and holding it is the whole authorisation this
   * needs. Always 200, so a client can never learn from the answer whether a
   * token it guessed was real.
   */
  app.post('/auth/logout', async (req, reply) => {
    const fromBody = (req.body as { token?: unknown } | null)?.token;
    const token = bearer(req)
      ?? (typeof fromBody === 'string' && fromBody.trim() ? fromBody.trim() : null);
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
