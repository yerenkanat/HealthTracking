/**
 * The admin panel's write controls: do they save, and do they admit it when
 * they do not?
 *
 * Rendering is not working. adminAllViewsRender proves every tab draws; this
 * proves the controls on them change something. A status dropdown that renders
 * the right options and sends nothing is indistinguishable from a working one
 * until someone asks why a lead is still marked "new".
 *
 * The second half matters more. Both status handlers were written as
 * `try { await apiSend(...) } catch(e) {}` — on a failed save the select keeps
 * showing the value the user just picked, the list is not re-rendered, and
 * nothing anywhere says the change did not stick. Staff would mark a mother as
 * called back, see it stay that way, and move on.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Six fixed sleeps — 150 after boot, 300 after the tab, 200 after each change —
 * decided their verdict on elapsed wall-clock rather than on the work being
 * finished. Four of the assertions here are NEGATIVE ("a declined cancellation
 * still reached the server", "nothing was written"), and a negative read before
 * the request has left passes for the wrong reason on every run.
 *
 * They are all quiet() now: no request in flight, none newly issued for several
 * consecutive turns, no page timer outstanding, and a throw rather than a
 * half-drawn screen. See helpers/panelSettle.ts.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const LEADS = {
  leads: [
    { id: 'lead-1', customerName: 'Айгерім', phone: '+7 707 345 22 44', package: 'Комплект', locale: 'kz', status: 'new', createdAt: '2026-08-01T10:00:00Z' },
  ],
};
const ORDERS = {
  orders: [
    {
      id: 'order-1', customerName: 'Мадина', phone: '+7 701 000 00 00', city: 'Астана',
      address: 'ул. Абая 1', status: 'new', totalMinor: 3900000, discountMinor: 0,
      createdAt: '2026-08-01T10:00:00Z',
      items: [{ productName: 'Часы', color: 'black', qty: 1 }],
    },
  ],
};

interface Sent {
  path: string;
  method: string;
  body: unknown;
}

/** A booted panel that knows when it has finished working. */
interface Shop {
  window: JSDOM['window'];
  quiet: (label?: string) => Promise<void>;
}

