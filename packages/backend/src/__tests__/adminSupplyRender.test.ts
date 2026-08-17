/**
 * Кадры 07a «Поставки» и 07g «Поставщики», как их РИСУЕТ браузер.
 *
 * The warehouse screen could answer two questions — what is on the shelf, and
 * how long it lasts — and was silent on the third, which is the one that
 * decides whether to order today: what is already coming. So it printed «пора
 * заказывать» beside goods ordered a fortnight ago, and a buyer either ordered
 * them twice or stopped believing the banner.
 *
 * Rendered with runScripts: 'dangerously' rather than grepped, because the
 * failure mode this project keeps producing is a finished card nothing
 * navigates to and a renderer nothing calls. "Verified structurally" would pass
 * against a card that never fills.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * This was the worst file in the directory for it: SIXTEEN fixed sleeps, each
 * deciding its verdict on elapsed wall-clock rather than on the work being
 * finished. The screen loads five endpoints that chain off one another —
 * inventory, suppliers, purchase orders, moves, device registry — so a window
 * that closes early loses a different card each run, and «the same tree gave
 * two different answers» is exactly the shape of that.
 *
 * Every one is `page.quiet()` now: no request in flight, none newly issued for
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

/**
 * Ten watches left, one sold a day, twenty on the water.
 *
 * `reorder` is FALSE and `reorderCovered` is TRUE — the shape
 * routes/inventory.ts sends once an open order covers the gap — and
 * `inTransit` is deliberately not folded into `stock`: a box in customs is not
 * a shelf.
 */
const INVENTORY = {
  windowDays: 30,
  leadTimeDays: 14,
  products: [
    {
      id: 'watch', name: 'Часы Ana-Bala', sku: 'AB-WATCH-01',
      priceMinor: 2490000, costMinor: 1500000, kind: 'simple', active: true,
      stock: 10, lowStock: false, lowStockThreshold: 3,
      daysOfCover: 10, perDay: 1, noSales: false, soldInWindow: 30,
      inTransit: 20, reorder: false, reorderCovered: true,
      variants: [{ id: 'v1', color: 'Чёрный', colorHex: '#111', stock: 10, inTransit: 20 }],
    },
    {
      id: 'strap', name: 'Ремешок', sku: null,
      priceMinor: 350000, costMinor: null, kind: 'simple', active: true,
      stock: 0, lowStock: true, lowStockThreshold: 3,
      daysOfCover: 0, perDay: 0, noSales: true, soldInWindow: 0,
      inTransit: 0, reorder: false, reorderCovered: false,
      variants: [{ id: 'v2', color: 'Синий', colorHex: '#48f', stock: 0, inTransit: 0 }],
    },
  ],
  lowStock: ['strap'],
  reorder: [],
  reorderCovered: ['watch'],
};

const SUPPLIERS = {
  defaultLeadTimeDays: 14,
  suppliers: [
    { id: 's-1', name: 'Shenzhen Watch Co', contact: '+86 755 000 00 00', leadTimeDays: 21, active: true, createdAt: '2026-07-01T10:00:00.000Z' },
    // Declared nothing. The screen must fall back and SAY that it fell back.
    { id: 's-2', name: 'Местный склад', contact: null, leadTimeDays: null, active: true, createdAt: '2026-07-02T10:00:00.000Z' },
  ],
};

const ORDERS = {
  leadTimeDays: 14,
  orders: [
    {
      id: 'aa11bb22-cccc-dddd-eeee-ffff00001111',
      supplierId: 's-1', supplierName: 'Shenzhen Watch Co', supplierLeadTimeDays: 21,
      status: 'placed', placedAt: '2026-08-01T10:00:00.000Z', expectedAt: '2026-08-22',
      note: null, createdBy: 'st-1',
      createdAt: '2026-08-01T10:00:00.000Z', updatedAt: '2026-08-01T10:00:00.000Z',
      items: [{
        variantId: 'v1', productId: 'watch', productName: 'Часы Ana-Bala', color: 'Чёрный',
        qtyOrdered: 20, qtyReceived: 0,
        // Nobody has named a price. The screen prints «—», never a guess.
        unitCostMinor: null, receivedAt: null,
      }],
    },
  ],
};

