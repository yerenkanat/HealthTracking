/**
 * The headers a browser is given, asserted on the bytes that leave the server.
 *
 * The back office had no Content-Security-Policy and no frame-ancestors of any
 * kind — not in deploy/, not in the app, not in the panel's own markup. That is
 * the control which would have CONTAINED the stored XSS fixed in 7dd7061: a
 * stranger's name broke out of an attribute and ran with the signed-in owner's
 * session over every family's data. The escaping was the fix; this is the wall
 * behind it, so the next one of those is inert.
 *
 * `frame-ancestors` matters here more than it usually does. The panel is a PATH
 * on the main site — `/admin`, not `admin.ana-bala.kz` — so anything that can
 * frame the landing page can frame the back office and click through it as
 * whoever is signed in.
 *
 * Everything below reads a real response from a real instance. A policy that
 * exists in a source file and never reaches a header is the same as no policy,
 * and this repo's dominant defect is exactly that shape.
 */

import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { registerStaticPages } from '../http/staticPages';
import { API_CSP, PAGE_CSP } from '../http/securityHeaders';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');
const TAKEOVER = readFileSync(resolve(here, '../../../../deploy/landing-takeover.sh'), 'utf8');

async function makeApp(): Promise<FastifyInstance> {
  const app = buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: 'u1' }),
      authAdmin: async () => null,
    },
    { logger: false },
  );
  // The panel and the legal pages are registered by index.ts in production, on
  // this same instance. Registering them here is what makes the test cover the
  // pages rather than only the API.
  registerStaticPages(app);
  await app.ready();
  return app;
}

/** Directives as a map, so an assertion names one rather than matching a blob. */
function directives(csp: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of csp.split(';')) {
    const [name, ...rest] = part.trim().split(/\s+/);
    if (name) out[name.toLowerCase()] = rest.join(' ');
  }
  return out;
}

describe('the back office is served under a nonce policy', () => {
  it('sends a Content-Security-Policy at all, with the panel', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin' });
    expect(res.statusCode, 'the panel did not render; the rest of this file is vacuous').toBe(200);
    expect(res.headers['content-security-policy'], 'no CSP on the one page that renders strangers’ text').toBeTruthy();
    await app.close();
  });

  it('refuses framing, plugins and <base>, and locks the origin down', async () => {
    const app = await makeApp();
    const d = directives(String((await app.inject({ method: 'GET', url: '/admin' })).headers['content-security-policy']));
    // /admin is a path on ana-bala.kz. Without this, a page anywhere can frame
    // the back office and drive it with the owner's own session.
    expect(d['frame-ancestors']).toBe("'none'");
    expect(d['base-uri']).toBe("'none'");
    expect(d['default-src']).toBe("'none'");
    expect(d['form-action']).toBe("'self'");
    // The panel talks only to /admin/* on its own origin. An exfiltration
    // channel is the second half of a stored XSS, and this closes it.
    expect(d['connect-src']).toBe("'self'");
    await app.close();
  });

  it('carries a nonce and NOT unsafe-inline, or it would contain nothing', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin' });
    const script = directives(String(res.headers['content-security-policy']))['script-src'];
    expect(script).toMatch(/'nonce-[A-Za-z0-9+/=]{16,}'/);
    // The whole point. `script-src 'self' 'unsafe-inline'` would have been
    // easier and would have permitted exactly the injected <script> and
    // onerror= that this is here to stop.
    expect(script, "'unsafe-inline' in script-src makes the nonce decorative").not.toContain("'unsafe-inline'");
    await app.close();
  });

  it('puts that same nonce on every inline <script> in the page it just sent', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin' });
    const nonce = /'nonce-([^']+)'/.exec(String(res.headers['content-security-policy']))![1];
    const body = res.body;

    // Every inline script tag must carry it. One that does not is a block of
    // the panel that silently stops running, with the explanation only in a
    // console nobody has open.
    const inline = [...body.matchAll(/<script(?![^>]*\ssrc=)([^>]*)>/g)].map((m) => m[1]);
    expect(inline.length, 'no inline script found — the panel is not what this thinks it is').toBeGreaterThanOrEqual(2);
    for (const attrs of inline) expect(attrs).toContain(`nonce="${nonce}"`);

    // And the placeholder must never reach a browser.
    expect(body).not.toContain('__CSP_NONCE__');
    await app.close();
  });

  it('uses a different nonce for every response', async () => {
    const app = await makeApp();
    const a = await app.inject({ method: 'GET', url: '/admin' });
    const b = await app.inject({ method: 'GET', url: '/admin' });
    const nonceOf = (r: typeof a) => /'nonce-([^']+)'/.exec(String(r.headers['content-security-policy']))![1];
    // A nonce fixed at boot is a constant an attacker reads once from the page
    // and then embeds in the payload — which is the same as having none.
    expect(nonceOf(a)).not.toBe(nonceOf(b));
    // Each body must match ITS OWN header. Getting these out of step is a
    // blank panel, so it is asserted rather than assumed.
    expect(a.body).toContain(`nonce="${nonceOf(a)}"`);
    expect(b.body).toContain(`nonce="${nonceOf(b)}"`);
    expect(a.body).not.toContain(`nonce="${nonceOf(b)}"`);
    await app.close();
  });

  it('answers HEAD with the same headers, because that is what the deploy check reads', async () => {
    // deploy/landing-takeover.sh verifies the live panel with `curl -sI`. If
    // HEAD did not carry these, the check would print MISSING on a correctly
    // configured server — and a check whose healthy output looks like a failure
    // gets ignored, which is worse than not having it.
    const app = await makeApp();
    const res = await app.inject({ method: 'HEAD', url: '/admin' });
    expect(res.statusCode).toBe(200);
    expect(String(res.headers['content-security-policy'])).toContain('nonce-');
    expect(res.headers['x-frame-options']).toBe('DENY');
    await app.close();
  });

  it('still sends no-store, because the nonce is per response', async () => {
    // Already true for another reason (the panel is one file containing all its
    // JavaScript, and a cached copy is an old build of everything). Now it is
    // load-bearing twice: a cached page carries a stale nonce and every script
    // in it is refused.
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin' });
    expect(String(res.headers['cache-control'])).toContain('no-store');
    await app.close();
  });
});