async function openShop(opts: { failWrites?: boolean; confirmAnswer?: boolean } = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const alerts: string[] = [];
  // What the operator was asked before a destructive status change, and what
  // they answered. jsdom has no confirm(); leaving it unstubbed makes it
  // return undefined, which is falsy, so every cancellation would silently
  // appear to be refused and the test would pass for the wrong reason.
  const confirms: string[] = [];
  const vc = new VirtualConsole();
  const errors: string[] = [];
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
      // The failure path now tells the operator; jsdom has no alert().
      (window as unknown as { alert: (m: string) => void }).alert = (m) => alerts.push(m);
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return opts.confirmAnswer ?? true;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        // The panel now opens on a sign-in gate and asks who is signed in
        // before it renders anything. These tests are about the dashboard,
        // so they answer as a signed-in admin.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
          if (opts.failWrites) return { ok: false, status: 500, json: async () => ({}) };
          return { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        const body = p.includes('/admin/shop/leads')
          ? LEADS
          : p.includes('/admin/shop/orders')
            ? ORDERS
            : p.includes('/admin/shop/variants')
              ? { variants: [] }
              : p.includes('/admin/settings')
                ? { settings: {} }
                : p.includes('/admin/stats')
                  ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
                  : {};
        return { ok: true, status: 200, json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="shop"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Магазин tab');
  return { window, sent, errors, alerts, confirms, quiet: settle.quiet };
}

/** Pick a new value on a `<select>` and fire the change the browser would. */
async function choose(page: Shop, selector: string, value: string) {
  const sel = page.window.document.querySelector(selector) as HTMLSelectElement;
  expect(sel, `no ${selector} on the page`).not.toBeNull();
  sel.value = value;
  sel.dispatchEvent(new page.window.Event('change', { bubbles: true }));
  await page.quiet(`the change on ${selector}`);
  return sel;
}

describe('settings cannot be wiped by a failed load', () => {
  /** Open Магазин with GET /admin/settings broken. */
  async function openWithBrokenSettings() {
    const html = readFileSync(PANEL, 'utf8');
    const settle = panelSettle();
    const sent: Sent[] = [];
    const vc = new VirtualConsole();
    const dom = new JSDOM(html, {
      runScripts: 'dangerously',
      pretendToBeVisual: true,
      url: 'http://localhost/admin/ui',
      virtualConsole: vc,
      beforeParse(window) {
        window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
          const noop = () => {};
          return new Proxy({ canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
            { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
        }) as never;
        Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
        window.scrollTo = () => {};
        Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
        (window as unknown as { alert: (m: string) => void }).alert = () => {};
        settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
          const p = path;
          const method = init?.method ?? 'GET';
          if (method !== 'GET') {
            sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
            return { ok: true, status: 200, json: async () => ({ ok: true }) };
          }
          // Who is signed in. This branch was missing, so /admin/me answered
          // `{}` and the panel ran with an empty role — which no real session
          // produces, and which now (correctly) hides every capability-guarded
          // card. The fake was lying about the session, not the settings.
          if (p.includes('/admin/me')) {
            return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
          }
          // The one that breaks.
          if (p.includes('/admin/settings')) return { ok: false, status: 503, json: async () => ({}) };
          const body = p.includes('/admin/shop/leads') ? { leads: [] }
            : p.includes('/admin/shop/orders') ? { orders: [] }
            : p.includes('/admin/shop/variants') ? { variants: [] }
            : p.includes('/admin/stats') ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
            : {};
          return { ok: true, status: 200, json: async () => body };
        });
      },
    });
    const { window } = dom;
    await settle.quiet('boot with a broken settings load');
    window.document.querySelector('[data-view="shop"]')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the Магазин tab');
    return { window, sent, quiet: settle.quiet };
  }

  it('refuses to save when it never learned what the server holds', async () => {
    // The path that destroys data: the load fails, every box is left empty —
    // which reads as "nothing is configured" — and one click of Сохранить
    // sends "" for every field. The API stores what it is sent, because an
    // empty string is not undefined, so that single click wipes the Anthropic
    // key, the Telegram token, the WhatsApp number and the reviews.
    const { window, sent, quiet } = await openWithBrokenSettings();

    const save = window.document.getElementById('setSave') as HTMLButtonElement;
    expect(save.disabled, 'the save button should be disabled after a failed load').toBe(true);

    // And if it is clicked anyway, nothing is written.
    save.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the refused save');
    expect(sent.filter((s) => s.path.includes('/admin/settings') && s.method === 'PUT'))
      .toHaveLength(0);

    // Either message is right — the load failure, or the refusal that replaces
    // it once the disabled button is clicked anyway. Both say the same thing:
    // we do not know what is stored, so we will not overwrite it.
    expect(window.document.getElementById('setMsg')!.textContent)
      .toMatch(/не удалось загрузить|не загрузились/i);
  });
});

describe('the shop tab saves what staff change', () => {
  it('marking a lead as called PATCHes it', async () => {
    const page = await openShop();
    const { sent } = page;
    await choose(page, '.lstatus', 'called');

    const write = sent.find((s) => s.path.includes('/admin/shop/leads/'));
    expect(write, 'no request went out — the dropdown changed nothing').toBeTruthy();
    expect(write!.method).toBe('PATCH');
    expect(write!.path).toContain('lead-1');
    expect(write!.body).toEqual({ status: 'called' });
  });

  it('changing an order status PATCHes it', async () => {
    const page = await openShop();
    const { sent } = page;
    await choose(page, '.ostatus', 'shipped');

    const write = sent.find((s) => s.path.includes('/admin/shop/orders/'));
    expect(write, 'no request went out').toBeTruthy();
    expect(write!.method).toBe('PATCH');
    expect(write!.path).toContain('order-1');
    expect(write!.body).toEqual({ status: 'shipped' });
  });

  it('says so when the save fails, instead of showing the new value', async () => {
    // The failure that prompted this test: the handler swallowed the error, so
    // the select kept the value the user picked and the list was never
    // re-rendered. Staff mark a mother as called back, watch it stay that way,
    // and never learn the server still has her as waiting.
    const page = await openShop({ failWrites: true });
    const { sent, alerts } = page;
    const sel = await choose(page, '.lstatus', 'called');

    expect(sent.some((s) => s.method === 'PATCH'), 'it did try').toBe(true);
    expect(sel.value, 'the dropdown must not keep a value the server rejected')
      .toBe('new');
    // Reverting silently is only half a fix: the operator would see the value
    // snap back with no idea whether they mis-clicked or the save failed.
    expect(alerts.join(' '), 'nothing told the operator').toMatch(/не удалось/i);
  });
});

/**
 * Cancelling somebody else's order takes one stray mouse-wheel tick.
 *
 * Hovering a <select> and scrolling changes its value in Chrome and Firefox,
 * and `onchange` fired the PATCH straight away. The order left «Заказы к
 * отгрузке», left the revenue figure and turned up under «Потеряно на
 * отменах» — nobody notified, one audit row the only trace.
 *
 * The app's own cancel path has always asked (confirmDestructive). The staff
 * side, which cancels other people's orders, did not.
 *
 * Only the terminal transitions ask. «Подтверждён» and «Отправлен» are the
 * ordinary movement of a day's work and a prompt on each of those would be
 * trained away within a week — which would take the cancel prompt with it.
 */
describe('a destructive status change asks first', () => {
  it('sends nothing when the operator declines the cancellation', async () => {
    const page = await openShop({ confirmAnswer: false });
    const { sent, confirms } = page;
    const sel = await choose(page, '.ostatus', 'cancelled');

    expect(confirms.length, 'the order was cancelled without asking').toBe(1);
    expect(sent.filter((s) => s.method === 'PATCH'), 'a declined cancellation still reached the server').toEqual([]);
    // Snapped back, so the list does not show an order as cancelled when it is
    // not — the same lie the failed-save path was fixed for.
    expect(sel.value, 'the dropdown kept the value the operator backed out of').toBe('new');
  });

  it('names the customer and the money, so the question is answerable', async () => {
    const page = await openShop({ confirmAnswer: false });
    const { confirms } = page;
    await choose(page, '.ostatus', 'cancelled');

    // «Отменить заказ?» is waved through; «Отменить заказ Мадина · 39 000 ₸?»
    // is read. If this ever regresses to a bare question it is worth nothing.
    expect(confirms[0]).toContain('Мадина');
    expect(confirms[0].replace(/ | /g, ' ')).toContain('39 000');
  });

  it('cancels when the operator confirms', async () => {
    const page = await openShop({ confirmAnswer: true });
    const { sent } = page;
    await choose(page, '.ostatus', 'cancelled');

    const patch = sent.find((s) => s.method === 'PATCH');
    expect(patch, 'confirming did not save').toBeTruthy();
    expect(patch!.body).toEqual({ status: 'cancelled' });
  });

  it('does not ask on the ordinary forward steps of a day', async () => {
    // A prompt on «Подтверждён» would be dismissed reflexively within a week,
    // and that habit is exactly what would carry the operator through the
    // cancel prompt too. Only the irreversible step asks.
    const page = await openShop();
    const { sent, confirms } = page;
    await choose(page, '.ostatus', 'confirmed');

    expect(confirms, 'a routine status change interrupted the operator').toEqual([]);
    expect(sent.find((s) => s.method === 'PATCH')!.body).toEqual({ status: 'confirmed' });
  });

  it('asks before marking a lead as refused, and names her', async () => {
    // The quieter version of the same mis-scroll: the woman who asked for a
    // callback leaves «не обработано» and is never rung. Nothing looks broken
    // afterwards, which is why it needs the ask.
    const page = await openShop({ confirmAnswer: false });
    const { sent, confirms } = page;
    const sel = await choose(page, '.lstatus', 'dropped');

    expect(confirms.length, 'a lead was written off without asking').toBe(1);
    expect(confirms[0]).toContain('Айгерім');
    expect(sent.filter((s) => s.method === 'PATCH')).toEqual([]);
    expect(sel.value).toBe('new');
  });
});
