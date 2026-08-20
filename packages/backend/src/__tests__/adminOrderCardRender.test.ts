/**
 * Кадр 02 «Заказы» and кадр 03 «Карточка заказа», drawn by a browser.
 *
 * The panel is one HTML file executed top to bottom, so "the markup contains
 * the right ids" proves nothing: a slip in an earlier block kills every later
 * one and the file still greps clean. Everything here is asserted against what
 * jsdom actually rendered after running the page's own JavaScript.
 *
 * The defect this covers: clicking an order did nothing. There was no card, so
 * the finished, audited GET /admin/shop/orders/:id/devices had no caller and a
 * packer could not see which serials were already on an order — every re-bind
 * was blind.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const ORDER_ID = '11111111-2222-3333-4444-555555555555';

/** One page of кадр 02 — three rows, and counters over the whole table. */
const PAGE = {
  orders: [
    {
      id: ORDER_ID, customerName: 'Мадина', phone: '+7 701 000 00 00', city: 'Астана',
      address: 'ул. Абая 1', note: null, status: 'new', totalMinor: 3900000, discountMinor: 800000,
      createdAt: '2026-08-01T10:00:00Z',
      // variantId travels with the line so frame 05a can name what it puts
      // back on the shelf; a line without one is the old-backend case, tested
      // separately below.
      items: [{ productName: 'Часы', color: 'Чёрный', qty: 1, unitPriceMinor: 3900000, variantId: 'v-w-black' }],
    },
    {
      id: 'aaaaaaaa-2222-3333-4444-555555555555', customerName: 'Айгерім', phone: '+7 707 345 22 44',
      city: 'Алматы', address: 'ул. Сейфуллина 2', note: null, status: 'shipped',
      totalMinor: 1990000, discountMinor: 0, createdAt: '2026-08-02T10:00:00Z',
      items: [{ productName: 'Брелок', color: 'Розовый', qty: 1, unitPriceMinor: 1990000 }],
    },
  ],
  total: 284,
  offset: 0,
  limit: 25,
  status: null,
  counts: { new: 14, confirmed: 3, shipped: 260, delivered: 5, cancelled: 2 },
};

const CARD = {
  order: PAGE.orders[0],
  ref: ORDER_ID.slice(0, 8),
  timeline: [
    { at: '2026-08-01T10:00:00Z', kind: 'created', status: 'new', from: null, by: null },
    { at: '2026-08-02T09:30:00Z', kind: 'status', status: 'confirmed', from: 'new', by: 'Нуржан' },
  ],
  historyGap: false,
  whatsapp: 'https://wa.me/77010000000?text=hello',
  // [] and null are different answers: none were booked, versus the read
  // failed. The card must not draw the second as the first.
  refunds: [],
  payment: {
    totalMinor: 3900000, discountMinor: 800000, recorded: false,
    refundedMinor: 0, refundableMinor: 3900000,
    note: 'Оплата при получении. Способ и факт оплаты в базе не хранятся.',
  },
};

const DEVICES = {
  devices: [
    {
      serial: 'AABBCCDDEE01', status: 'sold', kind: 'band', activationCode: null,
      orderId: ORDER_ID, receivedAt: '2026-07-20T10:00:00Z',
      activatedByPhone: '77010000000', activatedAt: null, note: null,
    },
  ],
};

interface Sent { path: string; method: string; body: unknown }

interface Opts {
  /** GET /admin/shop/orders/:id/devices answers 403. */
  devicesForbidden?: boolean;
  /** Every non-GET fails. */
  failWrites?: boolean;
  /** A specific refusal, so the named 409s can be told apart on screen. */
  writeStatus?: number;
  writeBody?: unknown;
  /** What GET /admin/shop/orders/:id says about refunds. */
  cardRefunds?: unknown;
  cardPayment?: Record<string, unknown>;
  /** What confirm() returns. */
  confirmAnswer?: boolean;
  /** Serve the list WITHOUT total/counts, as an older backend would. */
  oldBackend?: boolean;
  /** The role the session reports. */
  role?: string;
}

