/**
 * Render the Магазин tab and take an order the way a staff member would.
 *
 * Every sale arrives on WhatsApp or Kaspi — someone calls and reads out an
 * address. For a long time there was nowhere in the product to put it: the only
 * thing that could create an order was the public storefront, and the
 * storefront is retired. So this form is the whole sales channel, and "the
 * markup contains a button" is not evidence it works.
 *
 * These fill the fields in a real DOM, click Создать, and read the POST body:
 * whether the комплект is sent as a bundle is the difference between charging
 * 39 000 with a course and charging 29 800 without one.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Six fixed sleeps — 120 after boot, 250 after the tab, 60 after each Создать —
 * decided their verdict on elapsed wall-clock rather than on the work being
 * finished. 60 ms for a POST is the second-thinnest margin in the directory,
 * and two of the assertions are negative ("the course is granted against this
 * number" expects NOTHING posted), which an early read passes for free.
 *
 * They are all page.quiet() now: no request in flight, none newly issued for
 * several consecutive turns, no page timer outstanding, and a throw rather than
 * a half-drawn screen. See helpers/panelSettle.ts.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** The catalogue as GET /admin/inventory returns it. */
const INVENTORY = {
  products: [
    {
      id: 'watch', name: 'Смарт-часы Ana-Bala', sku: null, priceMinor: 2490000,
      costMinor: null, kind: 'simple', active: true, sort: 1, lowStockThreshold: 3,
      stock: 7, lowStock: false, parts: [],
      variants: [
        { id: 'v-watch-black', color: 'Чёрный', colorHex: '#222', stock: 5 },
        { id: 'v-watch-gone', color: 'Розовый', colorHex: '#e8a', stock: 0 },
      ],
    },
    {
      id: 'tracker', name: 'Детский трекер Ana-Bala', sku: null, priceMinor: 490000,
      costMinor: null, kind: 'simple', active: true, sort: 2, lowStockThreshold: 3,
      stock: 4, lowStock: false, parts: [],
      variants: [{ id: 'v-track-blue', color: 'Синий', colorHex: '#38c', stock: 4 }],
    },
    {
      id: 'combo', name: 'Комплект «Мама и ребёнок»', sku: null, priceMinor: 3900000,
      costMinor: null, kind: 'bundle', active: true, sort: 3, lowStockThreshold: 3,
      stock: 4, lowStock: false, variants: [],
      parts: [{ partId: 'watch', partName: 'Смарт-часы Ana-Bala', qty: 1 },
        { partId: 'tracker', partName: 'Детский трекер Ana-Bala', qty: 1 }],
    },
  ],
  lowStock: [],
};

interface Page {
  window: JSDOM['window'];
  errors: string[];
  posted: Array<{ url: string; body: Record<string, unknown> }>;
  $: (sel: string) => HTMLElement | null;
  text: (sel: string) => string;
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function render(inventory: unknown = INVENTORY, orderStatus = 201): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const errors: string[] = [];
  const posted: Array<{ url: string; body: Record<string, unknown> }> = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
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
      settle.attach(window as never, async (path: string, opts?: PanelRequestInit) => {
        const p = path;
        if (opts?.method === 'POST' && p.includes('/admin/shop/orders')) {
          posted.push({ url: p, body: JSON.parse(opts.body ?? '{}') });
          return orderStatus === 201
            ? { ok: true, status: 201, json: async () => ({ id: 'o-new', totalMinor: 3900000, discountMinor: 0 }) }
            : { ok: false, status: orderStatus, json: async () => ({ error: 'out_of_stock' }) };
        }
        const body = p.includes('/admin/inventory')
          ? inventory
          : p.includes('/admin/shop/orders')
            ? { orders: [] }
            : p.includes('/admin/shop/leads')
              ? { leads: [] }
              : p.includes('/admin/shop/variants')
                ? { variants: [] }
                : p.includes('/admin/settings')
                  ? { settings: {} }
                  : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="shop"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Магазин tab');

  return {
    window,
    errors,
    posted,
    $: (sel) => window.document.querySelector(sel),
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    quiet: settle.quiet,
  };
}

/** Type the delivery details a courier needs. */
function fillCustomer(page: Page): void {
  const set = (id: string, v: string) => {
    const el = page.$('#' + id) as HTMLInputElement;
    el.value = v;
    el.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  };
  set('noName', 'Мадина');
  set('noPhone', '+7 701 555 11 22');
  set('noCity', 'Астана');
  set('noAddr', 'пр. Кабанбай батыра 5, кв 12');
}

const click = (page: Page, sel: string) =>
  page.$(sel)!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));

