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
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

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

async function openShop(opts: { failWrites?: boolean } = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const sent: Sent[] = [];
  const alerts: string[] = [];
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
      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
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
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 150));
  window.document.querySelector('[data-view="shop"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 300));
  return { window, sent, errors, alerts };
}

/** Pick a new value on a `<select>` and fire the change the browser would. */
async function choose(window: JSDOM['window'], selector: string, value: string) {
  const sel = window.document.querySelector(selector) as HTMLSelectElement;
  expect(sel, `no ${selector} on the page`).not.toBeNull();
  sel.value = value;
  sel.dispatchEvent(new window.Event('change', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 200));
  return sel;
}

describe('settings cannot be wiped by a failed load', () => {
  /** Open Магазин with GET /admin/settings broken. */
  async function openWithBrokenSettings() {
    const html = readFileSync(PANEL, 'utf8');
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
        window.fetch = (async (path: string, init?: RequestInit) => {
          const p = String(path);
          const method = init?.method ?? 'GET';
          if (method !== 'GET') {
            sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
            return { ok: true, status: 200, json: async () => ({ ok: true }) };
          }
          // The one that breaks.
          if (p.includes('/admin/settings')) return { ok: false, status: 503, json: async () => ({}) };
          const body = p.includes('/admin/shop/leads') ? { leads: [] }
            : p.includes('/admin/shop/orders') ? { orders: [] }
            : p.includes('/admin/shop/variants') ? { variants: [] }
            : p.includes('/admin/stats') ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
            : {};
          return { ok: true, status: 200, json: async () => body };
        }) as never;
      },
    });
    const { window } = dom;
    await new Promise((r) => setTimeout(r, 150));
    window.document.querySelector('[data-view="shop"]')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 300));
    return { window, sent };
  }

  it('refuses to save when it never learned what the server holds', async () => {
    // The path that destroys data: the load fails, every box is left empty —
    // which reads as "nothing is configured" — and one click of Сохранить
    // sends "" for every field. The API stores what it is sent, because an
    // empty string is not undefined, so that single click wipes the Anthropic
    // key, the Telegram token, the WhatsApp number and the reviews.
    const { window, sent } = await openWithBrokenSettings();

    const save = window.document.getElementById('setSave') as HTMLButtonElement;
    expect(save.disabled, 'the save button should be disabled after a failed load').toBe(true);

    // And if it is clicked anyway, nothing is written.
    save.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));
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
    const { window, sent } = await openShop();
    await choose(window, '.lstatus', 'called');

    const write = sent.find((s) => s.path.includes('/admin/shop/leads/'));
    expect(write, 'no request went out — the dropdown changed nothing').toBeTruthy();
    expect(write!.method).toBe('PATCH');
    expect(write!.path).toContain('lead-1');
    expect(write!.body).toEqual({ status: 'called' });
  });

  it('changing an order status PATCHes it', async () => {
    const { window, sent } = await openShop();
    await choose(window, '.ostatus', 'shipped');

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
    const { window, sent, alerts } = await openShop({ failWrites: true });
    const sel = await choose(window, '.lstatus', 'called');

    expect(sent.some((s) => s.method === 'PATCH'), 'it did try').toBe(true);
    expect(sel.value, 'the dropdown must not keep a value the server rejected')
      .toBe('new');
    // Reverting silently is only half a fix: the operator would see the value
    // snap back with no idea whether they mis-clicked or the save failed.
    expect(alerts.join(' '), 'nothing told the operator').toMatch(/не удалось/i);
  });
});