/**
 * The same order after the first box of a split delivery.
 *
 * Reachable exactly as it looks: two colours were ordered, twelve of the twenty
 * black ones arrived and closed that line, and the order stays «В пути» because
 * the blue line is still open. The remaining eight are booked against this same
 * order, and the screen must compare them with what is still OWED.
 */
const PART_RECEIVED = {
  leadTimeDays: 14,
  orders: [{
    ...ORDERS.orders[0],
    items: [
      {
        variantId: 'v1', productId: 'watch', productName: 'Часы Ana-Bala', color: 'Чёрный',
        qtyOrdered: 20, qtyReceived: 12, unitCostMinor: null,
        receivedAt: '2026-08-10T10:00:00.000Z',
      },
      {
        variantId: 'v2', productId: 'strap', productName: 'Ремешок', color: 'Синий',
        qtyOrdered: 10, qtyReceived: 0, unitCostMinor: null, receivedAt: null,
      },
    ],
  }],
};

interface Page {
  window: JSDOM['window'];
  errors: string[];
  sent: Array<{ path: string; method: string; body: string | null }>;
  confirms: string[];
  $: (sel: string) => HTMLElement | null;
  text: (sel: string) => string;
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function render(
  opts: {
    confirmAnswer?: boolean; failWrites?: boolean; failStatus?: number;
    /// The «Поставки» payload, when a test needs a different one. Loosely
    /// typed on purpose: these fixtures are wire JSON, not repository rows.
    orders?: unknown;
    /// Slow the transport, to prove the verdict does not depend on the machine.
    latencyMs?: number;
  } = {},
): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Array<{ path: string; method: string; body: string | null }> = [];
  const confirms: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const settle = panelSettle({ latencyMs: opts.latencyMs });

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
      (window as unknown as { alert: () => void }).alert = () => {};
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return opts.confirmAnswer ?? true;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (method !== 'GET') sent.push({ path: p, method, body: init?.body ?? null });
        if (method !== 'GET' && opts.failWrites) {
          // What a real refusal looks like to apiSend: a non-ok response. The
          // status matters — 409 on the supplier form means «имя занято», and
          // the screen has to tell those two apart.
          const status = opts.failStatus ?? 409;
          return { ok: false, status, json: async () => ({ error: 'nope' }) };
        }
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен' }) };
        }
        // Order matters: '/admin/inventory' is a prefix of '/admin/inventory/moves'.
        const body =
          p.includes('/admin/inventory/moves') ? { moves: [] }
          : p.includes('/admin/purchase-orders') ? (opts.orders ?? ORDERS)
          : p.includes('/admin/suppliers') ? SUPPLIERS
          : p.includes('/admin/device-registry') ? { devices: [] }
          : p.includes('/admin/inventory') ? INVENTORY
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
    window,
    errors,
    sent,
    confirms,
    $: (sel) => window.document.querySelector(sel),
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    quiet: settle.quiet,
  };
}

