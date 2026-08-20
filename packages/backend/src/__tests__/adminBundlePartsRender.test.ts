/**
 * Меняем состав комплекта — docs/BACKLOG.md §3.3.
 *
 * PUT /admin/inventory/products/:id/parts was written, tested and guarded
 * against a bundle that contains itself — and had no caller anywhere. The
 * warehouse row printed «Комплект из: Часы + Трекер» and offered no way to
 * change it, so a bundle assembled from the wrong SKU needed a developer with
 * database access. The customer, meanwhile, gets whatever the row says.
 *
 * Two halves:
 *   - the ROUTE over HTTP against a real memory repository, a write read back
 *     through GET /admin/inventory — the same read the screen draws from;
 *   - the PANEL in jsdom: the button exists, it opens the real composition, a
 *     save sends what is on screen, removing a part asks first, and a refusal
 *     is reported as one.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

// ---------------------------------------------------------------------------
// The route
// ---------------------------------------------------------------------------

let app: FastifyInstance;
let repo: Repository;
let cookie = '';

beforeEach(async () => {
  repo = createMemoryRepository();
  app = buildServer(
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
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});
afterEach(async () => { await app.close(); });

const inventory = async () =>
  (await app.inject({ method: 'GET', url: '/admin/inventory', headers: { cookie } })).json();
const setParts = (id: string, parts: Array<{ partId: string; qty: number }>) =>
  app.inject({
    method: 'PUT', url: `/admin/inventory/products/${id}/parts`,
    payload: { parts }, headers: { cookie },
  });
const combo = async () =>
  (await inventory()).products.find((p: { id: string }) => p.id === 'combo');

describe('PUT /admin/inventory/products/:id/parts, read back', () => {
  it('replaces the composition and the shelf reads the new one', async () => {
    expect((await combo()).parts.map((x: { partId: string }) => x.partId).sort())
      .toEqual(['tracker', 'watch']);

    expect((await setParts('combo', [{ partId: 'watch', qty: 2 }])).statusCode).toBe(200);

    const after = await combo();
    expect(after.parts.map((x: { partId: string }) => x.partId)).toEqual(['watch']);
    expect(after.parts[0].qty).toBe(2);
    // The name travels with it — the row prints it, and an id in a warehouse
    // sentence is a code nobody reads.
    expect(after.parts[0].partName).toBeTruthy();
  });

  it('an emptied composition means nothing can be assembled', async () => {
    expect((await setParts('combo', [])).statusCode).toBe(200);
    const after = await combo();
    expect(after.parts).toEqual([]);
    expect(after.stock).toBe(0);
  });

  it('records who changed it', async () => {
    await setParts('combo', [{ partId: 'watch', qty: 1 }]);
    const { audit } = (await app.inject({
      method: 'GET', url: '/admin/audit', headers: { cookie },
    })).json();
    const row = audit.find((a: { action: string }) => a.action === 'bundle_parts');
    expect(row, 'a change to what a customer receives went unrecorded').toBeDefined();
    expect(row.target).toBe('combo');
  });

  it('still refuses a bundle inside itself, and changes nothing', async () => {
    const before = (await combo()).parts.map((x: { partId: string }) => x.partId).sort();
    expect((await setParts('combo', [{ partId: 'combo', qty: 1 }])).statusCode).toBe(400);
    expect((await combo()).parts.map((x: { partId: string }) => x.partId).sort()).toEqual(before);
  });
});

// ---------------------------------------------------------------------------
// The panel
// ---------------------------------------------------------------------------

const INVENTORY = {
  windowDays: 30, leadTimeDays: 14, lowStock: [], reorder: [], reorderCovered: [],
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: null,
      priceMinor: 2_490_000, costMinor: null, kind: 'simple', active: true,
      stock: 12, lowStock: false, lowStockThreshold: 3, inTransit: 0,
      daysOfCover: null, perDay: null, noSales: true, parts: [],
      variants: [{ id: 'v1', color: 'Розовый', colorHex: '#f9a', stock: 12, inTransit: 0 }],
    },
    {
      id: 'tracker', name: 'Трекер', sku: null,
      priceMinor: 490_000, costMinor: null, kind: 'simple', active: true,
      stock: 6, lowStock: false, lowStockThreshold: 3, inTransit: 0,
      daysOfCover: null, perDay: null, noSales: true, parts: [],
      variants: [{ id: 'v2', color: 'Синий', colorHex: '#48f', stock: 6, inTransit: 0 }],
    },
    {
      id: 'combo', name: 'Комплект «Мама и ребёнок»', sku: null,
      priceMinor: 2_900_000, costMinor: null, kind: 'bundle', active: true,
      stock: 6, lowStock: false, lowStockThreshold: 0, inTransit: 0,
      daysOfCover: null, perDay: null, noSales: true, variants: [],
      parts: [
        { partId: 'watch', partName: 'Часы Ana-Bala', qty: 1 },
        { partId: 'tracker', partName: 'Трекер', qty: 2 },
      ],
    },
  ],
};

interface Sent { url: string; method: string; body: unknown }

interface Page {
  window: JSDOM['window'];
  errors: string[];
  confirms: string[];
  sent: Sent[];
  text(sel: string): string;
  el(sel: string): Element | null;
  click(sel: string): Promise<void>;
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function render(opts: { answer?: boolean; putStatus?: number } = {}): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const confirms: string[] = [];
  const sent: Sent[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const settle = panelSettle();
  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/admin', virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: () => void }).alert = () => {};
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return opts.answer !== false;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (method === 'PUT' && /\/parts$/.test(p)) {
          sent.push({ url: p, method, body: JSON.parse(init?.body ?? '{}') });
          const code = opts.putStatus ?? 200;
          return { ok: code === 200, status: code, json: async () => ({ ok: code === 200 }) };
        }
        if (method !== 'GET') sent.push({ url: p, method, body: init?.body ?? null });
        const body = p.includes('/admin/inventory/moves') ? { moves: [] }
          : p.includes('/admin/inventory') ? INVENTORY
          : p.includes('/admin/device-registry') ? { devices: [] }
          : {};
        return { ok: true, status: 200, json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="stock"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Склад tab');

  return {
    window, errors, confirms, sent,
    quiet: settle.quiet,
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    el: (sel) => window.document.querySelector(sel),
    click: async (sel) => {
      const el = window.document.querySelector(sel) as HTMLElement | null;
      expect(el, `no ${sel}`).not.toBeNull();
      el!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet(`the click on ${sel}`);
    },
  };
}

const open = async (page: Page) => { await page.click('.bndedit[data-bid="combo"]'); };

describe('the warehouse row offers to change the composition', () => {
  it('boots without throwing', async () => {
    const p = await render();
    expect(p.errors, p.errors.join('\n')).toEqual([]);
  });

  it('prints the composition with its quantities and a button beside it', async () => {
    const p = await render();
    const t = p.text('#stockBody');
    expect(t).toContain('Комплект из: Часы Ana-Bala + Трекер ×2');
    expect(p.el('.bndedit[data-bid="combo"]')).not.toBeNull();
  });

  it('opens on the real composition, not an empty form', async () => {
    const p = await render();
    await open(p);
    expect((p.el('#bundleCard') as HTMLElement).hasAttribute('hidden')).toBe(false);
    const selects = p.window.document.querySelectorAll('#bndRows .bnd-part');
    expect(selects.length).toBe(2);
    expect((selects[0] as HTMLSelectElement).value).toBe('watch');
    expect((selects[1] as HTMLSelectElement).value).toBe('tracker');
    const qty = p.window.document.querySelectorAll('#bndRows .bnd-qty');
    expect((qty[1] as HTMLInputElement).value).toBe('2');
  });

  it('does not offer the bundle as a part of itself', async () => {
    const p = await render();
    await open(p);
    const values = Array.from(
      (p.el('#bndRows .bnd-part') as HTMLSelectElement).options).map((o) => o.value);
    expect(values).toContain('watch');
    expect(values).toContain('tracker');
    expect(values, 'the bundle could be put inside itself').not.toContain('combo');
  });

  it('states what the composition means for the shelf', async () => {
    const p = await render();
    await open(p);
    expect(p.text('#bndRule')).toContain('не лежит на складе');
  });
});

describe('saving a composition', () => {
  it('sends what is on screen, to the bundle that was opened', async () => {
    const p = await render();
    await open(p);
    const qty = p.el('#bndRows .bnd-qty') as HTMLInputElement;
    qty.value = '3';
    qty.dispatchEvent(new p.window.Event('input', { bubbles: true }));
    await p.click('#bndSave');

    const put = p.sent.find((s) => s.method === 'PUT');
    expect(put, 'the save never reached the server').toBeDefined();
    expect(put!.url).toBe('/admin/inventory/products/combo/parts');
    expect(put!.body).toEqual({ parts: [{ partId: 'watch', qty: 3 }, { partId: 'tracker', qty: 2 }] });
    // Nothing was removed, so nothing was asked: a dialog on every save is
    // dismissed reflexively within a week.
    expect(p.confirms).toEqual([]);
    expect((p.el('#bundleCard') as HTMLElement).hasAttribute('hidden')).toBe(true);
  });

  it('swaps a part for another SKU', async () => {
    const p = await render();
    await open(p);
    const sel = p.el('#bndRows .bnd-part') as HTMLSelectElement;
    sel.value = 'tracker';
    sel.dispatchEvent(new p.window.Event('change', { bubbles: true }));
    await p.click('#bndSave');
    const put = p.sent.find((s) => s.method === 'PUT')!;
    expect((put.body as { parts: Array<{ partId: string }> }).parts[0].partId).toBe('tracker');
  });

  it('warns when the same part is listed twice', async () => {
    const p = await render();
    await open(p);
    const sel = p.el('#bndRows .bnd-part') as HTMLSelectElement;
    sel.value = 'tracker';
    sel.dispatchEvent(new p.window.Event('change', { bubbles: true }));
    await p.quiet('the duplicate-part check');
    expect(p.text('#bndRule')).toContain('дважды');
  });

  it('adds a part', async () => {
    const p = await render();
    await open(p);
    await p.click('#bndRows .bnd-del');   // down to one
    await p.click('#bndAdd');
    expect(p.window.document.querySelectorAll('#bndRows .bnd-part').length).toBe(2);
  });
});

describe('removing a part asks first', () => {
  it('names the part that goes and what it means for the customer', async () => {
    const p = await render();
    await open(p);
    await p.click('#bndRows .bnd-del');
    expect(p.confirms).toEqual([]); // editing the draft asks nothing
    await p.click('#bndSave');
    expect(p.confirms.length, 'a part was dropped from a live bundle silently').toBe(1);
    expect(p.confirms[0]).toContain('Часы Ana-Bala');
    expect(p.confirms[0]).toMatch(/другой набор/);
  });

  it('sends nothing when the answer is no', async () => {
    const p = await render({ answer: false });
    await open(p);
    await p.click('#bndRows .bnd-del');
    await p.click('#bndSave');
    expect(p.sent.filter((s) => s.method === 'PUT')).toEqual([]);
    // And the card stays open on the edit that was not saved.
    expect((p.el('#bundleCard') as HTMLElement).hasAttribute('hidden')).toBe(false);
  });

  it('says an emptied composition means the bundle cannot be assembled', async () => {
    const p = await render();
    await open(p);
    await p.click('#bndRows .bnd-del');
    await p.click('#bndRows .bnd-del');
    expect(p.text('#bndRows')).toContain('Состав пуст');
    await p.click('#bndSave');
    expect(p.confirms[0]).toContain('останется без деталей');
  });
});

describe('a failed save says so', () => {
  it('reports a refusal instead of closing over an unsaved change', async () => {
    const p = await render({ putStatus: 400 });
    await open(p);
    await p.click('#bndSave');
    expect(p.text('#bndMsg')).toContain('не принял состав');
    expect(p.el('#bndMsg')!.className).toContain('err');
    // The card must not close: a closed card over a failed write reads as done.
    expect((p.el('#bundleCard') as HTMLElement).hasAttribute('hidden')).toBe(false);
  });

  it('names a refusal by capability as a refusal', async () => {
    const p = await render({ putStatus: 403 });
    await open(p);
    await p.click('#bndSave');
    expect(p.text('#bndMsg')).toContain('склад');
    expect(p.text('#bndMsg')).toContain('Ничего не сохранено');
  });
});
