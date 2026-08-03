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

  it('serves crawler-readable meta in the first byte', async () => {
    // Not from the DOM: from the raw response, which is all a scraper reads.
    const raw = await (await fetch(base + '/')).text();
    const head = raw.slice(0, raw.indexOf('</head>'));
    expect(head).toContain('<title>Ana-Bala');
    expect(head).toContain('og:title');
    expect(head).toContain(`og:url" content="${base}/`);
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
