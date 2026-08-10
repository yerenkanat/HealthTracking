/**
 * Render frame 00 «Дашборд владельца» and read what an owner would see.
 *
 * The payload is produced by the real `buildOwnerDashboard`, so the screen is
 * tested against the numbers the route actually serves. The assertions that
 * matter are the refusals: an estimate is not printed like a fact, a cash gap
 * is never green, and the decision card stays away on a week with nothing to
 * decide.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildOwnerDashboard, type OwnerInput } from '../admin/ownerDashboard.js';
import type { InventoryProduct, ShopOrder } from '../db/repository.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');
const NOW = new Date('2026-08-08T12:00:00.000Z');

const order = (o: Partial<ShopOrder>): ShopOrder => ({
  id: 'o1', customerName: 'Айгерім', phone: '+7700', city: 'Алматы', address: 'ул. 1',
  note: null, totalMinor: 0, discountMinor: 0, status: 'delivered',
  createdAt: '2026-08-06T10:00:00.000Z',
  items: [], ...o,
});

/**
 * The catalogue half of a product, unset. These tests are about money and
 * stock; spelling out eleven nulls in every fixture would bury what each one
 * is actually asserting.
 */
const NO_CATALOGUE = {
  nameKk: null, stage: null, category: null,
  descriptionRu: null, descriptionKk: null,
  ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
  seoSlug: null, seoTitle: null, seoDescription: null,
} as const;

const PRODUCTS: InventoryProduct[] = [
  {
    id: 'p1', name: 'Комплект', sku: null, priceMinor: 3_900_000, costMinor: 2_400_000,
    kind: 'simple', active: true, sort: 0, lowStockThreshold: 3, stock: 10,
    lowStock: false, variants: [], ...NO_CATALOGUE,
  },
  {
    // No cost recorded — this is what makes the profit an estimate.
    id: 'p2', name: 'Часы', sku: null, priceMinor: 1_500_000, costMinor: null,
    kind: 'simple', active: true, sort: 1, lowStockThreshold: 3, stock: 4,
    lowStock: true, variants: [], ...NO_CATALOGUE,
  },
];

const ORDERS: ShopOrder[] = [
  order({
    id: 'a', totalMinor: 3_900_000,
    items: [{ productName: 'Комплект', color: 'rose', qty: 1, unitPriceMinor: 3_900_000 }],
  }),
  order({
    id: 'b', totalMinor: 1_500_000, createdAt: '2026-08-03T10:00:00.000Z',
    items: [{ productName: 'Часы', color: 'black', qty: 1, unitPriceMinor: 1_500_000 }],
  }),
  order({ id: 'c', status: 'new', totalMinor: 900_000 }),
];

const SIGNALS: OwnerInput['signals'] = {
  overdue: ['emergencies'], lowStock: ['p2'], unreviewedMedical: 0,
  unregisteredDevices: 2, accessWithoutReason: 0, courseNeverStarted: 0,
};

function payload(over: Partial<OwnerInput> = {}) {
  return {
    asOf: NOW.toISOString(),
    ...buildOwnerDashboard(
      { orders: ORDERS, products: PRODUCTS, planMinor: 10_000_000, signals: SIGNALS, ...over },
      NOW,
    ),
    who: {
      mothers: { pregnant: 120, mothers: 140, both: 20, unknown: 5 },
      children: 161,
      devices: { total: 161, online: 90, watches: 60, trackers: 101, unassigned: 3, unregistered: 2 },
      dau: 40, wau: 120, mau: 240, retentionD7: 0.42,
      course: { lessons: 12, granted: 30, started: 22, finished: 4, lessonsCompleted: 90, active7d: 9 },
    },
  };
}

interface Rendered {
  text(sel: string): string;
  html(sel: string): string;
  count(sel: string): number;
  hidden(sel: string): boolean;
  errors: string[];
  window: JSDOM['window'];
}

async function render(body: unknown, down: string[] = []): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
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
          {
            canvas: { width: 600, height: 170 },
            createLinearGradient: () => ({ addColorStop: noop }),
            measureText: () => ({ width: 10 }),
          },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return {
            ok: true, status: 200,
            // `displayName`, as the real GET /admin/me sends it. A stub using
            // `name` would greet nobody in this test and everybody in
            // production, which is the wrong way round.
            json: async () => ({
              staffId: 's1', role: 'owner', displayName: 'Диас', phone: '+77000000000',
            }),
          };
        }
        if (down.some((d) => p.includes(d))) {
          return { ok: false, status: 500, json: async () => ({}) };
        }
        return {
          ok: true, status: 200,
          json: async () => (p.includes('/admin/owner') ? body : {}),
        };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document
    .querySelector('[data-view="owner"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(150);

  const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
  return {
    text: (sel) => norm(window.document.querySelector(sel)?.textContent ?? ''),
    html: (sel) => window.document.querySelector(sel)?.innerHTML ?? '',
    count: (sel) => window.document.querySelectorAll(sel).length,
    hidden: (sel) => !!(window.document.querySelector(sel) as HTMLElement | null)?.hidden,
    errors,
    window,
  };
}

