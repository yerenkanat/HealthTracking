/**
 * Render frames 08 / 08a / 08b for real (jsdom): the catalogue table, the
 * category and stage rails, and the product card with its five tabs.
 *
 * «Верифицировано структурно» is not verification — the panel is one file whose
 * JS a browser executes top to bottom, so a temporal-dead-zone slip in one new
 * block takes every later block with it. That is exactly what happened while
 * writing this view (the `on` helper is a const declared further down), and
 * only executing the page catches it.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };
const KIDS = {
  total: 10, boys: 6, girls: 3, unknown: 1, withDob: 9,
  byAge: [
    { bucket: '0–1', count: 2 }, { bucket: '1–3', count: 3 },
    { bucket: '3–7', count: 4 }, { bucket: '7+', count: 1 },
  ],
};
const CATALOG = {
  stages: ['planning', 'pregnancy', 'newborn', 'infant', 'toddler', 'any'],
  categories: [
    { id: 'watch', nameRu: 'Смарт-часы', nameKk: 'Смарт-сағат', sort: 10 },
    { id: 'tracker', nameRu: 'Детские трекеры', nameKk: null, sort: 20 },
  ],
  products: [
    {
      id: 'watch', name: 'Смарт-часы Ana-Bala', nameKk: 'Ana-Bala смарт-сағаты',
      priceMinor: 2_490_000, costMinor: 1_800_000, active: true, sort: 1, sku: null,
      kind: 'simple', category: 'watch', stage: 'pregnancy',
      descriptionRu: null, descriptionKk: null,
      ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
      seoSlug: null, seoTitle: null, seoDescription: null,
      stock: 12, lowStock: false, variants: [],
    },
    {
      // Deliberately incomplete: no category, no stage, no Kazakh name. The
      // screen must show the gap rather than a plausible default.
      id: 'tracker', name: 'Детский трекер', nameKk: null,
      priceMinor: 490_000, costMinor: null, active: false, sort: 2, sku: null,
      kind: 'simple', category: null, stage: null,
      descriptionRu: null, descriptionKk: null,
      ageMinMonths: 24, ageMaxMonths: 120, photoUrl: null,
      seoSlug: null, seoTitle: null, seoDescription: null,
      stock: 3, lowStock: true, variants: [],
    },
  ],
};

interface Rendered {
  text(s: string): string;
  count(s: string): number;
  click(s: string): Promise<void>;
  el(s: string): Element | null;
  patches: Array<{ url: string; body: Record<string, unknown> }>;
  errors: string[];
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function boot(): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const patches: Array<{ url: string; body: Record<string, unknown> }> = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const settle = panelSettle();
  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/admin/ui', virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      settle.attach(window as never, async (path: string, opts?: PanelRequestInit) => {
        const p = String(path);
        if (opts?.method === 'PATCH') {
          patches.push({ url: p, body: JSON.parse(opts.body ?? '{}') });
          return { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        const body = p.includes('/admin/shop/products') ? CATALOG
          : p.includes('/admin/children/stats') ? KIDS
          : p.includes('/admin/stats') ? STATS
          : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });
  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="catalog"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Каталог tab');
  return {
    text: (s) => (window.document.querySelector(s)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (s) => window.document.querySelectorAll(s).length,
    el: (s) => window.document.querySelector(s),
    click: async (s) => {
      window.document.querySelector(s)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet(`the click on ${s}`);
    },
    patches,
    errors,
    quiet: settle.quiet,
  };
}

describe('frame 08 — Каталог', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('lists the products with their stage', () => {
    const t = page.text('#catBody');
    expect(t).toContain('Смарт-часы Ana-Bala');
    expect(t).toContain('Беременность');
  });

  it('shows a missing stage as «не указан» rather than guessing one', () => {
    expect(page.text('#catBody')).toContain('не указан');
  });

  it('offers the categories and stages as filters', () => {
    expect(page.text('#catCats')).toContain('Смарт-часы');
    expect(page.text('#catStages')).toContain('Беременность');
    // The buckets that make the remaining work findable.
    expect(page.text('#catCats')).toContain('Без категории');
    expect(page.text('#catStages')).toContain('Этап не указан');
  });

  it('states the rule in the table footer', () => {
    const t = page.text('#catFootRule');
    expect(t).toContain('Без этапа: 1');
    expect(t).toContain('Без казахского названия: 1');
  });

  it('badges the sidebar with the work outstanding', () => {
    const badge = page.el('#catalogBadge') as HTMLElement | null;
    expect(badge?.hasAttribute('hidden')).toBe(false);
    expect(badge?.textContent).toBe('2'); // one missing stage + one missing kk
  });

  it('filtering by a stage narrows the table', async () => {
    await page.click('#catStages button[data-key="pregnancy"]');
    const t = page.text('#catBody');
    expect(t).toContain('Смарт-часы Ana-Bala');
    expect(t).not.toContain('Детский трекер');
    await page.click('#catStages button[data-key=""]'); // back to all
  });
});

describe('frame 08a — Карточка товара', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('opens with the product loaded', async () => {
    await page.click('#catBody button[data-prod="tracker"]');
    expect((page.el('#prodCard') as HTMLElement).hasAttribute('hidden')).toBe(false);
    expect((page.el('#pcName') as HTMLInputElement).value).toBe('Детский трекер');
    expect((page.el('#pcAgeMin') as HTMLInputElement).value).toBe('24');
  });

  it('has all five tabs, one pane visible', () => {
    expect(page.count('#pcTabs button')).toBe(5);
    const visible = Array.from(
      (page.el('#prodCard') as Element).querySelectorAll('.tabpane'))
      .filter((p) => !p.hasAttribute('hidden'));
    expect(visible.length).toBe(1);
  });

  it('switches panes', async () => {
    await page.click('#pcTabs button[data-tab="pers"]');
    const pers = (page.el('#prodCard') as Element)
      .querySelector('[data-pane="pers"]') as HTMLElement;
    expect(pers.hasAttribute('hidden')).toBe(false);
  });

  it('reports reach as approximate, from the buckets it actually has', () => {
    // 24–120 months overlaps 1–3, 3–7 and 7+. A precise-looking number nobody
    // can trace would be worse than this.
    const t = page.text('#pcReach');
    expect(t).toContain('Примерно');
    expect(t).toContain('8'); // 3 + 4 + 1
    expect(t).toContain('1–3');
  });

  it('builds the stage dropdown from the server list, not a hardcoded one', () => {
    // Six stages plus «не указан».
    expect(page.count('#pcStage option')).toBe(7);
  });

  it('sends ONLY what changed', async () => {
    (page.el('#pcStage') as HTMLSelectElement).value = 'toddler';
    await page.click('#pcSave');
    expect(page.patches.length).toBe(1);
    const body = page.patches[0].body;
    expect(body.stage).toBe('toddler');
    // The untouched fields must not be in the request at all. Sending them
    // back unchanged is how a stale form overwrites somebody else's edit.
    expect(Object.keys(body)).toEqual(['stage']);
  });
});

describe('«Двуязычность блокирует публикацию» — said before the save', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('warns when activating a product with no Kazakh name', async () => {
    await page.click('#catBody button[data-prod="tracker"]');
    const warn = page.el('#pcKkWarn') as HTMLElement;
    expect(warn.hasAttribute('hidden')).toBe(true);

    const active = page.el('#pcActive') as HTMLInputElement;
    active.checked = true;
    active.dispatchEvent(new (page.el('#pcActive') as Element).ownerDocument.defaultView!
      .Event('change', { bubbles: true }));
    await page.quiet('the Kazakh-name warning');
    expect(warn.hasAttribute('hidden')).toBe(false);
  });
});