/**
 * The completion signal for every window this file boots.
 *
 * Four fixed sleeps stood here — 200 after boot, 350 after the tab, 300 per
 * click, 250 after a status change — each deciding its verdict on elapsed
 * wall-clock rather than on the work being finished. The order card is filled
 * by a request that chains off the row click, and the device list by another
 * that chains off THAT, so a window closing early left an empty card and
 * «the card never drew» read as a bug in the panel.
 *
 * Kept in a WeakMap so click() needs no extra argument and every call site
 * stays as it was: the thing that changed is what the waiting means, not how
 * the tests are written. See helpers/panelSettle.ts.
 */
const settled = new WeakMap<JSDOM['window'], (label?: string) => Promise<void>>();

const quietOf = (window: JSDOM['window']) => {
  const q = settled.get(window);
  if (!q) throw new Error('this window was not booted by openShop()');
  return q;
};

async function openShop(opts: Opts = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const alerts: string[] = [];
  const confirms: string[] = [];
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
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = (m) => alerts.push(m);
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return opts.confirmAnswer ?? true;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, text: async () => '', json: async () => ({ staffId: 's1', role: opts.role ?? 'admin', displayName: 'Нуржан' }) };
        }
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
          if (opts.writeStatus) {
            return {
              ok: opts.writeStatus < 400, status: opts.writeStatus,
              text: async () => '', json: async () => opts.writeBody ?? {},
            };
          }
          if (opts.failWrites) return { ok: false, status: 500, text: async () => '', json: async () => ({}) };
          return { ok: true, status: 200, text: async () => '', json: async () => ({ ok: true, linked: ['AABBCCDDEE02'], unknown: [] }) };
        }
        sent.push({ path: p, method, body: null });

        if (/\/admin\/shop\/orders\/[^/]+\/devices/.test(p)) {
          if (opts.devicesForbidden) return { ok: false, status: 403, text: async () => '', json: async () => ({ error: 'forbidden', need: 'stock' }) };
          return { ok: true, status: 200, text: async () => '', json: async () => DEVICES };
        }
        const one = p.match(/\/admin\/shop\/orders\/([^/?]+)$/);
        if (one) {
          // The card that comes back must describe the order that was ASKED
          // for: a fixture that always answers "new" would hide every rule
          // that depends on where the order already is.
          const order = PAGE.orders.find((o) => o.id === one[1]) ?? PAGE.orders[0];
          return {
            ok: true, status: 200, text: async () => '',
            json: async () => ({
              ...CARD, order, ref: order.id.slice(0, 8),
              refunds: 'cardRefunds' in opts ? opts.cardRefunds : CARD.refunds,
              payment: { ...CARD.payment, ...(opts.cardPayment ?? {}) },
            }),
          };
        }
        const body = p.includes('/admin/shop/orders')
          ? (opts.oldBackend ? { orders: PAGE.orders } : PAGE)
          : p.includes('/admin/shop/leads')
            ? { leads: [] }
            : p.includes('/admin/shop/variants')
              ? { variants: [] }
              : p.includes('/admin/settings')
                ? { settings: {} }
                : p.includes('/admin/stats')
                  ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
                  : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      });
    },
  });

  const { window } = dom;
  settled.set(window, settle.quiet);
  await settle.quiet('boot');
  window.document.querySelector('[data-view="shop"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Магазин tab');
  return { window, sent, errors, alerts, confirms, quiet: settle.quiet };
}

/** Click a rendered element and let its handler finish — actually finish. */
async function click(window: JSDOM['window'], el: Element | null) {
  expect(el, 'nothing to click').not.toBeNull();
  el!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await quietOf(window)('the click');
}

