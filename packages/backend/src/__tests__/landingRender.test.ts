/**
 * Render the Ana-Bala landing page and read what it actually shows.
 *
 * The page is not HTML we wrote: it is an exported artifact that boots React
 * from local copies of the UMD bundles, parses its own <x-dc> template, and
 * paints everything from JavaScript. So "the file contains the price" proves
 * nothing — if the runtime fails to find React, or an asset URL is wrong, the
 * response is still a valid 200 with all the copy in it and the visitor sees a
 * blank pink page.
 *
 * This test therefore serves the real routes over a real socket, loads the
 * result in jsdom with resources enabled (so the fonts, the runtime and React
 * are fetched exactly as a browser would), and asserts on the rendered text.
 *
 * It also covers the half we added: the callback form. The artifact's own
 * handler paints "Заявка принята ✓" and sends nothing — landing/wire.js is what
 * turns that into a row in shop_leads, and a silent regression there looks
 * identical to success from the visitor's side.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import Fastify from 'fastify';
import type { FastifyInstance } from 'fastify';
import { registerLanding } from '../http/landing';

let app: FastifyInstance;
let base: string;

/** What wire.js POSTed, in order. */
let posted: Array<Record<string, unknown>>;

let dom: JSDOM;
let win: JSDOM['window'];
let pageErrors: string[];

beforeAll(async () => {
  app = Fastify({ logger: false });
  registerLanding(app);
  // The form target. Registered here rather than mounting the whole backend so
  // this test fails for landing reasons only.
  posted = [];
  app.post('/shop/leads', async (req, reply) => {
    posted.push(req.body as Record<string, unknown>);
    return reply.code(201).send({ id: 'lead-test' });
  });
  // The number staff would have set in the admin panel. The artifact hardcodes
  // a different one, so this is what proves the setting reaches the page.
  app.get('/shop/config', async (_req, reply) =>
    reply.send({
      whatsapp: '77015550101',
      kaspiUrl: '',
      // What staff would have typed into Магазин → Настройки. The artifact
      // hardcodes three different testimonials, so these names appearing on the
      // page is the proof the setting reached it.
      reviews: JSON.stringify([
        { name: 'Гүлнара Т.', city: 'Шымкент, один ребёнок', text: 'Настроила за вечер, сын носит не снимая.', stars: 5 },
        { name: 'Асем К.', city: 'Караганда, двое детей', text: 'Спокойнее стало, вижу что дошёл до школы.', stars: 4 },
      ]),
      rating: '',
      reviewCount: '',
    }));
  await app.listen({ port: 0, host: '127.0.0.1' });
  const addr = app.server.address();
  if (!addr || typeof addr === 'string') throw new Error('no port');
  base = `http://127.0.0.1:${addr.port}`;

  pageErrors = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => pageErrors.push(e.message));

  const html = await (await fetch(base + '/')).text();
  dom = new JSDOM(html, {
    url: base + '/',
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
    virtualConsole: vc,
  });
  win = dom.window;
  // jsdom ships no fetch; wire.js needs one. Forward to the real server so the
  // POST is genuinely served, and record the body.
  (win as unknown as { fetch: typeof fetch }).fetch = ((url: string, opts: RequestInit) =>
    fetch(new URL(url, base), opts)) as typeof fetch;

  await new Promise<void>((r) => win.addEventListener('load', () => r(), { once: true }));

  // React mounts from the runtime's boot hook, after it has fetched React over
  // HTTP. Poll for the template being consumed rather than sleeping a fixed
  // interval: a fixed wait is either slower than it needs to be or, under a
  // loaded machine running the rest of the suite in parallel, too short.
  const deadline = Date.now() + 45_000;
  while (win.document.querySelector('x-dc') && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 100));
  }
  // Let the first paint flush before anything reads the DOM.
  await new Promise((r) => setTimeout(r, 250));
}, 60_000);

