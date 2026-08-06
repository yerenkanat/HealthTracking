/**
 * Staff sign-in: a phone number and a password, the same two fields the app
 * asks a mother for.
 *
 * What this replaces, and why it is not merely cosmetic. The back office was
 * behind Caddy's basic_auth, and the panel trusted the `x-staff-role` header
 * outright — so the browser dialog was the entire boundary, and anyone past it
 * could call themselves an admin. A dialog also cannot be branded, cannot say
 * "номер телефона" instead of "username", never expires, and re-sends the
 * password on every request including every polled one.
 *
 * Passwords are scrypt with a per-account salt. Node ships it, so this adds no
 * dependency, and unlike a plain SHA it is deliberately slow — the whole point
 * when the username is a phone number and Kazakh mobiles are eleven digits with
 * a fixed prefix.
 */

import { randomBytes, scrypt, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';

const scryptAsync = promisify(scrypt) as (
  password: string,
  salt: Buffer,
  keylen: number,
) => Promise<Buffer>;

/** Cost chosen so a single verify costs ~100ms on the production box. */
const KEYLEN = 64;

/** How long a sign-in lasts. Long enough for a working day, not a week. */
export const SESSION_TTL_MS = 12 * 60 * 60 * 1000;

/** Attempts allowed per phone before the account is refused for a while. */
export const MAX_ATTEMPTS = 8;
export const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;

/**
 * Digits only.
 *
 * "+7 707 345 22 44", "8 707 345 22 44" and "77073452244" are one person, and
 * staff will type whichever their phone shows them. Normalising on both sides
 * of the comparison is the only way the login can accept all three without
 * being loose about what it matches.
 *
 * The leading 8 is the domestic prefix for the same number; Kazakh mobiles are
 * 11 digits starting 7.
 */
export { normalizePhone } from '../phone';

/** `scrypt$<salt-hex>$<hash-hex>` — self-describing, so the format can change. */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await scryptAsync(password, salt, KEYLEN);
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

/**
 * Constant-time verify.
 *
 * Returns false rather than throwing on a malformed stored value: a corrupt row
 * must read as "wrong password", never as a 500 that tells an attacker the
 * account exists.
 */
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  try {
    const [scheme, saltHex, hashHex] = (stored ?? '').split('$');
    if (scheme !== 'scrypt' || !saltHex || !hashHex) return false;
    const expected = Buffer.from(hashHex, 'hex');
    const actual = await scryptAsync(password, Buffer.from(saltHex, 'hex'), expected.length);
    return timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

/** A session token, and the hash of it that goes in the database. */
export function newSessionToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: hashToken(token) };
}

/**
 * Sessions are stored hashed.
 *
 * Anyone who reads the table — a backup, a support query, a leaked dump —
 * otherwise holds a live key to the back office. sha256 is right here and
 * scrypt is not: the token is 256 bits of randomness, so there is nothing to
 * brute-force, and this runs on every request.
 */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export const SESSION_COOKIE = 'umay_staff';

/**
 * The Set-Cookie for a fresh session.
 *
 * HttpOnly so the panel's own JavaScript cannot read it (and neither can
 * anything injected into that single large HTML file). SameSite=Strict because
 * the back office is never legitimately reached from another site, which also
 * makes CSRF on the write routes a non-issue. Secure unless we are on plain
 * localhost, where a Secure cookie would simply never be stored.
 */
export function sessionCookie(token: string, opts: { secure: boolean }): string {
  const parts = [
    `${SESSION_COOKIE}=${token}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Strict',
    `Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}`,
  ];
  if (opts.secure) parts.push('Secure');
  return parts.join('; ');
}

/** The Set-Cookie that clears it. */
export function clearedCookie(opts: { secure: boolean }): string {
  const parts = [`${SESSION_COOKIE}=`, 'Path=/', 'HttpOnly', 'SameSite=Strict', 'Max-Age=0'];
  if (opts.secure) parts.push('Secure');
  return parts.join('; ');
}

/** Pull our cookie out of a Cookie header without a parser dependency. */
export function readSessionCookie(header: string | undefined): string | null {
  if (!header) return null;
  for (const part of header.split(';')) {
    const [name, ...rest] = part.trim().split('=');
    if (name === SESSION_COOKIE) return rest.join('=') || null;
  }
  return null;
}
