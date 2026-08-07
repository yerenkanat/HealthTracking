/**
 * The Склад screen says how long the shelf lasts, not just how full it is.
 *
 * Two halves, both here on purpose:
 *
 *   1. the whole chain over HTTP — a sale booked into the ledger comes back
 *      out of /admin/inventory as days of cover. runway.test.ts proves the
 *      arithmetic; this proves the arithmetic is wired to the ledger;
 *   2. the sentence rendered in a browser. A number the API computes and the
 *      panel never prints is the repo's most common defect, and «26 шт» with
 *      no comment is exactly what docs/CLAUDE-admin-design.md calls out.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

function makeApp() {
  const repo = createMemoryRepository();
  const app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
    },
    { logger: false },
  );
  return { app, repo };
}

/** Book a stock movement the way the panel does — over HTTP, not into the fake. */
async function move(app: ReturnType<typeof makeApp>['app'], variantId: string, delta: number, reason: string) {
  const res = await app.inject({
    method: 'POST', url: '/admin/inventory/moves',
    payload: { variantId, delta, reason, note: 'test' },
  });
  expect(res.statusCode, res.body).toBe(200);
}

describe('the ledger becomes a date', () => {
  it('a month of sales comes back as days of cover', async () => {
    const { app, repo } = makeApp();
    const inv = async () => (await app.inject({ method: 'GET', url: '/admin/inventory' })).json();

    const variantId = (await repo.adminProducts())
      .find((p) => p.kind !== 'bundle' && p.variants.length)!.variants[0].id;
    const productId = (await repo.adminProducts())
      .find((p) => p.variants.some((v) => v.id === variantId))!.id;

    // Receive 100, then sell 60 over the window: 2/day, 20 days of cover.
    await move(app, variantId, 100, 'receipt');
    await move(app, variantId, -60, 'sale');

    const p = (await inv()).products.find((x: { id: string }) => x.id === productId);
    expect(p.stock).toBe(40);
    expect(p.soldInWindow).toBe(60);
    expect(p.perDay).toBe(2);
    expect(p.daysOfCover).toBe(20);
    expect(p.noSales).toBe(false);
    expect(p.reorder, '20 days is more than the 14-day lead time').toBe(false);
    await app.close();
  });

  it('a receipt is not a sale — only sales set the rate', async () => {
    // The obvious wrong implementation sums every move, so restocking a
    // product would report it as selling fast and order more of it.
    const { app, repo } = makeApp();
    const variantId = (await repo.adminProducts())
      .find((p) => p.kind !== 'bundle' && p.variants.length)!.variants[0].id;
    const productId = (await repo.adminProducts())
      .find((p) => p.variants.some((v) => v.id === variantId))!.id;

    await move(app, variantId, 50, 'receipt');
    await move(app, variantId, -2, 'writeoff');

    const body = (await app.inject({ method: 'GET', url: '/admin/inventory' })).json();
    const p = body.products.find((x: { id: string }) => x.id === productId);
    expect(p.soldInWindow).toBe(0);
    expect(p.noSales).toBe(true);
    expect(p.daysOfCover).toBeNull();
    await app.close();
  });

  it('says which numbers it was computed from', async () => {
    // Without the window in the response the panel has to hardcode "30 дней",
    // and the day the server changes it the screen quietly lies.
    const { app } = makeApp();
    const body = (await app.inject({ method: 'GET', url: '/admin/inventory' })).json();
    expect(body.windowDays).toBe(30);
    expect(body.leadTimeDays).toBe(14);
    await app.close();
  });

  it('flags what runs out before a shipment can land', async () => {
    const { app, repo } = makeApp();
    const variantId = (await repo.adminProducts())
      .find((p) => p.kind !== 'bundle' && p.variants.length)!.variants[0].id;
    const productId = (await repo.adminProducts())
      .find((p) => p.variants.some((v) => v.id === variantId))!.id;

    // 150 in, 120 sold: 4/day, 30 left → 7 days of cover against a 14-day lead.
    await move(app, variantId, 150, 'receipt');
    await move(app, variantId, -120, 'sale');

    const body = (await app.inject({ method: 'GET', url: '/admin/inventory' })).json();
    const p = body.products.find((x: { id: string }) => x.id === productId);
    expect(p.daysOfCover).toBe(7);
    expect(p.reorder).toBe(true);
    expect(body.reorder).toContain(productId);
    // The hand-set threshold has NOT fired — 30 units is plenty by that rule.
    // That is the case a threshold cannot see and this is here to cover.
    expect(p.lowStock).toBe(false);
    await app.close();
  });
});

