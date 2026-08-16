/**
 * Render the Магазин tab and read the landing-leads card.
 *
 * A lead exists to be phoned back, so this asserts on what a staff member can
 * actually see and do: the name, a dialable number, which bundle was picked, the
 * language to speak, and a status control. Checking that the markup contains
 * "Заявки" would pass with an empty card.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const LEADS = {
  leads: [
    {
      id: 'l-1', customerName: 'Айгерім', phone: '+7 707 345 22 44',
      package: 'Комплект «Мама и ребёнок» — 39 000 ₸', locale: 'kz',
      status: 'new', createdAt: '2026-08-01T09:12:00.000Z',
    },
    {
      id: 'l-2', customerName: 'Сауле', phone: '+7 700 666 55 44',
      package: 'Только часы — 24 900 ₸', locale: 'ru',
      status: 'called', createdAt: '2026-07-31T16:40:00.000Z',
    },
  ],
  /**
   * The shape GET /admin/shop/leads actually answers with, counts included —
   * `repo.shopLeadCounts()` over the whole table, not over this page. The
   * fixture carried the rows alone, which is a shape the route stopped sending;
   * a fake that lags the thing it stands for is how a screen passes its tests
   * and misprints in production.
   */
  counts: { shown: 2, total: 2, uncalled: 1 },
  limit: 100,
  exact: true,
};

interface Page {
  text(sel: string): string;
  count(sel: string): number;
  html(sel: string): string;
  errors: string[];
  window: JSDOM['window'];
  patched: Array<{ url: string; body: unknown }>;
}

async function render(leads: unknown = LEADS): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const patched: Array<{ url: string; body: unknown }> = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin/ui',
    virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.fetch = (async (path: string, opts?: { method?: string; body?: string }) => {
        const p = String(path);
        if (opts?.method === 'PATCH') {
          patched.push({ url: p, body: JSON.parse(opts.body ?? '{}') });
          return { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        // Only the shop endpoints are stubbed; everything else answers 500, the
        // same "endpoint down" the panel already tolerates elsewhere. Handing
        // back an empty object instead would make callers read fields off {}.
        const body = p.includes('/admin/shop/leads')
          ? leads
          : p.includes('/admin/shop/orders')
            ? { orders: [] }
            : p.includes('/admin/shop/variants')
              ? { variants: [] }
              : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document.querySelector('[data-view="shop"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(200);

  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    html: (sel) => window.document.querySelector(sel)?.innerHTML ?? '',
    errors,
    window,
    patched,
  };
}

describe('the landing-leads card', () => {
  let page: Page;
  beforeAll(async () => { page = await render(); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows a row per lead rather than an empty card', () => {
    expect(page.count('#shopLeads .ordercard')).toBe(2);
    expect(page.text('#shopLeads')).not.toMatch(/Не удалось|Заявок пока нет/);
  });

  it('shows who to call, on what number, about which bundle', () => {
    const t = page.text('#shopLeads');
    expect(t).toContain('Айгерім');
    expect(t).toContain('+7 707 345 22 44');
    expect(t).toContain('39 000');
    // Which language to greet them in — the lead came off the Kazakh page.
    expect(t).toContain('қаз');
  });

  it('makes the number dialable instead of something to retype', () => {
    const link = page.window.document.querySelector('#shopLeads a[href^="tel:"]');
    expect(link).not.toBeNull();
    expect(link!.getAttribute('href')).toBe('tel:+77073452244');
  });

  it('counts only the unhandled ones as waiting', () => {
    // Two leads, one already called.
    expect(page.text('#shopLeadsSub')).toContain('не обработано: 1');
  });

  it('saves the outcome of the call', async () => {
    const sel = page.window.document.querySelector('#shopLeads .lstatus') as HTMLSelectElement;
    expect(sel).not.toBeNull();
    // The vocabulary a phone call can end in — nothing about shipping.
    expect(Array.from(sel.options).map((o) => o.value)).toEqual(['new', 'called', 'ordered', 'dropped']);

    sel.value = 'ordered';
    sel.dispatchEvent(new page.window.Event('change', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 100));

    expect(page.patched).toHaveLength(1);
    expect(page.patched[0].url).toContain('/admin/shop/leads/l-1');
    expect(page.patched[0].body).toEqual({ status: 'ordered' });
  });
});

describe('the leads card with nothing in it', () => {
  it('says so plainly instead of looking broken', async () => {
    const page = await render({ leads: [] });
    expect(page.errors).toEqual([]);
    expect(page.text('#shopLeadsSub')).toBe('нет заявок');
    expect(page.text('#shopLeads')).toContain('Заявок пока нет');
  });
});
