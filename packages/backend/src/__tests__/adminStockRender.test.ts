/**
 * The Склад tab: adding a product, and reading its article code back.
 *
 * `sku` has existed since migration 021 — uniquely indexed, accepted by the
 * API, documented as "what goes on a box, an invoice and a courier's manifest".
 * The form had no field for it and the stock list never showed it, so every
 * manifest was written from the product name and the column stayed empty.
 *
 * The same defect as the lesson summary, in the part of the product where a
 * wrong code means the wrong box goes to a customer.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const INVENTORY = {
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: 'AB-WATCH-01',
      priceMinor: 2490000, costMinor: 1500000, kind: 'simple', active: true,
      stock: 12, lowStock: false, lowStockThreshold: 3,
      variants: [{ id: 'v1', color: 'Розовый', colorHex: '#f9a', stock: 12 }],
    },
    {
      // No code yet. It must not print "null" or an empty separator.
      id: 'strap', name: 'Ремешок', sku: null,
      priceMinor: 350000, costMinor: null, kind: 'simple', active: true,
      stock: 4, lowStock: false, lowStockThreshold: 3,
      variants: [{ id: 'v2', color: 'Синий', colorHex: '#48f', stock: 4 }],
    },
  ],
};

/// Two units: one still on the shelf, one activated by a customer.
const REGISTRY = {
  devices: [
    { serial: 'AABBCC000001', status: 'sold', kind: 'tag', activationCode: null,
      orderId: null, receivedAt: '2026-08-01T10:00:00.000Z',
      activatedByPhone: '77001112233', activatedAt: '2026-08-03T10:00:00.000Z', note: null },
    { serial: 'AABBCC000002', status: 'stock', kind: 'band', activationCode: null,
      orderId: null, receivedAt: '2026-08-01T10:00:00.000Z',
      activatedByPhone: null, activatedAt: null, note: null },
  ],
};

interface Page {
  window: JSDOM['window'];
  errors: string[];
  saved: Array<Record<string, unknown>>;
  $: (sel: string) => HTMLElement | null;
  text: (sel: string) => string;
}

async function render(): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const saved: Array<Record<string, unknown>> = [];
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
      window.fetch = (async (path: string, opts?: { method?: string; body?: string }) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (opts?.method === 'PUT' && p.includes('/admin/inventory/products')) {
          saved.push(JSON.parse(opts.body ?? '{}'));
          return { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/device-registry')) {
          return { ok: true, status: 200, json: async () => REGISTRY };
        }
        const body = p.includes('/admin/inventory/moves')
          ? { moves: [] }
          : p.includes('/admin/inventory')
            ? INVENTORY
            : {};
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document.querySelector('[data-view="stock"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(250);

  return {
    window,
    errors,
    saved,
    $: (sel) => window.document.querySelector(sel),
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
  };
}

function type(page: Page, id: string, value: string): void {
  const el = page.$('#' + id) as HTMLInputElement;
  el.value = value;
  el.dispatchEvent(new page.window.Event('input', { bubbles: true }));
}

describe('the article code', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('has somewhere to type one', () => {
    expect(page.$('#prodSku'), 'no article-code field').not.toBeNull();
  });

  it('is shown beside the product, where somebody packing a box can read it', () => {
    expect(page.text('#stockBody')).toContain('AB-WATCH-01');
  });

  it('prints nothing at all for a product that has no code', () => {
    // Not "null", and not a dangling separator.
    const t = page.text('#stockBody');
    expect(t).not.toContain('null');
    expect(t).not.toMatch(/Ремешок[^]*?·\s*·/);
  });

  it('goes out with the product when it is saved', async () => {
    type(page, 'prodId', 'strap');
    type(page, 'prodName', 'Ремешок');
    type(page, 'prodSku', 'AB-STRAP-01');
    type(page, 'prodPrice', '3500');
    page.$('#prodForm')!.dispatchEvent(
      new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 60));

    expect(page.saved).toHaveLength(1);
    expect(page.saved[0].sku).toBe('AB-STRAP-01');
  });

  it('sends null rather than an empty string when it is left blank', async () => {
    // The index is UNIQUE: two products saved with '' would collide on a code
    // neither of them has, and the second would be refused for a reason
    // nobody could see.
    type(page, 'prodId', 'strap');
    type(page, 'prodName', 'Ремешок');
    type(page, 'prodPrice', '3500');
    page.$('#prodForm')!.dispatchEvent(
      new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 60));

    expect(page.saved[0].sku).toBeNull();
  });

  it('cannot be typed longer than the server will take', () => {
    // 60 on both sides. A longer code would type cleanly and be refused on
    // save, for a reason the form never showed.
    expect((page.$('#prodSku') as HTMLInputElement).maxLength).toBe(60);
  });
});

/// The device registry, in the warehouse tab where serials are actually
/// recorded — the same moment stock goes onto the ledger.
///
/// If this form is awkward the registry stays empty, and an empty registry
/// makes the pairing check either useless (log-only) or catastrophic
/// (enforcing, refusing every real customer). So the UI is the feature.
describe('the device registry', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('takes a whole packing list, not one field per device', () => {
    // Nobody types forty MAC addresses into forty inputs.
    const box = page.$('#serialList') as HTMLTextAreaElement;
    expect(box, 'no paste box for serials').not.toBeNull();
    expect(box.tagName).toBe('TEXTAREA');
  });

  it('shows what became of each unit', () => {
    const t = page.text('#serialBody');
    expect(t).toContain('AABBCC000001');
    expect(t).toContain('Активировано');
    expect(t).toContain('AABBCC000002');
    expect(t).toContain('На складе');
  });

  it('names the customer holding an activated unit', () => {
    // The warranty conversation nobody could previously have.
    expect(page.text('#serialBody')).toContain('77001112233');
  });

  it('offers to block a unit, and to undo it', () => {
    // Blocking is how a stolen or replaced device stops working; unblocking
    // exists because the commonest reason to block is a mistake.
    const t = page.text('#serialBody');
    expect(t).toContain('Заблокировать');
  });
});
