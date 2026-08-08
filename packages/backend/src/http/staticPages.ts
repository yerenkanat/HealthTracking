/**
 * The pages a person reaches by typing an address: the back-office panel, the
 * API docs, and what is left of the old storefront.
 *
 * These lived inline in index.ts, which is the boot file — it opens database
 * pools and reads the environment, so no test could import it. The result was
 * a set of routes outside every guard the rest of the codebase has: /admin/ui,
 * /shop, the social cards. Two 404s reached production and were found by a
 * person typing the obvious thing — /shop/ with a trailing slash, and /admin
 * without /ui — because nothing else was looking.
 *
 * Extracted so they can be registered on a bare Fastify instance and asserted
 * like anything else. index.ts keeps only the logging, which is all it was ever
 * adding.
 *
 * Each block still fails soft: a missing file disables its routes rather than
 * stopping the server, because the landing and the API are worth serving even
 * if the panel's HTML is absent. What it does NOT do any more is fail soft
 * silently — the result says what registered, so the caller can log it and a
 * test can refuse to pass when nothing did.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { registerJoinPage } from './joinPage';
import { registerLegalPages } from './legalPages';

export interface StaticPages {
  /** The admin panel HTML and the /admin → /admin/ui redirects. */
  adminUi: boolean;
  apiDocs: boolean;
  /** The retired storefront: redirects to the landing, plus its images. */
  shop: boolean;
  /** /privacy and /terms, served from legal/legal.json. */
  legal: boolean;
}

/** Colours with a real product photo on disk. */
const WATCH_COLOURS = ['black', 'white', 'gray', 'pink', 'red', 'teal', 'army'];

/**
 * The old storefront's pages. All of them now redirect to the landing, which
 * carries the whole offer.
 *
 * They sold the same two devices under the old "Umay" brand, in the old
 * terracotta design, at the old prices — 29 000 ₸ for the watch where the
 * Ana-Bala landing says 24 900. Two prices for one product on one domain is
 * worse than one page fewer, and it is not fixable by editing numbers: the
 * brand name is wrong throughout and each page's social card is a PNG with the
 * old price baked into the artwork.
 *
 * '/shop/' is listed separately because Fastify treats a trailing slash as a
 * different route and 404s it. That is exactly what a browser leaves on a
 * bookmarked section, so the 404 was reachable by anyone who saved the page.
 */
export const RETIRED_SHOP_PAGES = ['/shop', '/shop/', '/shop/watch', '/shop/tracker', '/shop/umay-watch'];

/**
 * Where the back office is served. /admin is the address, because it is what a
 * person types and what anyone would read out loud; /admin/ is the same place
 * with the slash a browser leaves on a bookmark.
 *
 * It lived at /admin/ui, with /admin redirecting there. The redirect worked and
 * was still wrong: the URL bar ended up showing a path with a suffix nobody
 * would have guessed, on the one page in the product whose address gets typed
 * by hand rather than followed from a link.
 */
export const ADMIN_PANEL_PATHS = ['/admin', '/admin/'];

/**
 * The old address. Kept as a redirect rather than deleted — it has been the
 * panel's URL for as long as the panel has existed, so it is in browser
 * histories and autocompletes, and possibly in a message to a colleague.
 */
export const ADMIN_LEGACY_PATH = '/admin/ui';

export function registerStaticPages(app: FastifyInstance): StaticPages {
  const done: StaticPages = { adminUi: false, apiDocs: false, shop: false, legal: false };

  // Where a family invitation link lands. Registered here with the other pages
  // people reach by typing or tapping an address, rather than beside the API
  // routes it is not one of. Built from a string, so unlike the panel it
  // cannot fail to load from disk.
  registerJoinPage(app);

  // /privacy and /terms. A store listing needs a public URL for these, and so
  // does anyone deciding whether to install an app that tracks their child.
  done.legal = registerLegalPages(app);

  // ---- The back office ------------------------------------------------------
  try {
    const adminBody = readFileSync(fileURLToPath(new URL('../../../admin/index.html', import.meta.url)), 'utf8');
    const adminHtml = `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width,initial-scale=1">` +
      `<title>Ana-Bala Back-office</title></head><body>${adminBody}</body></html>`;
    for (const p of ADMIN_PANEL_PATHS) {
      app.get(p, async (_req, reply) =>
        reply
          .type('text/html')
          // no-store, and it is not a nicety.
          //
          // This one file IS the application: every line of the panel's
          // JavaScript is inline in it. With no cache header at all, browsers
          // fall back to heuristic caching and happily reuse an old copy — so
          // a person can be running a build from before a fix while the server
          // has served the fix a dozen times. That is not hypothetical: an
          // owner spent an evening unable to sign in, on a cached build whose
          // login form still let the browser's own validation block the submit
          // silently. Nothing reached the server, so nothing could be
          // diagnosed from it.
          //
          // no-store rather than no-cache: this page also renders patients'
          // names and health data, and a back office has no business being
          // written to a shared laptop's disk cache.
          .header('cache-control', 'no-store, must-revalidate')
          .send(adminHtml));
    }

    // 302, not 301: the panel is due to move to admin.ana-bala.kz once that DNS
    // record exists, and a permanent redirect would be cached by every browser
    // that has ever opened it.
    app.get(ADMIN_LEGACY_PATH, async (_req, reply) => reply.redirect('/admin', 302));
    done.adminUi = true;
  } catch {
    /* caller logs; see StaticPages */
  }

  // ---- API docs -------------------------------------------------------------
  // Served OUTSIDE the /api/v1 key guard so the docs are always reachable; the
  // console sends x-api-key on requests when the operator enters one.
  try {
    const apiDocs = readFileSync(fileURLToPath(new URL('../../docs/api.html', import.meta.url)), 'utf8');
    app.get('/api-docs', async (_req, reply) => reply.type('text/html').send(apiDocs));
    done.apiDocs = true;
  } catch {
    /* caller logs */
  }

  // ---- The retired storefront ----------------------------------------------
  // The shop *API* is untouched — /shop/products, /shop/orders, /shop/config
  // and /shop/leads still serve the app, the admin panel and the landing form.
  try {
    const serveImage = (path: string, file: string, type = 'image/png') => {
      const bytes = readFileSync(fileURLToPath(new URL(`../../shop/${file}`, import.meta.url)));
      app.get(path, async (_req, reply) =>
        reply.type(type).header('cache-control', 'public, max-age=86400').send(bytes));
    };

    for (const path of RETIRED_SHOP_PAGES) {
      app.get(path, async (_req, reply) => reply.redirect('/', 302));
    }

    // The cards stay reachable: they are referenced by links shared before the
    // redirect existed, and a dead og:image is worse than a stale one.
    serveImage('/shop/og.png', 'og.png');
    serveImage('/shop/watch-og.png', 'watch-og.png');
    serveImage('/shop/tracker-og.png', 'tracker-og.png');
    serveImage('/shop/umay-watch-og.png', 'umay-watch-og.png');

    for (const c of WATCH_COLOURS) {
      serveImage(`/shop/photos/watch-${c}.jpg`, `photos/watch-${c}.jpg`, 'image/jpeg');
    }
    done.shop = true;
  } catch {
    /* caller logs */
  }

  return done;
}