const pickBundle = (page: Page) => {
  const radio = page.$('input[name="noKind"][value="bundle"]') as HTMLInputElement;
  radio.checked = true;
  radio.dispatchEvent(new page.window.Event('change', { bubbles: true }));
};

describe('taking an order in the panel', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('offers the catalogue, not an empty dropdown', () => {
    const sel = page.$('#noProduct') as HTMLSelectElement;
    // Bundles are excluded here: they have no colours of their own, so picking
    // one would leave the colour list empty with nothing explaining why.
    expect(Array.from(sel.options).map((o) => o.value)).toEqual(['watch', 'tracker']);

    const colors = page.$('#noColor') as HTMLSelectElement;
    expect(colors.options.length).toBe(2);
    // A colour that will restock stays listed, disabled — hiding it reads as
    // discontinued.
    expect(Array.from(colors.options).find((o) => o.value === 'v-watch-gone')!.disabled).toBe(true);
    expect(colors.value, 'the first orderable colour should be preselected').toBe('v-watch-black');
  });

  it('previews what the customer will be charged', () => {
    expect(page.text('#noTotal')).toContain('24 900');
    pickBundle(page);
    // The set costs MORE than its parts, because the course comes with it.
    expect(page.text('#noTotal')).toContain('39 000');
  });

  it('sends a single-product order with the colour that was picked', async () => {
    fillCustomer(page);
    click(page, '#noSave');
    await page.quiet('the order');

    expect(page.posted).toHaveLength(1);
    const b = page.posted[0].body;
    expect(b.items).toEqual([{ variantId: 'v-watch-black', qty: 1 }]);
    expect(b.customerName).toBe('Мадина');
    expect(b.city).toBe('Астана');
    expect(b.bundleId, 'one watch is not a комплект').toBeUndefined();
  });

  it('sends the комплект as a bundle — both colours and the bundle id', async () => {
    pickBundle(page);
    fillCustomer(page);
    click(page, '#noSave');
    await page.quiet('the order');

    expect(page.posted).toHaveLength(1);
    const b = page.posted[0].body;
    expect(b.bundleId, 'without this the server charges 29 800 and grants nothing').toBe('combo');
    expect(b.items).toEqual([
      { variantId: 'v-watch-black', qty: 1 },
      { variantId: 'v-track-blue', qty: 1 },
    ]);
  });

  it('says the course is coming, and that it opens on dispatch', async () => {
    pickBundle(page);
    fillCustomer(page);
    click(page, '#noSave');
    await page.quiet('the order');

    const m = page.text('#noMsg');
    expect(m).toContain('Ма!Ма!');
    // Not "уже доступен" — it opens when the parcel goes out, and a staff
    // member who says otherwise on the phone creates a complaint.
    expect(m).toMatch(/отправлен/);
  });

  it('refuses to send an order with a phone nobody can be reached on', async () => {
    fillCustomer(page);
    const phone = page.$('#noPhone') as HTMLInputElement;
    phone.value = '705';
    click(page, '#noSave');
    await page.quiet('the order');

    expect(page.posted, 'the course is granted against this number').toHaveLength(0);
    expect(page.text('#noMsg')).toMatch(/телефон/i);
  });

  it('tells staff the shelf is short rather than "что-то пошло не так"', async () => {
    page = await render(INVENTORY, 409);
    fillCustomer(page);
    click(page, '#noSave');
    await page.quiet('the order');

    expect(page.text('#noMsg')).toMatch(/склад/i);
  });
});

describe('when the комплект cannot be assembled', () => {
  it('does not offer it', async () => {
    // A bundle whose parts are not in the catalogue would produce an order the
    // server refuses — better not to offer it than to fail at the last click.
    const orphaned = {
      ...INVENTORY,
      products: INVENTORY.products.filter((p) => p.id !== 'tracker'),
    };
    const page = await render(orphaned);
    expect((page.$('input[name="noKind"][value="bundle"]') as HTMLInputElement).disabled).toBe(true);
  });
});