describe('кадр 02 — the list an operator works from', () => {
  it('draws filter chips carrying the count of each status', async () => {
    const { window, errors } = await openShop();
    expect(errors, errors.join('\n')).toEqual([]);

    const chips = window.document.getElementById('orderChips')!;
    const labels = [...chips.querySelectorAll('.fchip')].map((c) => c.textContent ?? '');
    expect(labels.length, 'no status chips were drawn').toBeGreaterThan(4);
    // «Новые» on its own tells an operator nothing; the number is the control.
    expect(labels.join(' ')).toContain('Новый');
    expect(labels.join(' ').replace(/[   ]/g, ' ')).toContain('14');
    expect(labels[0]).toContain('Все');
  });

  it('states «Показано N из M» and the rule the list obeys', async () => {
    const { window } = await openShop();
    const foot = window.document.getElementById('ordersFoot')!.textContent ?? '';
    expect(foot.replace(/[   ]/g, ' ')).toContain('Показано 1–2 из 284');
    // Every table footer states its rule (spec 3.4). This one is the reason a
    // cancelled order is still on the screen.
    expect(foot).toMatch(/не удаляются/i);
  });

  it('pages forward, asking the server for the next offset', async () => {
    const { window, sent } = await openShop();
    await click(window, window.document.getElementById('ordersNext'));
    const asked = sent.filter((s) => s.path.includes('offset=25'));
    expect(asked.length, 'Вперёд did not ask for the next page').toBeGreaterThan(0);
    // «Назад» is disabled on the first page rather than paging into nothing.
    const { window: fresh } = await openShop();
    expect((fresh.document.getElementById('ordersPrev') as HTMLButtonElement).disabled).toBe(true);
  });

  it('filtering by a chip asks for that status and resets the offset', async () => {
    const { window, sent } = await openShop();
    const chip = [...window.document.querySelectorAll('#orderChips .fchip')]
      .find((c) => (c as HTMLElement).dataset.ostatus === 'shipped')!;
    await click(window, chip);
    const asked = sent.filter((s) => s.path.includes('status=shipped'));
    expect(asked.length, 'the chip filtered nothing').toBeGreaterThan(0);
    expect(asked[asked.length - 1].path).toContain('offset=0');
  });

  it('says the counters are missing rather than printing zeroes', async () => {
    // A backend one deploy behind answers 200 without total/counts. «Показано
    // 0 из 0» over a full list is a lie the operator cannot spot.
    const { window } = await openShop({ oldBackend: true });
    const chips = window.document.getElementById('orderChips')!.textContent ?? '';
    const foot = window.document.getElementById('ordersFoot')!.textContent ?? '';
    expect(chips).toMatch(/счётчики не пришли/i);
    expect(foot).not.toContain('из 0');
    expect(foot).toMatch(/сервер не сказал/i);
  });
});