afterAll(async () => {
  win?.close();
  await app?.close();
}, 30_000);

/**
 * Boot a second, independent copy of the landing against a given /shop/config.
 *
 * The suite-wide `dom` above is rendered once with one configuration; anything
 * that depends on a *different* setting (or on the visitor's language) needs
 * its own page rather than mutating the shared one.
 */
async function renderWith(
  config: Record<string, unknown>,
  locale?: 'ru' | 'kz',
): Promise<{ doc: Document; close: () => Promise<void> }> {
  const server = Fastify({ logger: false });
  registerLanding(server);
  server.get('/shop/config', async (_q, reply) => reply.send(config));
  await server.listen({ port: 0, host: '127.0.0.1' });
  const port = (server.server.address() as { port: number }).port;
  const origin = `http://127.0.0.1:${port}`;

  let html = await (await fetch(origin + '/')).text();
  if (locale) {
    // The landing keeps the visitor's language here and wire.js reads it. Seed
    // it before any of the page's own scripts run, which is what a returning
    // Kazakh visitor's browser hands over.
    html = html.replace(
      '<head>',
      `<head><script>localStorage.setItem('anabala-landing-lang', ${JSON.stringify(locale)})</script>`,
    );
  }

  const d = new JSDOM(html, {
    url: origin + '/',
    runScripts: 'dangerously',
    resources: 'usable',
    pretendToBeVisual: true,
  });
  (d.window as unknown as { fetch: typeof fetch }).fetch = ((u: string, o: RequestInit) =>
    fetch(new URL(u, origin), o)) as typeof fetch;
  await new Promise<void>((r) => d.window.addEventListener('load', () => r(), { once: true }));
  const deadline = Date.now() + 45_000;
  while (d.window.document.querySelector('x-dc') && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 100));
  }
  await new Promise((r) => setTimeout(r, 400));

  return {
    doc: d.window.document as unknown as Document,
    close: async () => {
      d.window.close();
      await server.close();
    },
  };
}