// ---------------------------------------------------------------------------

const INVENTORY = {
  windowDays: 30,
  leadTimeDays: 14,
  reorder: ['watch'],
  lowStock: [],
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: 'AB-WATCH-01',
      priceMinor: 2490000, costMinor: 1500000, kind: 'simple', active: true,
      stock: 26, lowStock: false, lowStockThreshold: 3, parts: [],
      soldInWindow: 180, perDay: 6, daysOfCover: 4, noSales: false, reorder: true,
      variants: [{ id: 'v1', color: 'Розовый', colorHex: '#f9a', stock: 26 }],
    },
    {
      // Sitting there. Must not read as "хватит навсегда".
      id: 'strap', name: 'Ремешок', sku: null,
      priceMinor: 350000, costMinor: null, kind: 'simple', active: true,
      stock: 40, lowStock: false, lowStockThreshold: 3, parts: [],
      soldInWindow: 0, perDay: 0, daysOfCover: null, noSales: true, reorder: false,
      variants: [{ id: 'v2', color: 'Синий', colorHex: '#48f', stock: 40 }],
    },
  ],
};

async function renderStock() {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = () => {};

      window.fetch = (async (path: string) => {
        const p = String(path);
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/inventory/moves') ? { moves: [] }
          : p.includes('/admin/inventory') ? INVENTORY
          : p.includes('/admin/device-registry') ? { devices: [] }
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 200));
  window.document.querySelector('[data-view="stock"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 300));
  return { window, errors, body: window.document.querySelector('#stockBody')!.textContent ?? '' };
}

describe('the sentence reaches the screen', () => {
  it('a fast seller reads as days, a rate, and what to do', async () => {
    const { body, errors } = await renderStock();
    expect(errors, errors.join('\n')).toEqual([]);
    expect(body).toContain('хватит на 4 дн.');
    expect(body).toContain('6 шт/день');
    expect(body).toContain('пора заказывать');
    expect(body).toContain('14 дн.'); // the lead time it was judged against
  });

  it('a product nobody is buying says so, and never "хватит на ∞"', async () => {
    const { body } = await renderStock();
    expect(body).toContain('продаж за 30 дн. не было');
    expect(body).not.toContain('Infinity');
    expect(body).not.toContain('NaN');
    expect(body).not.toContain('null');
  });

  it('the banner names what is running out and how soon', async () => {
    const { window } = await renderStock();
    const banner = window.document.querySelector('#stockLow') as HTMLElement;
    expect(banner.hidden, 'a product with 4 days of cover must raise the banner').toBe(false);
    const list = window.document.querySelector('#stockLowList')!.textContent ?? '';
    expect(list).toContain('Часы Ana-Bala');
    expect(list).toContain('хватит на 4 дн.');
    // The one that is not selling is not in the reorder banner: it has 40 on
    // the shelf and no demand, and telling somebody to order more of it is
    // the opposite of the right action.
    expect(list).not.toContain('Ремешок');
  });

  it('every product carries an explaining line, not a bare count', async () => {
    const { window } = await renderStock();
    const notes = window.document.querySelectorAll('#stockBody .metricnote');
    expect(notes.length).toBe(INVENTORY.products.length);
    for (const n of notes) expect((n.textContent ?? '').trim().length).toBeGreaterThan(8);
  });
});