describe('кадр 03 — clicking an order opens its card', () => {
  it('opens the card and fills it from the order route', async () => {
    const { window, sent, errors } = await openShop();
    expect(errors, errors.join('\n')).toEqual([]);

    const card = window.document.getElementById('orderCard')!;
    expect(card.hasAttribute('hidden'), 'the card was open before anything was clicked').toBe(true);

    await click(window, window.document.querySelector('tr[data-order]'));

    expect(card.hasAttribute('hidden'), 'clicking an order still does nothing').toBe(false);
    expect(sent.some((s) => s.method === 'GET' && s.path.endsWith(`/admin/shop/orders/${ORDER_ID}`)))
      .toBe(true);

    expect(window.document.getElementById('ocTitle')!.textContent).toContain(ORDER_ID.slice(0, 8));
    // Composition, per line.
    expect(window.document.getElementById('ocItems')!.textContent).toContain('Часы');
    // Customer and delivery.
    expect(window.document.getElementById('ocCustomer')!.textContent).toContain('Мадина');
    expect(window.document.getElementById('ocDelivery')!.textContent).toContain('ул. Абая 1');
  });

  it('calls the devices route and shows the serials already on the order', async () => {
    // The route existed, was audited and had no caller. Without this a packer
    // binds serials blind.
    const { window, sent } = await openShop();
    await click(window, window.document.querySelector('tr[data-order]'));

    expect(
      sent.some((s) => s.method === 'GET' && s.path.includes(`/admin/shop/orders/${ORDER_ID}/devices`)),
      'the card never asked which devices are on this order',
    ).toBe(true);
    const devices = window.document.getElementById('ocDevices')!.textContent ?? '';
    expect(devices).toContain('AABBCCDDEE01');
  });

  it('says the serials are unknown when that request is refused, and does not pretend', async () => {
    const { window } = await openShop({ devicesForbidden: true });
    await click(window, window.document.querySelector('tr[data-order]'));
    const devices = window.document.getElementById('ocDevices')!.textContent ?? '';
    expect(devices).toMatch(/закрыт|неизвестно/i);
    expect(devices).not.toContain('AABBCCDDEE01');
  });

  it('draws the history with who moved the status', async () => {
    const { window } = await openShop();
    await click(window, window.document.querySelector('tr[data-order]'));
    const tl = window.document.getElementById('ocTimeline')!.textContent ?? '';
    expect(tl).toContain('Заказ создан');
    expect(tl).toContain('Подтверждён');
    expect(tl, 'the timeline dropped the person who did it').toContain('Нуржан');
  });

  it('prints what the schema cannot answer about payment', async () => {
    const { window } = await openShop();
    await click(window, window.document.querySelector('tr[data-order]'));
    const pay = window.document.getElementById('ocPayment')!.textContent ?? '';
    // The sum it CAN stand behind…
    expect(pay.replace(/[   ]/g, ' ')).toContain('39 000');
    // …and the absence, in words, because a blank field reads as «не оплачено».
    expect(pay).toMatch(/не хранятся/i);
  });

  it('offers the WhatsApp link the server built, not one it invented', async () => {
    const { window } = await openShop();
    await click(window, window.document.querySelector('tr[data-order]'));
    const wa = window.document.getElementById('ocWa') as HTMLAnchorElement;
    expect(wa.hidden).toBe(false);
    expect(wa.getAttribute('href')).toBe(CARD.whatsapp);
  });
});

describe('the card’s dangerous actions ask first, and report the answer', () => {
  it('names the customer and the money before cancelling', async () => {
    const { window, sent, confirms } = await openShop({ confirmAnswer: false });
    await click(window, window.document.querySelector('tr[data-order]'));
    await click(window, window.document.getElementById('ocCancel'));

    expect(confirms.length, 'the order was cancelled without asking').toBe(1);
    expect(confirms[0]).toContain('Мадина');
    expect(confirms[0].replace(/[   ]/g, ' ')).toContain('39 000');
    // And what it costs, not just that it is irreversible.
    expect(confirms[0]).toMatch(/склад/i);
    expect(sent.filter((s) => s.method === 'PATCH'), 'a declined cancellation still reached the server')
      .toEqual([]);
  });

  it('cancels when confirmed', async () => {
    const { window, sent } = await openShop({ confirmAnswer: true });
    await click(window, window.document.querySelector('tr[data-order]'));
    await click(window, window.document.getElementById('ocCancel'));

    const patch = sent.find((s) => s.method === 'PATCH');
    expect(patch, 'confirming cancelled nothing').toBeTruthy();
    expect(patch!.path).toContain(ORDER_ID);
    expect(patch!.body).toEqual({ status: 'cancelled' });
  });

  it('says the order is NOT cancelled when the write fails', async () => {
    // A tick over a failed write is how somebody believes a sale is closed
    // when it is still in the shipping queue.
    const { window, sent } = await openShop({ confirmAnswer: true, failWrites: true });
    await click(window, window.document.querySelector('tr[data-order]'));
    await click(window, window.document.getElementById('ocCancel'));

    expect(sent.some((s) => s.method === 'PATCH'), 'it did try').toBe(true);
    const err = window.document.getElementById('ocError')!;
    expect(err.hasAttribute('hidden'), 'a failed cancellation said nothing').toBe(false);
    expect(err.textContent).toMatch(/не отмен/i);
  });

  it('warns that rolling a shipped order back does not take the course away', async () => {
    // The quiet one: the entitlement granted on dispatch is never revoked, so
    // an order rolled back leaves a paid-for course nobody remembers giving.
    const { window, confirms, sent } = await openShop({ confirmAnswer: false });
    await click(window, window.document.querySelectorAll('tr[data-order]')[1]);

    const sel = window.document.getElementById('ocStatus') as HTMLSelectElement;
    // The card's own control never offers «Отменён» — cancelling is a
    // dangerous action with its own button, and one screen must not carry two
    // ways to do the same irreversible thing.
    expect([...sel.options].map((o) => o.value)).not.toContain('cancelled');

    sel.value = 'new';
    sel.dispatchEvent(new window.Event('change', { bubbles: true }));
    await quietOf(window)('the status change');

    expect(confirms.length, 'rolling an order back asked nothing').toBe(1);
    expect(confirms[0]).toMatch(/Ма!Ма!/);
    expect(sent.filter((s) => s.method === 'PATCH')).toEqual([]);
    expect(sel.value, 'the dropdown kept a value the operator backed out of').toBe('shipped');
  });
});

