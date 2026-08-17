/**
 * The two warehouse forms, in a browser.
 *
 * warehouse.test.ts proves the routes. This proves somebody can reach them:
 * the forms exist, they are filled from the same shelf the table is drawn
 * from, and they send what the server expects. A route with no caller is this
 * repo's most common defect and the one no API test can see.
 *
 * The two things checked hardest are the ones that protect the ledger: the
 * mismatch warning before the button is pressed, and the fact a blank count
 * field means "not counted" rather than zero.
 */

/**
 * WAITING — the fixed sleeps that used to stand in for "the panel has finished"
 * are gone. quiet() returns when no request is in flight, none has been issued
 * for several consecutive turns and the page has no timer outstanding, and it
 * THROWS rather than hand a half-drawn screen to an assertion. A wall-clock
 * wait decides its verdict on how busy the machine is; this one decides it on
 * the work being done. See helpers/panelSettle.ts.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const INVENTORY = {
  windowDays: 30, leadTimeDays: 14, reorder: [], lowStock: [],
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: 'AB-W', priceMinor: 2490000, costMinor: 1500000,
      kind: 'simple', active: true, stock: 12, lowStock: false, lowStockThreshold: 3, parts: [],
      soldInWindow: 30, perDay: 1, daysOfCover: 12, noSales: false, reorder: false,
      variants: [
        { id: 'v-black', color: 'Чёрный', colorHex: '#111', stock: 7 },
        { id: 'v-rose', color: 'Розовый', colorHex: '#f9a', stock: 5 },
      ],
    },
    {
      // A bundle holds no shelf of its own — receiving 10 combos is not a
      // thing, so it must not be offered.
      id: 'combo', name: 'Комплект', sku: null, priceMinor: 3900000, costMinor: null,
      kind: 'bundle', active: true, stock: 5, lowStock: false, lowStockThreshold: 1,
      parts: [{ partId: 'watch', partName: 'Часы', qty: 1 }],
      soldInWindow: 0, perDay: 0, daysOfCover: null, noSales: true, reorder: false,
      variants: [],
    },
  ],
};

interface Sent { path: string; method: string; body: Record<string, unknown> | null }

async function openStock() {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Sent[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const settle = panelSettle();

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
      (window as unknown as { confirm: () => boolean }).confirm = () => true;

      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
        }
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'warehouse', displayName: 'Ерен' }
          : p.includes('/admin/inventory/moves') ? { moves: [] }
          : p.includes('/admin/inventory') ? INVENTORY
          : p.includes('/admin/device-registry') ? { devices: [] }
          : { ok: true, stock: 20, serialsAdded: 3, serialsSkipped: 0, changed: 1, netDelta: -2, lines: [] };
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet();
  window.document.querySelector('[data-view="stock"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet();

  const $ = (sel: string) => window.document.querySelector(sel) as HTMLElement;
  const type = (sel: string, value: string) => {
    const el = $(sel) as HTMLInputElement | HTMLTextAreaElement;
    el.value = value;
    el.dispatchEvent(new window.Event('input', { bubbles: true }));
  };
  const submit = async (sel: string) => {
    $(sel).dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await settle.quiet();
  };
  return { window, errors, sent, $, type, submit };
}

describe('Приёмка in the panel', () => {
  it('offers every colour, and no bundle', async () => {
    const { $, errors } = await openStock();
    expect(errors, errors.join('\n')).toEqual([]);
    const sel = $('#recvVariant') as HTMLSelectElement;
    const values = [...sel.options].map((o) => o.value);
    expect(values).toEqual(['v-black', 'v-rose']);
    // The count is on the label, so somebody receiving stock can see what is
    // already there without leaving the field.
    expect(sel.options[0].textContent).toContain('7');
    expect(values).not.toContain('combo');
  });

  it('warns about a mismatch before the button is pressed', async () => {
    // The server refuses it; finding that out after typing forty MACs is
    // finding it out too late to be useful.
    const { $, type } = await openStock();
    type('#recvQty', '5');
    type('#recvSerials', 'AA:01\nAA:02');
    expect($('#recvCheck').textContent).toContain('серийных номеров 2');
    expect($('#recvCheck').textContent).toContain('допишите недостающие');
  });

  it('says so when they agree, rather than staying silent', async () => {
    const { $, type } = await openStock();
    type('#recvQty', '2');
    type('#recvSerials', 'AA:01, AA:02');
    expect($('#recvCheck').textContent).toContain('на склад встанет 2 шт.');
  });

  it('spells out the claim and the cost before anything is sent', async () => {
    // «Приёмка принимает факт, а не накладную.» What somebody needs to know at
    // this moment is that the delivery WILL be accepted and what it will cost
    // — not that the form is about to refuse them.
    const { $, type } = await openStock();
    type('#recvQty', '28');
    type('#recvInvoice', '30');
    type('#recvDefect', '2');
    type('#recvCost', '2600'); // ₸ for the batch
    const note = $('#recvCheck').textContent ?? '';
    expect(note).toContain('на склад встанет 26 шт.');
    expect(note).toContain('брак 2 шт.');
    expect(note).toContain('недостача 2 шт.');
    expect(note).toContain('претензия');
    // 2 600 ₸ over 26 sellable units is 100 ₸ each.
    expect(note).toContain('100 ₸ за шт.');
  });

  it('sends tenge as tiyn, because the whole backend is minor units', async () => {
    // One place converting and another not is how a price ends up a hundred
    // times wrong, on the number the owner's margin is computed from.
    const { type, submit, sent } = await openStock();
    type('#recvQty', '10');
    type('#recvCost', '2600');
    await submit('#recvForm');
    const req = sent.find((r) => r.path.includes('/receipt'));
    expect(req!.body!.batchCostMinor).toBe(260000);
  });

  it('leads with the claim when there is one', async () => {
    const { window, type, submit, $ } = await openStock();
    (window as unknown as { fetch: unknown }).fetch = (async (path: string) => {
      const p = String(path);
      const body =
        p.includes('/receipt') ? { ok: true, stock: 28, received: 28, stocked: 28, defective: 0, shortfall: 2 }
        : p.includes('/admin/inventory/moves') ? { moves: [] }
        : p.includes('/admin/inventory') ? INVENTORY
        : p.includes('/admin/device-registry') ? { devices: [] }
        : {};
      return { ok: true, status: 200, text: async () => '', json: async () => body };
    }) as never;
    type('#recvQty', '28');
    await submit('#recvForm');
    // Not buried after a list of successes: it is the thing somebody has to act
    // on, and «Поставка оприходована ✓» first reads as "all fine".
    expect(($('#recvMsg').textContent ?? '').startsWith('Принято с недостачей 2 шт.')).toBe(true);
  });

  it('sends the quantity and the serials in one request', async () => {
    const { type, submit, sent } = await openStock();
    type('#recvQty', '3');
    type('#recvSerials', 'AA:01\nAA:02\nAA:03');
    await submit('#recvForm');
    const req = sent.find((r) => r.path.includes('/admin/inventory/receipt'));
    expect(req, 'the form is wired to nothing').toBeDefined();
    expect(req!.method).toBe('POST');
    expect(req!.body).toMatchObject({ variantId: 'v-black', qty: 3 });
    expect(String(req!.body!.serials)).toContain('AA:03');
  });

  it('reports the serials that were already known, not just the ones added', async () => {
    // "Записано ✓" that hides a skipped serial is how somebody believes a unit
    // is registered when it is not.
    const { window, type, submit, $ } = await openStock();
    (window as unknown as { fetch: unknown }).fetch = (async (path: string, init?: RequestInit) => {
      const p = String(path);
      const body =
        p.includes('/admin/inventory/receipt') ? { ok: true, stock: 9, serialsAdded: 1, serialsSkipped: 2 }
        : p.includes('/admin/inventory/moves') ? { moves: [] }
        : p.includes('/admin/inventory') ? INVENTORY
        : p.includes('/admin/device-registry') ? { devices: [] }
        : {};
      void init;
      return { ok: true, status: 200, text: async () => '', json: async () => body };
    }) as never;
    type('#recvQty', '3');
    await submit('#recvForm');
    expect($('#recvMsg').textContent).toContain('уже были в базе: 2');
  });
});

describe('Инвентаризация in the panel', () => {
  it('lists every colour with what the system believes', async () => {
    const { window } = await openStock();
    const rows = window.document.querySelectorAll('#takeBody .takecount');
    expect(rows.length).toBe(2);
    expect((window.document.querySelector('#takeBody') as HTMLElement).textContent).toContain('в базе 7');
  });

  it('summarises the discrepancy before anything is written', async () => {
    const { $, type } = await openStock();
    type('#takeBody .takecount[data-vid="v-black"]', '5');
    expect($('#takeDiff').textContent).toContain('Расхождений: 1');
    expect($('#takeDiff').textContent).toContain('7→5');
    expect($('#takeDiff').textContent).toContain('-2');
  });

  it('says so when the shelf agrees', async () => {
    const { $, type } = await openStock();
    type('#takeBody .takecount[data-vid="v-black"]', '7');
    expect($('#takeDiff').textContent).toContain('расхождений нет');
  });

  it('a blank field is NOT counted as zero', async () => {
    // Treating an untouched row as a count of zero would write off the whole
    // shelf on the first partial stocktake anybody does.
    const { type, submit, sent } = await openStock();
    type('#takeBody .takecount[data-vid="v-black"]', '5');
    await submit('#takeForm');
    const req = sent.find((r) => r.path.includes('/stocktake'));
    expect(req).toBeDefined();
    expect(req!.body!.counts).toEqual([{ variantId: 'v-black', counted: 5 }]);
  });

  it('the button stays dead until something is counted', async () => {
    const { $, type } = await openStock();
    expect(($('#takeBtn') as HTMLButtonElement).disabled).toBe(true);
    type('#takeBody .takecount[data-vid="v-rose"]', '5');
    expect(($('#takeBtn') as HTMLButtonElement).disabled).toBe(false);
  });

  it('says so when the server could not write every correction', async () => {
    // Reporting a partial count as done is how somebody believes a shelf was
    // fixed. The server names what it refused; the panel has to pass that on.
    const { window, type, submit, $ } = await openStock();
    (window as unknown as { fetch: unknown }).fetch = (async (path: string) => {
      const p = String(path);
      const body =
        p.includes('/stocktake') ? { ok: false, refused: ['v-black'], changed: 0, netDelta: 0, lines: [] }
        : p.includes('/admin/inventory/moves') ? { moves: [] }
        : p.includes('/admin/inventory') ? INVENTORY
        : p.includes('/admin/device-registry') ? { devices: [] }
        : {};
      return { ok: true, status: 200, text: async () => '', json: async () => body };
    }) as never;
    type('#takeBody .takecount[data-vid="v-black"]', '3');
    await submit('#takeForm');
    expect($('#takeMsg').textContent).toContain('не полностью');
    expect($('#takeMsg').textContent).toContain('1 позиций');
  });

  it('asks before writing irreversible ledger rows', async () => {
    const { window, type, submit, sent } = await openStock();
    (window as unknown as { confirm: () => boolean }).confirm = () => false;
    type('#takeBody .takecount[data-vid="v-black"]', '1');
    await submit('#takeForm');
    expect(sent.some((r) => r.path.includes('/stocktake')), 'a declined confirm still wrote').toBe(false);
  });
});
