/**
 * Render frames 05 / 05a / 05b for real (jsdom).
 *
 * The assertion that matters is the last one: the margin's coverage caveat has
 * to be ON the screen, next to the margin. A margin computed over half the
 * revenue, shown alone, is a wrong number presented as a right one.
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
import type { InventoryProduct, ShopOrder, StockMove } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NO_CATALOGUE = {
  nameKk: null, stage: null, category: null, descriptionRu: null, descriptionKk: null,
  ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
  seoSlug: null, seoTitle: null, seoDescription: null,
} as const;

const products: InventoryProduct[] = [
  { id: 'watch', name: 'Часы', sku: null, priceMinor: 1_000_000, costMinor: 600_000,
    kind: 'simple', active: true, sort: 0, lowStockThreshold: 3, stock: 5, lowStock: false,
    variants: [], ...NO_CATALOGUE },
  // No cost — this is what makes the margin partial, and the caveat necessary.
  { id: 'tracker', name: 'Трекер', sku: null, priceMinor: 1_000_000, costMinor: null,
    kind: 'simple', active: true, sort: 1, lowStockThreshold: 3, stock: 5, lowStock: false,
    variants: [], ...NO_CATALOGUE },
];
const orders: ShopOrder[] = [
  { id: 'o1', customerName: 'A', phone: '+7', city: 'Алматы', address: 'ул. 1', note: null,
    totalMinor: 2_000_000, discountMinor: 0, status: 'delivered',
    createdAt: '2026-08-05T10:00:00.000Z',
    items: [
      { productName: 'Часы', color: 'rose', qty: 1, unitPriceMinor: 1_000_000 },
      { productName: 'Трекер', color: 'blue', qty: 1, unitPriceMinor: 1_000_000 },
    ] },
  { id: 'o2', customerName: 'B', phone: '+7', city: 'Алматы', address: 'ул. 2', note: null,
    totalMinor: 900_000, discountMinor: 0, status: 'new',
    createdAt: '2026-08-06T10:00:00.000Z', items: [] },
];
const moves: StockMove[] = [
  { id: 1, variantId: 'v1', productName: 'Часы', color: 'rose', delta: -4, reason: 'sale',
    note: null, staffId: null, orderId: 'o1', at: '2026-08-05T10:00:00.000Z' },
  { id: 2, variantId: 'v1', productName: 'Часы', color: 'rose', delta: 1, reason: 'return',
    note: 'не подошёл размер', staffId: 's1', orderId: null, at: '2026-08-07T10:00:00.000Z' },
  { id: 3, variantId: 'v1', productName: 'Часы', color: 'rose', delta: -1, reason: 'writeoff',
    note: 'разбит экран', staffId: 's1', orderId: null, at: '2026-08-08T10:00:00.000Z' },
];

const REPORT = buildFinanceReport({
  orders, products, moves, planMinor: 10_000_000, from: '2026-08-01', to: '2026-08-31',
});

interface Rendered { text(s: string): string; count(s: string): number; errors: string[]; }

async function boot(): Promise<Rendered> {
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
        const body = p.includes('/admin/finance') ? REPORT
          : p.includes('/admin/stats')
            ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
            : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });
  const { window } = dom;
  await settle.quiet();
  window.document.querySelector('[data-view="finance"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet();
  return {
    text: (s) => (window.document.querySelector(s)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (s) => window.document.querySelectorAll(s).length,
    errors,
  };
}

describe('frame 05 — Финансы', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows earned, and its progress against the plan', () => {
    const t = page.text('#finKpis');
    expect(t).toContain('Заработано');
    expect(t).toContain('20 000 ₸');
    expect(t).toContain('20% от плана');
  });

  it('shows the promise SEPARATELY from the revenue', () => {
    // 9 000 ₸ is placed and unpaid. If it were folded into «Заработано» the
    // month would read 29 000 and shrink when the order is cancelled.
    const t = page.text('#finKpis');
    expect(t).toContain('Обещано');
    expect(t).toContain('9 000 ₸');
    expect(t).toContain('ещё не заплатили');
  });

  it('prints the margin WITH its coverage, never alone', () => {
    // The whole point. Half the revenue has no cost recorded.
    const t = page.text('#finKpis');
    expect(t).toContain('Маржа');
    expect(t).toContain('50% выручки');
  });

  it('carries the caveats onto the screen', () => {
    const t = page.text('#finCaveats');
    expect(t).toContain('способ оплаты');
    expect(t).toContain('Трекер');
  });
});

describe('frame 05a — Возвраты и брак', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('lists returns and write-offs, newest first', () => {
    const t = page.text('#finReturns');
    expect(t).toContain('разбит экран');
    expect(t).toContain('не подошёл размер');
    expect(t.indexOf('разбит экран')).toBeLessThan(t.indexOf('не подошёл размер'));
  });

  it('distinguishes a return from a write-off', () => {
    // One comes back on the shelf, the other is gone. Same row otherwise.
    const t = page.text('#finReturns');
    expect(t).toContain('возврат');
    expect(t).toContain('списание');
  });

  it('gives the rate against sales, not a bare count', () => {
    expect(page.text('#finRetSub')).toContain('из 4 продаж');
    expect(page.text('#finRetSub')).toContain('25,0%');
  });
});