describe('«Поставки в пути» — кадр 07a', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('renders the whole warehouse screen without throwing', () => {
    // One file, executed top to bottom: a slip in this block kills every later
    // block on the screen, not just this card.
    expect(page.errors).toEqual([]);
  });

  it('has a card, inside the Склад view, that the sidebar can reach', () => {
    const card = page.$('#stockSupplyCard');
    expect(card, 'no «Поставки в пути» card').not.toBeNull();
    expect(card!.closest('#stock'), 'the card is not inside the stock view').not.toBeNull();
    expect(
      page.$('.nav.sub[data-view="stock"][data-anchor="stockSupplyCard"]'),
      'a finished card with nothing navigating to it — the defect this repo keeps producing',
    ).not.toBeNull();
  });

  it('draws the order: ПН, поставщик, ожидается, что и сколько, статус', () => {
    const t = page.text('#supplyBody');
    expect(t, 'the order reference nobody can read out on the phone').toContain('aa11bb22');
    expect(t).toContain('Shenzhen Watch Co');
    expect(t).toContain('2026-08-22');
    expect(t).toContain('Часы Ana-Bala');
    expect(t).toContain('20 шт.');
    expect(t).toContain('В пути');
  });

  it('paints the status, rather than leaving it as chrome', () => {
    // `.pill.warn` is defined; `.chip.crit` never was, which is why the whole
    // panel moved to pills for status.
    const pill = page.$('#supplyBody .pill');
    expect(pill, 'the status is not a status chip').not.toBeNull();
    expect(pill!.className).toContain('warn');
  });

  it('prints «—» for a purchase price nobody has named', () => {
    // The cost of a unit is knowable in exactly one moment — when a receipt
    // carries the batch cost and it is divided by the usable units. A computed
    // guess here reaches the owner's dashboard as a margin nobody is earning.
    const cells = [...page.window.document.querySelectorAll('#supplyBody td')].map((td) => td.textContent);
    expect(cells).toContain('—');
  });

  it('states the rule under the table, including what in-transit is NOT', () => {
    const note = page.text('#supplyNote');
    expect(note).toContain('20 шт.');
    expect(note, 'nothing says that goods on the water are not stock').toMatch(/НЕ входят в остаток/);
  });

  it('says «заказ уже размещён» on the shelf instead of «пора заказывать»', () => {
    const shelf = page.text('#stockBody');
    expect(shelf).toContain('заказ уже размещён, ожидается 20 шт.');
    expect(shelf, 'the buyer is still being told to order what is already ordered')
      .not.toContain('пора заказывать');
  });

  it('keeps the short shelf visible in the banner rather than hiding it', () => {
    // The shelf did not fill up because somebody placed an order. Dropping the
    // row would say all is well; repeating «пора заказывать» would invite a
    // second order. The row changes its sentence instead.
    expect(page.text('#stockLowList')).toContain('заказ размещён, ожидается 20 шт.');
  });
});

describe('«Заказ поставщику» — кадр 07b', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('offers every colour on the shelf, and only real ones', () => {
    const sel = page.$('#poVariant') as HTMLSelectElement;
    expect(sel, 'no form to order anything').not.toBeNull();
    const labels = [...sel.options].map((o) => o.textContent);
    expect(labels.join(' ')).toContain('Часы Ana-Bala · Чёрный');
    expect(labels.join(' ')).toContain('Ремешок · Синий');
  });

  it('shows the shelf and the water as two numbers, never one', () => {
    const sel = page.$('#poVariant') as HTMLSelectElement;
    expect(sel.options[0].textContent).toContain('на складе 10');
    expect(sel.options[0].textContent, 'the two numbers were summed into a shelf that does not exist')
      .toContain('в пути 20');
  });

  it('offers the suppliers, with the term labelled as THEIR claim', () => {
    const sel = page.$('#poSupplier') as HTMLSelectElement;
    const labels = [...sel.options].map((o) => o.textContent).join(' ');
    expect(labels).toContain('Shenzhen Watch Co');
    expect(labels).toContain('со слов поставщика');
  });

  it('sends the order, in tiyn, and reports what the server made of it', async () => {
    (page.$('#poQty') as HTMLInputElement).value = '30';
    (page.$('#poCost') as HTMLInputElement).value = '15000';
    page.$('#poForm')!.dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await page.quiet('the purchase order');

    const post = page.sent.find((s) => s.path.endsWith('/admin/purchase-orders') && s.method === 'POST');
    expect(post, 'the form sent nothing').toBeTruthy();
    const body = JSON.parse(post!.body!);
    expect(body.items[0].qtyOrdered).toBe(30);
    // Tenge in the form, tiyn on the wire — one place converting and another
    // not is how a price ends up a hundred times wrong.
    expect(body.items[0].unitCostMinor).toBe(1500000);
    expect(body.place, 'a draft counts as nothing in transit').toBe(true);
  });

  it('says so when the order could not be placed', async () => {
    const failing = await render({ failWrites: true });
    (failing.$('#poQty') as HTMLInputElement).value = '30';
    failing.$('#poForm')!.dispatchEvent(new failing.window.Event('submit', { bubbles: true, cancelable: true }));
    await failing.quiet('the refused purchase order');
    // A tick over a failed write is how somebody believes a shipment is on its
    // way when nothing was ordered.
    expect(failing.text('#poMsg')).toMatch(/Не удалось|уже нет/);
    expect(failing.$('#poMsg')!.className).toContain('bad');
  });
});

