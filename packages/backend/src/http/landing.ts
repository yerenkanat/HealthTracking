/**
 * The Ana-Bala landing page — the site root.
 *
 * The page is authored as an exported artifact and unpacked into static files
 * by tools/build-landing.mjs (see that file for why we unpack rather than serve
 * the 2.7 MB self-extracting export). This module serves the result:
 *
 *   GET /                     the page, with crawler-readable meta injected
 *   GET /landing/wire.js      our form-wiring script (landing/wire.js)
 *   GET /landing/a/<file>     fonts, images, React, the artifact runtime
 *
 * Everything is read once at boot, exactly like the storefront pages, so no
 * request path ever reaches the filesystem. Restart the backend after a rebuild.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { esc, requestBase } from './pageMeta';

/** Extensions the build emits. Anything else is not served rather than guessed. */
const TYPES: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.gif': 'image/gif',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

/**
 * The page's social description. The artifact declares a <title> (which the
 * build hoists into <head>) but no description, so this is the one piece of
 * page copy that lives here — keep it in step with the landing's actual offer.
 */
const DESC =
  'Ana-Bala Watch следит за пульсом, давлением, сном и женским календарём, ' +
  'а брелок показывает, где ребёнок — без SIM-карты и абонентской платы. ' +
  'Часы 24 900 ₸, брелок 4 900 ₸, комплект «Мама и ребёнок» 39 000 ₸ с курсом Ма!Ма! в подарок. ' +
  'Оплата при получении, доставка по Казахстану, гарантия 12 месяцев.';

/**
 * The social card: the Watch S5 product photo the landing itself ships.
 *
 * This used to point at `/shop/og.png`, the old storefront's card — which shows
 * the previous "Umay" brand and the previous prices baked into the artwork. Every
 * share of the new page was previewing the old product.
 *
 * 1500×1500 rather than the conventional 1200×630: it is a real photo from the
 * page, and a square card that is accurate beats a wide one that is wrong.
 * Scrapers crop; the declared dimensions below are the real ones so they crop
 * correctly.
 */
const OG_IMAGE = '/landing/a/8dff23ac-cadc-4e5a-9fe7-bb25973d9cf1.jpg';
const OG_W = 1500;
const OG_H = 1500;

/**
 * Social tags for the first byte of the response. The artifact applies its own
 * <helmet> only after React boots — too late for a crawler that runs no
 * JavaScript, and too late for a scraper that never waits.
 *
 * The <title> is NOT emitted here: the build already moved the artifact's own
 * into <head>, so titling the page stays the artifact author's job and <head>
 * never ends up with two.
 */
function headTags(base: string, title: string): string {
  return (
    `<meta name="description" content="${esc(DESC)}">` +
    `<meta name="theme-color" content="#FFD9E4">` +
    `<meta property="og:type" content="website">` +
    `<meta property="og:site_name" content="Ana-Bala">` +
    `<meta property="og:locale" content="ru_KZ">` +
    `<meta property="og:title" content="${esc(title)}">` +
    `<meta property="og:description" content="${esc(DESC)}">` +
    `<meta property="og:url" content="${esc(base)}/">` +
    `<meta property="og:image" content="${esc(base)}${OG_IMAGE}">` +
    `<meta property="og:image:width" content="${OG_W}"><meta property="og:image:height" content="${OG_H}">` +
    `<meta name="twitter:card" content="summary_large_image">` +
    `<meta name="twitter:title" content="${esc(title)}">` +
    `<meta name="twitter:description" content="${esc(DESC)}">` +
    `<meta name="twitter:image" content="${esc(base)}${OG_IMAGE}">`
  );
}

/**
 * Register the landing routes. Throws if the page has not been built — the
 * caller decides how loud that is (in production it means the site has no root).
 *
 * @param dir the built landing directory; defaults to packages/backend/landing.
 * @returns how many assets were registered.
 */
export function registerLanding(app: FastifyInstance, dir?: string): number {
  const landingDir = dir ?? fileURLToPath(new URL('../../landing/', import.meta.url));
  const html = readFileSync(join(landingDir, 'index.html'), 'utf8');

  const headOpen = /<head[^>]*>/i.exec(html);
  if (!headOpen) throw new Error('landing/index.html has no <head>');
  const headEnd = headOpen.index + headOpen[0].length;
  const before = html.slice(0, headEnd);
  const after = html.slice(headEnd);

  // og:title should say what the tab says. The build hoists the artifact's
  // <title> into <head>, so it is here to read rather than restate.
  const titleTag = /<title>([\s\S]*?)<\/title>/i.exec(html);
  if (!titleTag) throw new Error('landing/index.html has no <title> — rebuild it with tools/build-landing.mjs');
  const title = titleTag[1].trim();

  app.get('/', async (req, reply) =>
    reply.type('text/html').send(before + headTags(requestBase(req), title) + after));

  // Our form wiring, not the artifact's. Its URL is stable (unlike the generated
  // assets, which are named by content uuid), so it gets a short cache instead
  // of an immutable one — otherwise a fix would be pinned in browsers for a year.
  const wireJs = readFileSync(join(landingDir, 'wire.js'), 'utf8');
  app.get('/landing/wire.js', async (_req, reply) =>
    reply
      .type('application/javascript; charset=utf-8')
      .header('cache-control', 'public, max-age=300')
      .send(wireJs));

  // Fonts, images, React, the artifact runtime. Each filename contains the
  // artifact's uuid for that asset, so a given URL's bytes never change: safe to
  // cache for a year. A re-export mints new uuids and the HTML points at those.
  let served = 0;
  for (const file of readdirSync(join(landingDir, 'a'))) {
    const type = TYPES[extname(file).toLowerCase()];
    if (!type) {
      app.log.warn(`landing asset ${file}: unknown extension, not served`);
      continue;
    }
    const bytes = readFileSync(join(landingDir, 'a', file));
    app.get(`/landing/a/${file}`, async (_req, reply) =>
      reply.type(type).header('cache-control', 'public, max-age=31536000, immutable').send(bytes));
    served++;
  }
  return served;
}
