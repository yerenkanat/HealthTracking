/**
 * The headers that decide what a browser is allowed to do with our responses.
 *
 * WHY THIS EXISTS. On 2026-08-19 a stored XSS was fixed in the back office
 * (commit 7dd7061): a customer typed script into a name field, the panel put it
 * into an attribute unescaped, and it ran in the browser of whoever opened the
 * leads queue — with that person's session, over every family's data. The
 * escaping is fixed. This file is the second wall, so the NEXT one of those is
 * inert instead of catastrophic.
 *
 * `frame-ancestors 'none'` is not decoration here. The panel is a PATH on the
 * main site (`/admin`), not a separate origin, so anything that can frame
 * ana-bala.kz can frame the back office and click through it as the signed-in
 * owner. There is no `admin.ana-bala.kz` yet; until there is, framing is the
 * whole clickjacking surface.
 *
 * ── Two policies, on purpose ────────────────────────────────────────────────
 *
 * [panelCsp] is strict: a per-response nonce, no 'unsafe-inline' for scripts.
 * The panel is one file we own, with exactly two inline <script> blocks, no
 * eval, no `new Function`, no external script origins — so a nonce fits it
 * without a single change to how it is written, and injected markup cannot run.
 *
 * [PAGE_CSP] is deliberately WEAKER, and says so out loud. `/` is an exported
 * artifact: tools/build-landing.mjs unpacks somebody else's bundle, its inline
 * scripts change on every re-export, and it is re-exported often. A hash policy
 * would break on the next export; a nonce policy would need us to rewrite a
 * bundle we do not control. A script-src there would be switched off within the
 * week — and a CSP that gets switched off is worth less than a narrower one
 * that stays. So the public pages get the directives that cost nothing to keep:
 * no framing, no <base> injection, no plugins, forms can only post to us.
 *
 * WHAT PAGE_CSP DOES NOT PROTECT AGAINST, stated plainly: script injection on
 * the landing page, the storefront pages, /join, /privacy, /terms and
 * /api-docs. If markup is ever injected into one of those, it runs. The reason
 * that is an acceptable trade TODAY is that none of them renders attacker-
 * controlled data — the landing is static export, the legal pages are static
 * text, /join renders a code the caller already holds — and the one page that
 * does render strangers' data, the panel, is covered by the strict policy. The
 * day a public page starts rendering user input, that page needs its own
 * script-src and this comment is the reason to notice.
 *
 * [API_CSP] goes on everything that is not a page. A JSON response cannot
 * execute anything, but it can be framed, and `default-src 'none'` is free.
 */

import type { FastifyInstance } from 'fastify';
import { randomBytes } from 'node:crypto';

/**
 * The strict policy, for the back office.
 *
 * @param nonce the per-RESPONSE nonce, also written into the panel's own
 *   <script> tags. It must be unguessable and must not be reused across
 *   responses, which is why it is generated per request rather than at boot —
 *   a nonce fixed at startup is a nonce an attacker can read once and embed.
 */
export function panelCsp(nonce: string): string {
  return [
    "default-src 'none'",
    // 'self' as well as the nonce: the panel is inline today, but a future
    // <script src="/admin/…"> should not silently fail to load.
    `script-src 'self' 'nonce-${nonce}'`,
    // 'unsafe-inline' for STYLE only, and it is not laziness: the panel carries
    // 436 style="…" attributes and one 970-line <style> block. Nonce-ing the
    // block would not help, because per CSP3 a nonce in style-src makes
    // 'unsafe-inline' be ignored — and then every one of those attributes
    // stops applying and the panel is unreadable. Inline CSS cannot execute;
    // the exposure it leaves is style-based data inference, which is a long way
    // from running as the owner.
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' https://fonts.gstatic.com",
    // https: because product photos are URLs an operator pastes in, and
    // YouTube lesson thumbnails come from img.youtube.com.
    "img-src 'self' https:",
    // The daily-calendar audio the panel plays back is served by us.
    "media-src 'self'",
    // Every request the panel makes is to /admin/* on this origin.
    "connect-src 'self'",
    "form-action 'self'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
  ].join('; ');
}

/**
 * The public server-rendered pages. Read the header comment before widening or
 * narrowing this — in particular, adding a `script-src` here breaks `/` on the
 * next re-export of the landing artifact.
 */
export const PAGE_CSP = [
  "base-uri 'none'",
  "object-src 'none'",
  "form-action 'self'",
  "frame-ancestors 'none'",
].join('; ');

/** Everything that is not an HTML page: JSON, images, scripts, 404s. */
export const API_CSP = [
  "default-src 'none'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
].join('; ');

/** A fresh CSP nonce. 128 bits, base64 — the shape the spec asks for. */
export const cspNonce = (): string => randomBytes(16).toString('base64');

/**
 * Attach the headers to every response this instance sends.
 *
 * Registered in buildServer, so it covers the API, the 404 handler, and — in
 * production, where index.ts adds them to the same instance — the landing page
 * and the static pages too.
 *
 * A response that ALREADY carries a Content-Security-Policy keeps it. That is
 * how the panel's nonce policy survives: http/staticPages.ts sets its own,
 * and this hook must not flatten it into the generic one.
 */
export function registerSecurityHeaders(app: FastifyInstance): void {
  app.addHook('onSend', async (_req, reply, payload) => {
    // Also set at the edge. Set here too because the edge config is a file on
    // one box that has twice been out of date with this repo, and because the
    // memory-mode backend that people test against has no edge at all.
    reply.header('x-content-type-options', 'nosniff');
    // The pre-CSP way of saying frame-ancestors, for browsers that predate it.
    // Same value the edge sets, so neither can surprise the other.
    reply.header('x-frame-options', 'DENY');

    if (!reply.getHeader('content-security-policy')) {
      const type = String(reply.getHeader('content-type') ?? '');
      reply.header('content-security-policy', type.includes('text/html') ? PAGE_CSP : API_CSP);
    }
    return payload;
  });
}