describe('«Поставщики» — кадр 07g', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('has a card, inside the Склад view, that the sidebar can reach', () => {
    const card = page.$('#stockSuppliersCard');
    expect(card, 'no «Поставщики» card').not.toBeNull();
    expect(card!.closest('#stock')).not.toBeNull();
    expect(
      page.$('.nav.sub[data-view="stock"][data-anchor="stockSuppliersCard"]'),
      'the card exists and nothing navigates to it',
    ).not.toBeNull();
  });

  it('lists them with their contact and their DECLARED term', () => {
    const t = page.text('#supplierBody');
    expect(t).toContain('Shenzhen Watch Co');
    expect(t).toContain('+86 755 000 00 00');
    expect(t).toContain('21 дн. (со слов поставщика)');
  });

  it('falls back for a supplier who declared nothing, and says it is the fallback', () => {
    // Nothing in this database has a placed→received pair, so a measured lead
    // time cannot exist. Printing 14 as though the supplier promised it would
    // be a number a buyer plans money against.
    expect(page.text('#supplierBody')).toContain('14 дн. (общий срок склада)');
  });

  it('states under the table why the term is not ours', () => {
    expect(page.text('#supplierNote')).toMatch(/разместили → приняли/);
  });

  it('adds one, and reports the result rather than the send', async () => {
    (page.$('#supName') as HTMLInputElement).value = 'Новый поставщик';
    (page.$('#supLead') as HTMLInputElement).value = '30';
    page.$('#supplierForm')!.dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await page.quiet('the new supplier');

    const post = page.sent.find((s) => s.path.endsWith('/admin/suppliers') && s.method === 'POST');
    expect(post, 'the supplier form sent nothing').toBeTruthy();
    expect(JSON.parse(post!.body!).leadTimeDays).toBe(30);
    expect(page.text('#supplierMsg')).toContain('✓');
  });

  it('sends null, not zero, when no term was declared', async () => {
    // Zero days of delivery is a promise nobody made.
    (page.$('#supName') as HTMLInputElement).value = 'Без срока';
    page.$('#supplierForm')!.dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await page.quiet('the new supplier');
    const post = page.sent.find((s) => s.path.endsWith('/admin/suppliers') && s.method === 'POST');
    expect(JSON.parse(post!.body!).leadTimeDays).toBeNull();
  });

  it('says so when the supplier could not be saved', async () => {
    const failing = await render({ failWrites: true, failStatus: 500 });
    (failing.$('#supName') as HTMLInputElement).value = 'Новый поставщик';
    failing.$('#supplierForm')!.dispatchEvent(new failing.window.Event('submit', { bubbles: true, cancelable: true }));
    await failing.quiet('the refused supplier');
    expect(failing.text('#supplierMsg')).toContain('Не удалось');
    expect(failing.$('#supplierMsg')!.className).toContain('bad');
  });

  it('names the taken name when the server refuses it, rather than «не удалось»', async () => {
    // `lower(name)` is UNIQUE. A generic failure here sends the operator
    // looking for a broken server instead of typing a different name.
    const failing = await render({ failWrites: true, failStatus: 409 });
    (failing.$('#supName') as HTMLInputElement).value = 'Shenzhen Watch Co';
    failing.$('#supplierForm')!.dispatchEvent(new failing.window.Event('submit', { bubbles: true, cancelable: true }));
    await failing.quiet('the refused supplier');
    const msg = failing.text('#supplierMsg');
    expect(msg).toContain('Shenzhen Watch Co');
    expect(msg).toMatch(/уже есть в списке/);
    expect(failing.$('#supplierMsg')!.className).toContain('bad');
  });
});

