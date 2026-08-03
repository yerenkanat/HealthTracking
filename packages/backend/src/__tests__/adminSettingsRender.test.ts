/**
 * Render the admin "Магазин → Настройки" panel for real (jsdom).
 *
 * Everything the storefront is configured with passes through this one form:
 * the WhatsApp number, the testimonials, and now the Telegram credentials that
 * decide whether anyone hears about a new lead. A field that fails to populate,
 * or a save that quietly drops a key, looks identical to a working panel from
 * the outside — which is exactly how `reviews` came to be editable here while
 * reaching nothing on the page.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };
const SETTINGS = {
  whatsapp: '77073452244',
  kaspiUrl: '',
  anthropicApiKey: 'sk-ant-stored',
  googleMapsApiKey: '',
  rating: '4.9',
  reviewCount: '120',
  reviews: '[{"name":"Айгерим, 34","city":"Алматы","text":"Отлично.","stars":5}]',
  telegramBotToken: '123456:STORED-TOKEN',
  telegramChatId: '-1001234567890',
};

interface Booted {
  window: JSDOM['window'];
  saved: Array<Record<string, unknown>>;
  posts: string[];
  errors: string[];
}

async function boot(): Promise<Booted> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const saved: Array<Record<string, unknown>> = [];
  const posts: string[] = [];
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
      window.fetch = (async (path: string, opts?: RequestInit) => {
        const p = String(path);
        if (p.includes('/admin/settings/test-telegram')) {
          posts.push(p);
          return { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/settings')) {
          if (opts?.method === 'PUT') {
            saved.push(JSON.parse(String(opts.body)));
            return { ok: true, status: 200, json: async () => ({ ok: true, settings: SETTINGS }) };
          }
          return { ok: true, status: 200, json: async () => ({ settings: SETTINGS }) };
        }
        if (p.includes('/admin/stats')) return { ok: true, status: 200, json: async () => STATS };
        return { ok: true, status: 200, json: async () => ({ leads: [], orders: [], products: [] }) };
      }) as never;
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 120));
  const tab = window.document.querySelector('[data-view="shop"]');
  tab?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 250));
  return { window, saved, posts, errors };
}

let b: Booted;
beforeAll(async () => {
  b = await boot();
}, 30_000);

const val = (id: string) => (b.window.document.getElementById(id) as HTMLInputElement | null)?.value;

describe('the shop settings form', () => {
  it('renders without a script error', () => {
    expect(b.errors).toEqual([]);
  });

  it('shows every stored setting, including the Telegram credentials', () => {
    // A blank box reads as "not configured" and invites someone to retype a
    // token that was already right.
    expect(val('setWhatsapp')).toBe('77073452244');
    expect(val('setRating')).toBe('4.9');
    expect(val('setReviews')).toContain('Айгерим');
    expect(val('setTgToken')).toBe('123456:STORED-TOKEN');
    expect(val('setTgChat')).toBe('-1001234567890');
  });

  it('sends the Telegram fields when saving', async () => {
    // The save handler lists the keys by hand, so a new field that is rendered
    // and populated but never sent looks completely correct until someone
    // notices their edit did not stick.
    (b.window.document.getElementById('setTgChat') as HTMLInputElement).value = '-100999';
    b.window.document.getElementById('setSave')!.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));

    expect(b.saved).toHaveLength(1);
    expect(b.saved[0].telegramChatId).toBe('-100999');
    expect(b.saved[0].telegramBotToken).toBe('123456:STORED-TOKEN');
    // And it still sends everything it did before.
    expect(b.saved[0].whatsapp).toBe('77073452244');
    expect(b.saved[0].reviews).toContain('Айгерим');
  });

  it('has a test button that actually calls the server', async () => {
    // "Сохранено" is not "работает": the token is only proven by a real send.
    b.window.document.getElementById('setTgTest')!.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));
    expect(b.posts.some((p) => p.includes('/admin/settings/test-telegram'))).toBe(true);
    expect(b.window.document.getElementById('setMsg')!.textContent).toContain('Отправлено');
  });
});
