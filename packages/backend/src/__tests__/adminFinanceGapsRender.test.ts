/**
 * Two numbers the finance report already computed and the screen never showed.
 *
 * 1. `margin.missingCost` — the NAMES of the products sold in the window with
 *    no cost recorded. The panel printed «маржа посчитана по 50 % выручки» and
 *    stopped there: the owner was told a half of his margin is unmeasured and
 *    not told which products to go and price.
 * 2. `money.averageCheckMinor` — an average cheque over EARNED orders only,
 *    rendered nowhere, while «Сводка» shows a DIFFERENT average over all time.
 *    Two averages without their periods is worse than one.
 *
 * Rendered for real in jsdom, because "the field is on the wire" was true of
 * both of these for months.
 */

/**
 * WAITING — the fixed sleeps that used to stand in for "the panel has finished"
 * are gone. quiet() returns when no request is in flight, none has been issued
 * for several consecutive turns and the page has no timer outstanding, and it
 * THROWS rather than hand a half-drawn screen to an assertion. A wall-clock
 * wait decides its verdict on how busy the machine is; this one decides it on
 * the work being done. See helpers/panelSettle.ts.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';
import { buildFinanceReport } from '../admin/finance';
import type { InventoryProduct, ShopOrder } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NO_CATALOGUE = {
  nameKk: null, stage: null, category: null, descriptionRu: null, descriptionKk: null,
  ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
  seoSlug: null, seoTitle: null, seoDescription: null,
} as const;

const product = (id: string, name: string, costMinor: number | null): InventoryProduct => ({
  id, name, sku: null, priceMinor: 1_000_000, costMinor,
  kind: 'simple', active: true, sort: 0, lowStockThreshold: 3, stock: 5, lowStock: false,
  variants: [], ...NO_CATALOGUE,
});

const delivered = (id: string, names: string[]): ShopOrder => ({
  id, customerName: 'A', phone: '+7', city: 'Алматы', address: 'ул. 1', note: null,
  totalMinor: 1_000_000 * names.length, discountMinor: 0, status: 'delivered',
  createdAt: '2026-08-05T10:00:00.000Z',
  items: names.map((productName) => ({ productName, color: 'rose', qty: 1, unitPriceMinor: 1_000_000 })),
});

/** Половина выручки без себестоимости, один заказ на 20 000 ₸. */
const HALF_PRICED = buildFinanceReport({
  orders: [delivered('o1', ['Часы', 'Трекер'])],
  products: [product('watch', 'Часы', 600_000), product('tracker', 'Трекер', null)],
  moves: [], planMinor: null, from: '2026-08-01', to: '2026-08-31',
});

/** Всё оценено. */
const ALL_PRICED = buildFinanceReport({
  orders: [delivered('o1', ['Часы'])],
  products: [product('watch', 'Часы', 600_000)],
  moves: [], planMinor: null, from: '2026-08-01', to: '2026-08-31',
});

/** Заказ есть, отгрузки нет — среднему чеку не на что делиться. */
const NOTHING_SHIPPED = buildFinanceReport({
  orders: [{ ...delivered('o1', ['Часы']), status: 'new' }],
  products: [product('watch', 'Часы', 600_000)],
  moves: [], planMinor: null, from: '2026-08-01', to: '2026-08-31',
});

interface Page {
  text(sel: string): string;
  kpi(label: string): string;
  errors: string[];
}

async function render(report: unknown): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
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
      settle.attach(window as never, async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        // `null` means the report route is down — the panel has to say so
        // rather than repaint whatever it drew last time.
        if (p.includes('/admin/finance')) {
          return report === null
            ? { ok: false, status: 500, text: async () => 'down', json: async () => ({}) }
            : { ok: true, status: 200, json: async () => report };
        }
        return { ok: false, status: 500, json: async () => ({}) };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });

  const { window } = dom;
  await settle.quiet();
  window.document.querySelector('[data-view="finance"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet();

  const flat = (el: Element | null | undefined) =>
    (el?.textContent ?? '').replace(/\s+/g, ' ').trim();

  return {
    errors,
    text: (sel) => flat(window.document.querySelector(sel)),
    // The tile by its LABEL: asserting on #finKpis as one blob would let a
    // «0 ₸» from a neighbouring tile satisfy an assertion about this one.
    kpi: (label) => flat(
      [...window.document.querySelectorAll('#finKpis .kpi')]
        .find((c) => flat(c.querySelector('.lbl')).includes(label))),
  };
}

describe('the products whose cost nobody entered', () => {
  let page: Page;
  beforeAll(async () => { page = await render(HALF_PRICED); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('names them, instead of only stating a coverage percentage', () => {
    expect(page.text('#finMissing')).toContain('Трекер');
    expect(page.text('#finMissingSub')).toContain('1 товар');
  });

  it('says what the gap costs, in money, with the share it is of', () => {
    // 20 000 ₸ earned, 10 000 ₸ of it priced. The unmeasured half is the
    // number that decides whether this matters.
    const foot = page.text('#finMissingFoot');
    expect(foot).toContain('10 000 ₸');
    expect(foot).toContain('50% выручки');
    // And where to go and fix it.
    expect(foot).toContain('Склад');
    // The rule of the list: it is about the window at the top of the screen.
    expect(foot).toContain('период');
  });

  it('keeps the report\'s own caveat as well, rather than swallowing it', () => {
    expect(page.text('#finCaveats')).toContain('Себестоимость не указана');
  });
});

describe('when every sold product has a cost', () => {
  it('says so, instead of rendering an empty card that looks broken', async () => {
    const page = await render(ALL_PRICED);
    expect(page.errors).toEqual([]);
    expect(page.text('#finMissing')).toContain('себестоимость указана');
    expect(page.text('#finMissingSub')).toBe('нет таких товаров');
  });
});

describe('when the report cannot be loaded at all', () => {
  it('does not leave the previous answer standing as if it were this one', async () => {
    const page = await render(null);
    expect(page.errors).toEqual([]);
    // The refusal/failure itself is reported by #finMsg — this card must not
    // keep claiming every product is priced from a load that is no longer on
    // screen, and must not say «нет данных» either.
    expect(page.text('#finMissing')).toContain('Не загрузилось');
    expect(page.text('#finMissing')).not.toContain('себестоимость указана');
    expect(page.text('#finMsg')).not.toBe('');
  });
});

describe('the average cheque', () => {
  let page: Page;
  beforeAll(async () => { page = await render(HALF_PRICED); });

  it('is on the screen at all', () => {
    expect(page.kpi('Средний чек')).toContain('20 000 ₸');
  });

  it('carries the denominator AND the period, so it cannot be confused with the other one', () => {
    // «Сводка» shows revenue ÷ shipped over ALL TIME. This one is the window
    // named at the top of this screen. Both now say which they are.
    const tile = page.kpi('Средний чек');
    expect(tile).toContain('за период');
    expect(tile).toContain('отгруженные и доставленные');
  });

  it('says «не считается» rather than «0 ₸» when nothing shipped', async () => {
    const empty = await render(NOTHING_SHIPPED);
    const tile = empty.kpi('Средний чек');
    expect(tile).toContain('не считается');
    expect(tile).toContain('делить не на что');
    expect(tile).not.toContain('0 ₸');
  });
});