describe('отмена заказа спрашивает', () => {
  it('asks before cancelling, and names what changes', async () => {
    const page = await render();
    (page.$('#supplyBody .pocancel') as HTMLButtonElement).click();
    await page.quiet('the cancel prompt');

    expect(page.confirms.join(' '), 'a purchase order was cancelled without asking').toContain('Отменить заказ');
    // The consequence, not just the act: cancelling puts «пора заказывать»
    // back on the shelf, which is the thing the person needs to know.
    expect(page.confirms.join(' ')).toContain('пора заказывать');
  });

  it('cancels nothing when the answer is no', async () => {
    const page = await render({ confirmAnswer: false });
    (page.$('#supplyBody .pocancel') as HTMLButtonElement).click();
    await page.quiet('the declined cancel');
    // The handler ran and reached the question: without this, «nothing was
    // sent» would also pass for a button wired to nothing at all.
    expect(page.confirms.join(' '), 'the cancel button asked nothing').toContain('Отменить заказ');
    expect(page.sent.filter((s) => s.path.includes('/cancel'))).toEqual([]);
  });

  it('sends the cancel when the answer is yes, and says it happened', async () => {
    const page = await render();
    (page.$('#supplyBody .pocancel') as HTMLButtonElement).click();
    await page.quiet('the cancel');
    expect(page.sent.some((s) => s.path.includes('/cancel') && s.method === 'POST')).toBe(true);
  });

  it('says so when the cancel failed', async () => {
    const page = await render({ failWrites: true });
    (page.$('#supplyBody .pocancel') as HTMLButtonElement).click();
    await page.quiet('the refused cancel');
    expect(page.text('#supplyMsg')).toContain('Не удалось');
  });
});

describe('приёмка по заказу', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('offers the open orders, with «без заказа» first', () => {
    const sel = page.$('#recvPo') as HTMLSelectElement;
    expect(sel, 'the receipt form cannot name an order').not.toBeNull();
    // «Приход без заказа» is a real event and must stay the easy one.
    expect(sel.options[0].value).toBe('');
    expect(sel.options[0].textContent).toContain('без заказа');
    expect([...sel.options].map((o) => o.textContent).join(' ')).toContain('aa11bb22');
  });

  it('measures the shortfall against the ORDER once one is chosen', async () => {
    const sel = page.$('#recvPo') as HTMLSelectElement;
    sel.value = 'aa11bb22-cccc-dddd-eeee-ffff00001111';
    sel.dispatchEvent(new page.window.Event('change', { bubbles: true }));
    const qty = page.$('#recvQty') as HTMLInputElement;
    qty.value = '18';
    qty.dispatchEvent(new page.window.Event('input', { bubbles: true }));
    await page.quiet('the shortfall note');

    // What we are owed is what we ORDERED. A supplier who bills accurately for
    // a short shipment still owes the units missing from it.
    expect(page.text('#recvCheck')).toContain('недостача 2 шт. против заказа (20)');
  });

  it('sends the order id with the receipt', async () => {
    const sel = page.$('#recvPo') as HTMLSelectElement;
    sel.value = 'aa11bb22-cccc-dddd-eeee-ffff00001111';
    (page.$('#recvQty') as HTMLInputElement).value = '18';
    page.$('#recvForm')!.dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await page.quiet('the receipt');

    const post = page.sent.find((s) => s.path.includes('/admin/inventory/receipt'));
    expect(post).toBeTruthy();
    expect(JSON.parse(post!.body!).poId).toBe('aa11bb22-cccc-dddd-eeee-ffff00001111');
  });

  it('compares a second box with what the line still OWES, not the whole order', async () => {
    // Twelve of the twenty already arrived. The eight in this box settle the
    // line: the screen must say so, not warn about a shortfall of twelve
    // against units already on our own shelf.
    const part = await render({ orders: PART_RECEIVED });
    const sel = part.$('#recvPo') as HTMLSelectElement;
    sel.value = 'aa11bb22-cccc-dddd-eeee-ffff00001111';
    sel.dispatchEvent(new part.window.Event('change', { bubbles: true }));
    (part.$('#recvVariant') as HTMLSelectElement).value = 'v1';
    const qty = part.$('#recvQty') as HTMLInputElement;
    qty.value = '8';
    qty.dispatchEvent(new part.window.Event('input', { bubbles: true }));
    await part.quiet('the shortfall note');

    const note = part.text('#recvCheck');
    expect(note, 'the box that completes the order was reported as short').not.toContain('недостача');
    expect(note).toContain('на склад встанет 8 шт.');

    // …and a genuinely short second box is measured against the remainder,
    // with both numbers on screen so nobody reads it as a claim for the lot.
    qty.value = '5';
    qty.dispatchEvent(new part.window.Event('input', { bubbles: true }));
    await part.quiet('the shortfall note');
    expect(part.text('#recvCheck')).toContain('недостача 3 шт. против остатка заказа (8 из 20, принято 12)');
  });

  it('leaves the receipt unchanged when no order is chosen', async () => {
    (page.$('#recvQty') as HTMLInputElement).value = '18';
    page.$('#recvForm')!.dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
    await page.quiet('the receipt');

    const post = page.sent.find((s) => s.path.includes('/admin/inventory/receipt'));
    expect(JSON.parse(post!.body!).poId).toBeUndefined();
  });
});

