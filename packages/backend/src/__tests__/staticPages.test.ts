/**
 * The addresses a person types.
 *
 * These routes had no tests at all, because they were written inline in
 * index.ts — the boot file, which opens a database pool and reads the
 * environment, so no test could import it. The consequence was not theoretical:
 * two 404s reached production and were found by the owner typing the obvious
 * thing.
 *
 *   /shop/  — a trailing slash, which is what a browser leaves on a bookmark
 *   /admin  — without /ui, which is what anybody would type first
 *
 * Both answered with a JSON 404 that reads as a broken site. Neither the test
 * suite nor the deploy checks were looking, and the fix each time was to add
 * that one case to the deploy script afterwards — which only ever catches what
 * somebody has already tripped over.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import { registerStaticPages, ADMIN_ENTRY_PATHS, RETIRED_SHOP_PAGES, type StaticPages } from '../http/staticPages';

let app: FastifyInstance;
let registered: StaticPages;

beforeAll(async () => {
  app = Fastify({ logger: false });
  registered = registerStaticPages(app);
  await app.ready();
});

describe('the pages registered at all', () => {
  it('found every file it serves from', () => {
    // The vacuity guard, and the reason it is first. Every block below fails
    // soft on a missing file, so without this the whole suite would pass on a
    // server that serves none of these pages: "404 expected" and "route never
    // existed" look identical from the outside.
    expect(registered.adminUi, 'admin/index.html was not found').toBe(true);
    expect(registered.apiDocs, 'docs/api.html was not found').toBe(true);
    expect(registered.shop, 'shop images were not found').toBe(true);
  });

  it('has an address list to check', () => {
    // The second vacuity guard, and it is here because the first version of
    // this file did not have it. Emptying ADMIN_ENTRY_PATHS — which is exactly
    // the bug that was reported — made `it.each(ADMIN_ENTRY_PATHS)` register
    // ZERO tests, and the suite went green while /admin 404'd. A parameterised
    // test proves nothing about a list nobody checked the contents of.
    expect(ADMIN_ENTRY_PATHS).toEqual(['/admin', '/admin/']);
    expect(RETIRED_SHOP_PAGES).toEqual(
      expect.arrayContaining(['/shop', '/shop/', '/shop/watch', '/shop/tracker', '/shop/umay-watch']),
    );
  });
});

describe('the back office', () => {
  it('serves the panel at /admin/ui', async () => {
    const res = await app.inject({ method: 'GET', url: '/admin/ui' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    // Not merely 200: the page has to be the panel, opening on its sign-in form.
    expect(res.body).toContain('id="loginForm"');
    expect(res.body).toContain('<!doctype html>');
  });

  it.each(ADMIN_ENTRY_PATHS)('%s redirects to the panel', async (path) => {
    // The reported bug. /admin is what a person types; /admin/ is what a
    // browser leaves behind. Both used to be a JSON 404.
    const res = await app.inject({ method: 'GET', url: path });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe('/admin/ui');
  });

  it('redirects temporarily, so the panel can move later', async () => {
    // 301 would be cached by every browser that has ever visited, and the plan
    // is to move this to admin.ana-bala.kz.
    const res = await app.inject({ method: 'GET', url: '/admin' });
    expect(res.statusCode).not.toBe(301);
  });
});

describe('the retired storefront', () => {
  it.each(RETIRED_SHOP_PAGES)('%s sends people to the landing', async (path) => {
    const res = await app.inject({ method: 'GET', url: path });
    expect(res.statusCode).toBe(302);
    expect(res.headers.location).toBe('/');
  });

  it('covers the trailing slash, which is the one that was missing', async () => {
    // Named separately from the loop above so that removing it from the list
    // fails a test with the reason attached, rather than silently shortening
    // a parameterised run nobody counts.
    expect(RETIRED_SHOP_PAGES).toContain('/shop/');
  });

  it('still serves the social cards shared before the redirect existed', async () => {
    // A dead og:image is worse than a stale one: the link previews break on
    // every message anyone has already sent.
    const res = await app.inject({ method: 'GET', url: '/shop/og.png' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('image/png');
    expect(res.headers['cache-control']).toContain('max-age=86400');
    expect(res.rawPayload.length).toBeGreaterThan(1000);
  });

  it('serves the product photos the panel links', async () => {
    const res = await app.inject({ method: 'GET', url: '/shop/photos/watch-black.jpg' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('image/jpeg');
  });

  it('leaves the shop API alone', async () => {
    // The redirects are for the retired HTML pages. /shop/products and friends
    // are live API routes registered elsewhere, and a greedy /shop* redirect
    // here would break the storefront, the app and the landing's lead form at
    // once. Nothing under /shop/ that is not listed should be answered here.
    const res = await app.inject({ method: 'GET', url: '/shop/products' });
    expect(res.statusCode, 'staticPages should not answer for the shop API').toBe(404);
  });
});

describe('the API docs', () => {
  it('are reachable without a key', async () => {
    // Served outside the /api/v1 key guard on purpose: docs nobody can open
    // until they already have a key are documentation for people who do not
    // need it.
    const res = await app.inject({ method: 'GET', url: '/api-docs' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
  });
});