/**
 * КАДР 05a — «Оформить возврат», drawn and driven.
 *
 * The write side of «Возвраты и брак». Before it existed, an operator holding a
 * returned комплект had two options: write the unit off — destroying stock and
 * inflating «Списано на сумму» — or record nothing at all, leaving refunded
 * money in «Заработано» for ever.
 */
describe('кадр 05a — оформление возврата', () => {
  /** Open the card, then the refund form. */
  const openRefund = async (opts: Opts = {}) => {
    const shop = await openShop(opts);
    await click(shop.window, shop.window.document.querySelector('tr[data-order]'));
    await click(shop.window, shop.window.document.getElementById('ocRefund'));
    return shop;
  };

  it('offers the action in the danger block, and it opens a form', async () => {
    const { window, errors } = await openShop();
    expect(errors, errors.join('\n')).toEqual([]);
    await click(window, window.document.querySelector('tr[data-order]'));

    const btn = window.document.getElementById('ocRefund');
    expect(btn, 'there is no way to record a return at all').toBeTruthy();
    const modal = window.document.getElementById('refundModal')!;
    expect(modal.hasAttribute('hidden')).toBe(true);

    await click(window, btn);
    expect(modal.hasAttribute('hidden'), 'the button opened nothing').toBe(false);
    expect(window.document.getElementById('rfTitle')!.textContent).toContain(ORDER_ID.slice(0, 8));
  });

  it('offers no more than the server will accept', async () => {
    const { window } = await openRefund({
      cardRefunds: [{
        id: 1, orderId: ORDER_ID, amountMinor: 900000, reason: 'defect', note: null,
        staffId: 's1', staffName: 'Нуржан', restockedUnits: 1, at: '2026-08-03T10:00:00Z',
      }],
      cardPayment: { refundedMinor: 900000, refundableMinor: 3000000 },
    });
    const amount = window.document.getElementById('rfAmount') as HTMLInputElement;
    // The limit the form offers and the limit the repository refuses on are one
    // rule, sent once — otherwise the operator meets a 409 the screen said
    // could not happen.
    expect(amount.value).toBe('30000');
    expect((window.document.getElementById('rfLimit')!.textContent ?? '').replace(/\s+/g, ' '))
      .toContain('9 000');
  });

  it('states the four things a refund does NOT do', async () => {
    const { window } = await openRefund();
    const facts = window.document.getElementById('rfFacts')!.textContent ?? '';
    // The device registry has no «возвращён» state (routes/inventory.ts).
    expect(facts).toContain('Активировано');
    // Entitlement is revoked only by a person, never by this.
    expect(facts).toMatch(/НЕ отзывается/);
    expect(facts).toContain('Ма!Ма!');
    // The destination of the money is not stored, and must not be implied.
    expect(facts).toMatch(/Kaspi/);
    // And the reasons only exist from the day this shipped.
    expect(facts).toContain('20.08.2026');
    expect(facts).toMatch(/задним числом/);
    // The link is offered rather than the course being silently taken away.
    expect(window.document.getElementById('rfCourseLink')).toBeTruthy();
  });

  it('asks before it sends, naming the person and the money', async () => {
    const { window, sent, confirms } = await openRefund({ confirmAnswer: false });
    const amount = window.document.getElementById('rfAmount') as HTMLInputElement;
    amount.value = '12000';
    await click(window, window.document.getElementById('rfSubmit'));

    expect(confirms.length, 'money was returned without asking').toBe(1);
    expect(confirms[0]).toContain('Мадина');
    expect(confirms[0].replace(/\s+/g, ' ')).toContain('12 000');
    expect(confirms[0], 'the question hid that the course stays').toMatch(/Ма!Ма!/);
    expect(sent.filter((s) => s.method === 'POST' && s.path.includes('/refund')),
      'a declined refund still reached the server').toEqual([]);
  });

  it('sends the amount, the reason and the restocked lines when confirmed', async () => {
    const { window, sent } = await openRefund({ confirmAnswer: true });
    (window.document.getElementById('rfAmount') as HTMLInputElement).value = '39000';
    (window.document.getElementById('rfReason') as HTMLSelectElement).value = 'not_suitable';
    (window.document.getElementById('rfNote') as HTMLInputElement).value = 'мала по размеру';
    const qty = window.document.querySelector('#rfLines .rfqty') as HTMLInputElement;
    expect(qty, 'the form offered no way to put the unit back on the shelf').toBeTruthy();
    qty.value = '1';

    await click(window, window.document.getElementById('rfSubmit'));

    const post = sent.find((s) => s.method === 'POST' && s.path.includes('/refund'));
    expect(post, 'confirming refunded nothing').toBeTruthy();
    expect(post!.path).toContain(ORDER_ID);
    expect(post!.body).toEqual({
      amountMinor: 3900000, reason: 'not_suitable', note: 'мала по размеру',
      restock: [{ variantId: 'v-w-black', qty: 1 }],
    });
  });

  it('reports the result of the request, not the fact that one was sent', async () => {
    const { window, sent } = await openRefund({ confirmAnswer: true, failWrites: true });
    (window.document.getElementById('rfAmount') as HTMLInputElement).value = '1000';
    await click(window, window.document.getElementById('rfSubmit'));

    expect(sent.some((s) => s.path.includes('/refund')), 'it did try').toBe(true);
    const err = window.document.getElementById('rfError')!;
    expect(err.hasAttribute('hidden'), 'a failed refund said nothing').toBe(false);
    expect(err.textContent).toMatch(/НЕ оформлен/);
    // And the form stays open with the numbers in it, so the operator can retry.
    expect(window.document.getElementById('refundModal')!.hasAttribute('hidden')).toBe(false);
  });

  it('says WHICH refusal it was — «столько вернуть нельзя» is not a server fault', async () => {
    const { window } = await openRefund({
      confirmAnswer: true, writeStatus: 409, writeBody: { error: 'refund_exceeds_order' },
    });
    (window.document.getElementById('rfAmount') as HTMLInputElement).value = '39000';
    await click(window, window.document.getElementById('rfSubmit'));

    const err = window.document.getElementById('rfError')!.textContent ?? '';
    expect(err).toMatch(/больше суммы заказа/);
    expect(err, 'a refusal was reported as a breakage').not.toMatch(/сервер не принял запись/);
    expect(err).toMatch(/ничего не записано/i);
  });

  it('says so plainly when it worked', async () => {
    // The operator has already handed the money over by the time they get here;
    // «ничего не произошло» must never be a state they have to guess at.
    const { window } = await openRefund({ confirmAnswer: true });
    (window.document.getElementById('rfAmount') as HTMLInputElement).value = '39000';
    await click(window, window.document.getElementById('rfSubmit'));

    expect(window.document.getElementById('refundModal')!.hasAttribute('hidden')).toBe(true);
    const said = window.document.getElementById('ocError')!;
    expect(said.hasAttribute('hidden')).toBe(false);
    expect(said.textContent).toMatch(/Возврат оформлен/);
  });

  it('lists the refunds already booked against the order', async () => {
    const { window } = await openShop({
      cardRefunds: [{
        id: 1, orderId: ORDER_ID, amountMinor: 900000, reason: 'defect', note: 'не заряжается',
        staffId: 's1', staffName: 'Нуржан', restockedUnits: 1, at: '2026-08-03T10:00:00Z',
      }],
      cardPayment: { refundedMinor: 900000, refundableMinor: 3000000 },
    });
    await click(window, window.document.querySelector('tr[data-order]'));
    const box = window.document.getElementById('ocRefunds')!.textContent ?? '';
    expect(box).toContain('брак');
    expect(box).toContain('не заряжается');
    expect(box).toContain('Нуржан');
    expect(box.replace(/\s+/g, ' ')).toContain('9 000 ₸');
    // And it does not imply the money's destination was recorded.
    expect(box).toMatch(/не хранится/);
  });

  it('says «не прочиталось» rather than «возвратов нет» when the read failed', async () => {
    // [] and null are opposite answers. Drawing the second as the first is how
    // the same order gets refunded twice.
    const { window } = await openShop({
      cardRefunds: null, cardPayment: { refundedMinor: null, refundableMinor: null },
    });
    await click(window, window.document.querySelector('tr[data-order]'));
    const box = window.document.getElementById('ocRefunds')!.textContent ?? '';
    expect(box).toMatch(/не прочитались/);
    expect(box).not.toMatch(/возвратов не оформляли/);

    // And the form refuses to guess a limit rather than offering the full total.
    await click(window, window.document.getElementById('ocRefund'));
    expect((window.document.getElementById('rfSubmit') as HTMLButtonElement).disabled).toBe(true);
    expect(window.document.getElementById('rfLimit')!.textContent).toMatch(/неизвестно/);
  });

  it('will not restock a line whose variant the server did not send', async () => {
    // An older backend answers without variantId. Putting a unit back on the
    // shelf by guessing which colour it was is how the ledger starts lying.
    // The second row in the fixture is exactly that: a line with no variantId.
    const { window } = await openShop();
    await click(window, window.document.querySelectorAll('tr[data-order]')[1]);
    await click(window, window.document.getElementById('ocRefund'));
    const lines = window.document.getElementById('rfLines')!;
    expect(lines.querySelector('.rfqty'), 'it offered to restock a line it cannot name').toBeNull();
    expect(lines.textContent).toMatch(/сервер не сказал/);
  });
});

describe('a role without warehouse access', () => {
  it('is told why the serials are not shown, instead of a silent empty block', async () => {
    // An operator has `orders` and not `stock`. The card is still hers; the
    // serials are not, and «пусто» would read as "nothing was ever packed".
    const { window, sent } = await openShop({ role: 'operator' });
    await click(window, window.document.querySelector('tr[data-order]'));

    const devices = window.document.getElementById('ocDevices')!.textContent ?? '';
    expect(devices).toMatch(/складск/i);
    // And it does not fire a request it knows will be refused.
    expect(sent.some((s) => s.path.includes('/devices'))).toBe(false);
  });
});