describe('the panel contains nothing the nonce policy would kill', () => {
  /** The source, minus comments — where the two examples below are DISCUSSED. */
  const code = readFileSync(PANEL, 'utf8')
    .split('\n')
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .join('\n');

  it('has no inline event-handler attributes', () => {
    // `onerror="…"` IS script. Under `script-src 'nonce-…'` the attribute is
    // ignored, so the panel had two <img> tags whose "фото не загрузилось"
    // placeholder would simply never appear — a silent, invisible regression of
    // exactly the kind a CSP rollout is blamed for. They are one delegated
    // listener now (search the panel for data-onfail).
    const found = [...code.matchAll(/\son(?:error|click|load|change|submit|input|focus|blur|toggle)\s*=/g)]
      .map((m) => m[0].trim());
    expect(found, 'an inline handler here is a feature that stops working under the CSP').toEqual([]);
  });

  it('has no eval, no new Function, and no javascript: URL', () => {
    // Each of these needs 'unsafe-eval' or 'unsafe-inline', and adding either
    // would give most of the policy back.
    expect(code).not.toMatch(/\beval\s*\(/);
    expect(code).not.toMatch(/\bnew\s+Function\s*\(/);
    expect(code).not.toContain('javascript:');
  });

  it('loads no script from another origin', () => {
    // script-src is 'self' plus the nonce. A CDN <script> would 404 into a
    // blank panel; catching it here is cheaper than catching it in production.
    const external = [...code.matchAll(/<script[^>]*\ssrc="(https?:)?\/\/[^"]*"/g)].map((m) => m[0]);
    expect(external).toEqual([]);
  });
});

describe('everything else gets a policy too', () => {
  it('a JSON response is locked to nothing and cannot be framed', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.headers['content-security-policy']).toBe(API_CSP);
    expect(res.headers['x-frame-options']).toBe('DENY');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    await app.close();
  });

  it('so does a 404 — the response an attacker probes with', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/no-such-route' });
    expect(res.statusCode).toBe(404);
    expect(res.headers['content-security-policy']).toBe(API_CSP);
    expect(res.headers['x-frame-options']).toBe('DENY');
    await app.close();
  });

  it('a public HTML page gets the page policy, not the API one', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/privacy' });
    expect(res.statusCode, '/privacy did not render; this assertion proves nothing').toBe(200);
    expect(res.headers['content-security-policy']).toBe(PAGE_CSP);
    await app.close();
  });

  it('the public page policy deliberately does NOT restrict script-src', () => {
    // Stated as an assertion so nobody "hardens" it without reading why: `/` is
    // an exported artifact whose inline scripts change on every re-export
    // (tools/build-landing.mjs). A script-src there would break the landing on
    // the next export and be switched off within the week — and a CSP that gets
    // switched off is worth less than a narrower one that stays.
    //
    // What it costs: no script-injection containment on /, /shop*, /join/*,
    // /privacy, /terms, /api-docs. None of those renders attacker-controlled
    // data today. The day one does, it needs its own policy.
    const d = directives(PAGE_CSP);
    expect(d['script-src'], 'read http/securityHeaders.ts before adding this').toBeUndefined();
    expect(d['frame-ancestors']).toBe("'none'");
    expect(d['object-src']).toBe("'none'");
    expect(d['base-uri']).toBe("'none'");
  });
});

describe('the edge says the same thing', () => {
  // deploy/landing-takeover.sh writes the live Caddyfile. It ends in a
  // catch-all `respond "Not found" 404`, and that response never touches
  // Fastify — so the edge needs its own copy of the framing refusal or the one
  // response the app cannot reach is the one without it.
  it('sets X-Frame-Options at the proxy as well', () => {
    expect(TAKEOVER).toMatch(/X-Frame-Options\s+"DENY"/);
  });

  it('sets a CSP default that does not clobber the app’s', () => {
    // `?Header` in Caddy means "only if the response does not already have
    // one". Plain `Header` REPLACES — which would flatten the panel's nonce
    // policy into the generic one and blank the back office.
    expect(TAKEOVER, 'a bare Content-Security-Policy here overwrites the panel’s')
      .toMatch(/\?Content-Security-Policy\s+"[^"]*frame-ancestors 'none'[^"]*"/);
  });

  it('has finished the HSTS staging plan it wrote down', () => {
    // The file's own plan: 0 → 86400 on 2026-08-05 → 31536000 after about a
    // week clean. It sat at 86400 for over two weeks, which is a plan that
    // stopped being followed rather than a decision.
    const m = /Strict-Transport-Security\s+"max-age=(\d+)/.exec(TAKEOVER);
    expect(m, 'no HSTS header in the generated config').toBeTruthy();
    expect(Number(m![1])).toBeGreaterThanOrEqual(31536000);
    // `preload` is a hardcoded browser list and getting off it takes months.
    expect(TAKEOVER).not.toMatch(/Strict-Transport-Security\s+"[^"]*preload/);
  });
});