describe('landing page renders', () => {
  it('boots React and consumes the template', () => {
    // <x-dc> is the unrendered template. Still present ⇒ the runtime never ran.
    expect(dom.window.document.querySelector('x-dc')).toBeNull();
    expect(pageErrors).toEqual([]);
  });

  it('paints the real page, not an empty shell', () => {
    const text = dom.window.document.body.textContent ?? '';
    expect(text).toContain('Ana-Bala');
    expect(dom.window.document.querySelectorAll('section').length).toBeGreaterThanOrEqual(5);
    // The offer itself — if pricing vanished, the page is decoration.
    expect(text).toMatch(/39 000|24 900|4 900/);
  });

  it('ends up with one title, not the injected one plus the runtime\'s', () => {
    // The page carries its own <title> in a <helmet> block that the runtime
    // applies on boot, and we inject one for crawlers. Two <title> elements in
    // <head> is malformed and leaves which one search engines use to chance.
    const titles = dom.window.document.head.querySelectorAll('title');
    expect(titles.length).toBe(1);
    expect(dom.window.document.title).toContain('Ana-Bala');
  });

  it('carries the ordering routes a visitor can act on', () => {
    const doc = dom.window.document;
    expect(doc.querySelector('a[href*="wa.me"]')).not.toBeNull();
    expect(doc.querySelectorAll('form').length).toBeGreaterThanOrEqual(1);
  });

  it('dials the number staff configured, not the one baked into the export', () => {
    // WhatsApp is the main way to buy here, so a stale number is a dead
    // storefront — and the admin field that is supposed to control it was
    // reaching nothing at all.
    const links = Array.from(dom.window.document.querySelectorAll('a[href*="wa.me/"]')) as HTMLAnchorElement[];
    expect(links.length).toBeGreaterThan(0);
    for (const a of links) {
      expect(a.href, 'link still points at the hardcoded number').toContain('wa.me/77015550101');
    }
    // Each link keeps its own pre-filled greeting; the RU and KZ ones differ.
    expect(links.some((a) => a.href.includes('?text='))).toBe(true);
  });

  it('shows the testimonials staff configured, not the ones in the export', () => {
    // shop_settings.reviews existed, the admin panel edited it, /shop/config
    // served it — and nothing on the page read it, so entering real customer
    // quotes changed nothing. Exactly the shape of the callback form before it
    // was wired.
    const text = dom.window.document.body.textContent ?? '';
    expect(text).toContain('Гүлнара Т.');
    expect(text).toContain('Настроила за вечер');
    // And the hardcoded ones are gone rather than sitting alongside.
    expect(text).not.toContain('Дочь ходит в школу сама с первого класса');

    // Both language sections, not just the Russian one — they are found
    // structurally for this reason.
    const cards = dom.window.document.querySelectorAll('[data-review="1"]');
    expect(cards.length).toBeGreaterThanOrEqual(2);

    // A 4-star review renders four filled and one empty, not five.
    const four = Array.from(cards).find((c) => (c.textContent ?? '').includes('Асем К.'));
    expect(four?.textContent).toContain('★★★★☆');
  });

  it('reads a Kazakh visitor the Kazakh text of the same review', async () => {
    // One setting feeds a bilingual page. The authored page localises both
    // sections; if the configured reviews only ever rendered `text`, filling
    // this field in would have handed Kazakh visitors Russian testimonials —
    // a downgrade caused by wiring the setting up.
    const cfg = {
      whatsapp: '',
      reviews: JSON.stringify([
        {
          name: 'Гүлнара Т.',
          city: 'Шымкент',
          city_kz: 'Шымкент, бір бала',
          text: 'Настроила за вечер.',
          text_kz: 'Бір кеште баптап шықтым.',
          stars: 5,
        },
      ]),
    };
    const { doc, close } = await renderWith(cfg, 'kz');
    const text = doc.body.textContent ?? '';
    expect(text).toContain('Бір кеште баптап шықтым');
    expect(text).not.toContain('Настроила за вечер');
    // The name has no _kz form, so it falls back rather than rendering empty.
    expect(text).toContain('Гүлнара Т.');
    await close();
  }, 60_000);

  it('shows the honest empty state when no reviews are configured', async () => {
    // This asserted the page KEPT its authored testimonials when the setting
    // was empty — «a page that blanked its social proof because a field was
    // empty would be worse than one that kept the copy it shipped with».
    //
    // That reasoning held only while the shipped copy was TRUE. It was not:
    // the three authored quotes were invented, and they are gone. So the
    // fallback is no longer fabricated proof but a sentence saying reviews
    // will appear when real buyers write them — which is what an empty reviews
    // field actually means.
    const { doc, close } = await renderWith({ whatsapp: '', reviews: '' });
    expect(doc.body.textContent).not.toContain('Дочь ходит в школу сама с первого класса');
    expect(doc.body.textContent).toContain('Отзывы появятся здесь');
    await close();
  }, 60_000);

  it('does not break the page when the field holds something that is not JSON', async () => {
    // The admin panel's reviews box is a free-text field. A half-typed entry
    // must leave the page intact rather than throwing partway through render.
    const { doc, close } = await renderWith({ whatsapp: '', reviews: '[{"name": "Айг' });
    expect(doc.body.textContent).toContain('Отзывы появятся здесь');
    // And it must certainly not resurrect a fabricated quote.
    expect(doc.body.textContent).not.toContain('Дочь ходит в школу сама с первого класса');
    await close();
  }, 60_000);

  it('serves crawler-readable meta in the first byte', async () => {
    // Not from the DOM: from the raw response, which is all a scraper reads.
    const raw = await (await fetch(base + '/')).text();
    const head = raw.slice(0, raw.indexOf('</head>'));
    expect(head).toContain('<title>Ana-Bala');
    expect(head).toContain('og:title');
    expect(head).toContain(`og:url" content="${base}/`);
  });

  it('tells crawlers where the sitemap is', async () => {
    const res = await fetch(base + '/robots.txt');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/plain');
    const body = await res.text();
    expect(body).toContain('Allow: /');
    expect(body).toContain('Disallow: /admin');
    // The absolute URL, on the host that was asked — a sitemap line naming the
    // wrong host is worse than no line at all.
    expect(body).toContain(`Sitemap: ${base}/sitemap.xml`);
  });

  it('serves a sitemap listing the one page there is', async () => {
    const res = await fetch(base + '/sitemap.xml');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('xml');
    const body = await res.text();
    expect(body).toContain('<?xml');
    expect(body).toContain(`<loc>${base}/</loc>`);
    // The two languages share one URL — the toggle is client-side — so a
    // second <url> would be claiming an address that does not exist.
    expect((body.match(/<url>/g) ?? []).length).toBe(1);
  });

  it('states a canonical URL, because the site answers on www too', () => {
    const links = dom.window.document.head.querySelectorAll('link[rel="canonical"]');
    expect(links.length).toBe(1);
    expect((links[0] as HTMLLinkElement).getAttribute('href')).toBe(`${base}/`);
  });

  it('serves every asset the page asks for', async () => {
    const doc = dom.window.document;
    const urls = new Set<string>();
    for (const el of Array.from(doc.querySelectorAll('script[src], img[src], link[href]'))) {
      const u = el.getAttribute('src') ?? el.getAttribute('href') ?? '';
      if (u.startsWith('/landing/')) urls.add(u);
    }
    expect(urls.size).toBeGreaterThan(0);
    for (const u of urls) {
      const res = await fetch(base + u);
      expect(res.status, `${u} should be served`).toBe(200);
    }
  });

  it('never falls back to the unpkg CDN for React', async () => {
    const raw = await (await fetch(base + '/')).text();
    const map = /window\.__resources = (\{.*?\});/.exec(raw);
    expect(map, '__resources map must be injected').not.toBeNull();
    const resources = JSON.parse(map![1]) as Record<string, string>;
    const entries = Object.entries(resources);
    expect(entries.length).toBeGreaterThan(0);
    // Every CDN URL the runtime knows about must resolve to a local path;
    // an unmapped one silently reaches out to unpkg.com at runtime.
    for (const [cdn, local] of entries) {
      expect(cdn).toMatch(/^https:\/\/unpkg\.com\//);
      expect(local).toMatch(/^\/landing\/a\//);
      expect((await fetch(base + local)).status).toBe(200);
    }
  });
});

describe('the callback form reaches the backend', () => {
  /** Fill the rendered form and submit it the way a browser would. */
  async function submit(name: string, phone: string): Promise<HTMLFormElement> {
    const form = dom.window.document.querySelector('form') as HTMLFormElement;
    const inputs = form.querySelectorAll('input');
    inputs[0].value = name;
    inputs[1].value = phone;
    form.dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 500));
    return form;
  }

  it('refuses an empty submission instead of faking success', async () => {
    const before = posted.length;
    const form = await submit('', '');
    expect(posted.length, 'nothing should be recorded').toBe(before);
    // The artifact would have painted "Заявка принята ✓" regardless; the visitor
    // has to be told the number never left the page.
    expect(form.textContent).toMatch(/Укажите имя|Атыңыз/);
  });

  it('posts a filled form as a lead', async () => {
    const before = posted.length;
    await submit('Айгерім Тест', '+7 707 345 22 44');
    expect(posted.length).toBe(before + 1);
    const lead = posted[posted.length - 1];
    expect(lead.customerName).toBe('Айгерім Тест');
    expect(lead.phone).toBe('+7 707 345 22 44');
    expect(lead.locale).toMatch(/^(ru|kz)$/);
    // Which bundle they picked — the whole point of calling back.
    expect(String(lead.package ?? '')).not.toBe('');
  });
});