describe('the owner dashboard renders', () => {
  let page: Rendered;
  beforeAll(async () => { page = await render(payload()); });

  it('runs without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('greets the person actually signed in', () => {
    // The spec's «Доброе утро, Диас» is a name in a mock-up. Hard-coding it
    // into a live panel greets the wrong person every morning.
    const t = page.text('#ownerGreet');
    expect(t).toMatch(/Доброе утро|Добрый день|Добрый вечер|Доброй ночи/);
    expect(t).toContain('Диас');
    expect(t).toMatch(/\d{1,2} \p{L}+ \d{4}/u);
  });

  it('shows all five money metrics', () => {
    expect(page.count('#ownerMoney .kpi')).toBe(5);
    const t = page.text('#ownerMoney');
    for (const label of ['Выручка за месяц', 'Чистая прибыль', 'Заказов',
      'Деньги в товаре', 'Кассовый разрыв']) {
      expect(t).toContain(label);
    }
  });

  it('marks the profit as an estimate when costs are missing', () => {
    // «Часы» has no recorded cost, so 72 % of the month's revenue is costed.
    // Printing that in the same weight as the ledger figures is the lie this
    // screen must not tell.
    expect(page.text('#ownerMoney')).toMatch(/Оценка: себестоимость известна по \d+ %/);
    expect(page.count('#ownerMoney .est')).toBe(1);
  });

  it('never paints a positive cash gap as good news', () => {
    // Money tied up in goods with less on its way in is a warning.
    const html = page.html('#ownerMoney');
    expect(html).toContain('--warn-text');
    expect(page.text('#ownerMoney')).toContain('в заказах');
  });

  it('states the plan it is measured against', () => {
    expect(page.text('#ownerMoney')).toMatch(/% плана/);
  });

  it('lists what is on fire, with a count in the header', () => {
    const t = page.text('#ownerBurning');
    expect(t).toContain('Очереди просрочены');
    expect(t).toContain('Товары заканчиваются');
    expect(page.text('#ownerBurnCount')).toBe('3');
  });

  it('shows where the revenue came from, biggest first', () => {
    const t = page.text('#ownerSources');
    expect(t.indexOf('Комплект')).toBeLessThan(t.indexOf('Часы'));
    expect(t).toMatch(/\d+ шт/);
  });

  it('answers «кто с нами» from the snapshot', () => {
    const t = page.text('#ownerWho');
    expect(t).toContain('Мамы');
    expect(t).toContain('161');
    expect(t).toContain('42 %');
  });

  it('has no «Новый заказ» button anywhere on it', () => {
    // «Никакой кнопки "Новый заказ".» This screen is for deciding; the owner
    // has an operator for doing, and a create button here is how the owner
    // starts doing the operator's job at midnight.
    expect(page.text('#owner')).not.toContain('Новый заказ');
    expect(page.count('#owner button')).toBe(0);
  });
});

describe('«Решение недели»', () => {
  it('appears with three options when something needs deciding', async () => {
    const p = await render(payload({ signals: { ...SIGNALS, unreviewedMedical: 4 } }));
    expect(p.hidden('#ownerDecision')).toBe(false);
    expect(p.count('#ownerDecisionOpts li')).toBe(3);
    expect(p.text('#ownerDecisionWhy')).toContain('4');
  });

  it('stays away on a week with nothing to decide', async () => {
    // A card that manufactures a decision every week teaches its reader to
    // ignore it, and then it is useless on the week it matters.
    const p = await render(payload({
      planMinor: 100, signals: { ...SIGNALS, overdue: [] },
      products: [{ ...PRODUCTS[0] }],
      orders: [ORDERS[0]],
    }));
    expect(p.hidden('#ownerDecision')).toBe(true);
  });
});

describe('when the summary cannot be loaded', () => {
  it('says so instead of showing zeroes', async () => {
    // Zero revenue and zero profit rendered from a failed request is the worst
    // message this panel could print — it is calmly, confidently wrong.
    const p = await render(payload(), ['/admin/owner']);
    expect(p.text('#ownerMoney')).toContain('Не удалось загрузить');
    expect(p.text('#ownerMoney')).not.toMatch(/0 ₸/);
    expect(p.hidden('#ownerDecision')).toBe(true);
  });
});