/**
 * Load as an INPUT, not as a hope.
 *
 * SLOW_MS is derived, not guessed, and the derivation is the point. The first
 * attempt copied the reference file's 40 ms and was DECORATION: with the old
 * fixed waits reinstated the sabotaged run still passed, because two chained
 * requests at 40 ms land comfortably inside a 300 ms window on an idle runner.
 *
 * The rule instead: SLOW_MS is larger than the longest fixed wait these files
 * ever contained (300 ms). At that latency a SINGLE request cannot land inside
 * the old window, so any reinstated sleep truncates the screen and this test
 * fails with an empty card — which is exactly the half-drawn state the whole
 * exercise is about.
 *
 * One latency is still a sample. The property that holds for every latency is
 * that quiet() THROWS rather than returning early; this test is the evidence
 * that the throw is reachable and that nothing downstream reads a partial page.
 */
const SLOW_MS = 320;
/**
 * Load as an INPUT, not as a hope.
 *
 * The property sixteen sleeps could not have. This screen is the worst case for
 * it — the shelf table, the in-transit table, the supplier table and both order
 * pickers are filled from five separate requests — so the cards were the first
 * thing a closing window truncated, one at a time, differently each run.
 *
 * Boot the same screen twice, once with every request answering forty times
 * slower, and require every card and every option list to come out identical.
 * With a fixed wait in place the slow run draws «…» in half of them.
 */
describe('the verdict does not depend on how fast the machine is', () => {
  it('draws the same warehouse whether the server answers in one turn or slowly', async () => {
    const fast = await render();
    const slow = await render({ latencyMs: SLOW_MS });

    const CARDS = ['#supplyBody', '#supplyNote', '#stockBody', '#stockLowList', '#supplierBody', '#supplierNote'];
    for (const sel of CARDS) {
      expect(slow.text(sel), `«${sel}» was drawn differently when the server was slower`)
        .toBe(fast.text(sel));
    }
    const options = (p: Page, sel: string) =>
      [...(p.$(sel) as HTMLSelectElement).options].map((o) => `${o.value}=${o.textContent}`).join('|');
    for (const sel of ['#poVariant', '#poSupplier', '#recvPo']) {
      expect(options(slow, sel), `«${sel}» was filled differently when the server was slower`)
        .toBe(options(fast, sel));
    }

    // Non-vacuity: six empty cards and three empty pickers must not be what
    // matched. Each of these comes from a DIFFERENT request, so this also
    // proves the slow run waited for all five and not merely the first.
    expect(fast.text('#supplyBody')).toContain('Shenzhen Watch Co');   // purchase orders
    expect(fast.text('#stockBody')).toContain('Часы Ana-Bala');        // inventory
    expect(fast.text('#supplierBody')).toContain('Местный склад');     // suppliers
    expect(options(fast, '#recvPo')).toContain('aa11bb22');
    expect(options(fast, '#poVariant')).toContain('Ремешок');
  });
});
