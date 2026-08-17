/**
 * Render the admin "Магазин → Настройки витрины" card for real (jsdom).
 *
 * Everything the STOREFRONT is configured with passes through this one form:
 * the WhatsApp number, the Kaspi link and the testimonials. A field that fails
 * to populate, or a save that quietly drops one, looks identical to a working
 * panel from the outside — which is exactly how `reviews` came to be editable
 * here while reaching nothing on the page.
 *
 * WHAT IS NO LONGER HERE, and why this file now asserts its ABSENCE. The card
 * used to be «Настройки и ключи»: the Anthropic API key, the Telegram bot token
 * and chat id sat between the WhatsApp number and a «Рейтинг (напр. 4.9)» box.
 * Credentials are not storefront content — the spec puts them on Настройки →
 * Интеграции (frames 24 / 24a) — and the key travelled to the browser in
 * plaintext to fill an `<input>` on this screen. They are on the integrations
 * screen now; see adminIntegrationKeysRender.test.ts.
 *
 * `rating` and `reviewCount` are gone outright. /shop/config deliberately
 * stopped publishing both, because nothing in the schema can produce either
 * number, so an owner typed 4.9, saw «Сохранено», and the storefront never
 * showed it.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Five fixed sleeps — 120 after boot, 250 after the tab, 50 "for the rejection
 * to be reported", 200 after each click — decided their verdict on elapsed
 * wall-clock rather than on the work being finished. The form is populated from
 * a request that chains off the tab click, so a window that closed early read
 * EMPTY boxes, and "a blank box reads as not configured" is the exact failure
 * this file exists to catch.
 *
 * They are all quiet() now: no request in flight, none newly issued for several
 * consecutive turns, no page timer outstanding, and a throw rather than a
 * half-drawn screen. See helpers/panelSettle.ts.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };
/** The analytics payload the KPI tiles and trend charts read. */
const BI = {
  devices: { online: 3, total: 5 },
  safety: { alerts7d: 2 },
  dau: 4, wau: 9, mau: 20,
  dauSeries: [{ date: '2026-08-01', value: 3 }, { date: '2026-08-02', value: 4 }],
  wauSeries: [{ date: '2026-08-01', value: 8 }, { date: '2026-08-02', value: 9 }],
  signupSeries: [{ date: '2026-08-01', value: 1 }, { date: '2026-08-02', value: 2 }],
  retentionCurve: [{ day: 0, pct: 100 }, { day: 1, pct: 60 }],
};
/**
 * What the server sends now: the redacted map plus the masks.
 *
 * `rating` and `reviewCount` are still IN it on purpose. The write no longer
 * accepts them, but rows saved before the withdrawal are still in the table,
 * and the card has to be able to say what became of them — an owner who typed
 * 4.9 last month goes looking for the box he filled in.
 */
const SETTINGS = {
  whatsapp: '77073452244',
  kaspiUrl: '',
  rating: '4.9',
  reviewCount: '120',
  reviews: '[{"name":"Айгерим, 34","city":"Алматы","text":"Отлично.","stars":5}]',
  telegramChatId: '-1001234567890',
};
const SECRETS = {
  anthropicApiKey: { stored: true, mask: '••••ored', source: 'panel', envMask: null },
  telegramBotToken: { stored: true, mask: '••••OKEN' },
  googleMapsApiKey: { stored: false, mask: null },
};

interface Booted {
  window: JSDOM['window'];
  saved: Array<Record<string, unknown>>;
  posts: string[];
  errors: string[];
  rejections: string[];
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function boot(): Promise<Booted> {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const errors: string[] = [];
  const saved: Array<Record<string, unknown>> = [];
  const posts: string[] = [];
  const rejections: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  // The panel boots from an async chain, so a throw inside it rejects a promise
  // rather than reaching the VirtualConsole. jsdom does not dispatch a window
  // 'unhandledrejection' event for scripts it runs either — the rejection
  // escapes to Node, where vitest prints it beside a green run. Catching it here
  // is the only way a broken boot fails this file instead of decorating it.
  const onRejection = (reason: unknown) => rejections.push(String(reason));
  process.on('unhandledRejection', onRejection);

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
      settle.attach(window as never, async (path: string, opts?: PanelRequestInit) => {
        const p = path;
        // Who is signed in. The catch-all used to answer this with
        // {leads,orders,products}, so the panel ran with an empty role — a
        // session no server produces. The keys card is `staff` (the response
        // carries the Anthropic key and the Telegram bot token), so an empty
        // role now correctly draws nothing at all.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен' }) };
        }
        if (p.includes('/admin/settings')) {
          if (opts?.method === 'PUT') {
            saved.push(JSON.parse(String(opts.body)));
            posts.push(p);
            return {
              ok: true, status: 200,
              json: async () => ({ ok: true, settings: SETTINGS, secrets: SECRETS, written: ['whatsapp'], keptUnchanged: [] }),
            };
          }
          return { ok: true, status: 200, json: async () => ({ settings: SETTINGS, secrets: SECRETS }) };
        }
        if (p.includes('/admin/stats')) return { ok: true, status: 200, json: async () => STATS };
        // /admin/bi feeds the KPI tiles and the trend charts, which index into
        // it. The catch-all below used to answer it with {leads,orders,...},
        // so the panel threw during boot on every run of this test.
        if (p.includes('/admin/bi')) {
          return { ok: true, status: 200, json: async () => BI };
        }
        return { ok: true, status: 200, json: async () => ({ leads: [], orders: [], products: [] }) };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  const tab = window.document.querySelector('[data-view="shop"]');
  tab?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Магазин tab');
  // Node reports a rejection on the tick after the promise is rejected with no
  // handler. This used to be a further 50 ms sleep; quiet() has already run
  // several macrotask turns with nothing in flight, which is strictly more
  // than that one tick, so the channel is drained by the time it returns.
  process.off('unhandledRejection', onRejection);
  return { window, saved, posts, errors, rejections, quiet: settle.quiet };
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

  it('boots without an unhandled rejection', () => {
    // Distinct from the check above, and from "the assertions passed". The
    // panel boots from an async chain, so a throw inside it rejects a promise
    // rather than reaching the VirtualConsole — every expectation in this file
    // can be green while the operator's screen is half-rendered. One missing
    // field in the /admin/bi payload did exactly that, taking the whole boot
    // down instead of one chart.
    expect(b.rejections).toEqual([]);
  });

  it('shows every stored storefront setting', () => {
    // A blank box reads as "not configured" and invites someone to retype a
    // value that was already right.
    expect(val('setWhatsapp')).toBe('77073452244');
    expect(val('setReviews')).toContain('Айгерим');
  });

  it('holds no credential field at all', () => {
    // The card is storefront content. A key box here is a key in the DOM of a
    // screen the whole back office can open, and it is what made the plaintext
    // round trip possible in the first place.
    for (const id of ['setAnthropic', 'setTgToken', 'setTgChat', 'setTgTest']) {
      expect(b.window.document.getElementById(id), `${id} is still on the Магазин card`).toBeNull();
    }
  });

  it('no longer offers a rating or a review count to type into', () => {
    // Two boxes that saved, read back, and reached nothing: /shop/config
    // publishes neither, because no query in this schema can produce either
    // number. Wiring them would mean inventing one.
    expect(b.window.document.getElementById('setRating')).toBeNull();
    expect(b.window.document.getElementById('setRcount')).toBeNull();
  });

  it('says what became of the rating somebody already typed', () => {
    // Silence would be its own defect: the owner filled that box in, and if the
    // field simply vanishes he assumes the panel broke. The line appears only
    // because SETTINGS still carries a stored value.
    const note = b.window.document.getElementById('setDeadFields')!;
    expect(note.hasAttribute('hidden')).toBe(false);
    expect(note.textContent).toContain('4.9');
    expect(note.textContent).toContain('120');
    // …and that they are not deleted, which is what «убрали» would imply.
    expect(note.textContent).toMatch(/не удален/i);
  });

  it('points at where the keys went', () => {
    const btn = b.window.document.getElementById('setToInt')!;
    // A real navigation, not a sentence: [data-view] is the panel's one router.
    expect(btn.getAttribute('data-view')).toBe('integrations');
  });

  it('sends the storefront fields when saving, and nothing else', async () => {
    // The save handler lists its keys by hand. A field that is rendered and
    // populated but never sent looks completely correct until somebody notices
    // their edit did not stick — and a key that is NOT rendered but still sent
    // would be sent as an empty string, wiping it.
    (b.window.document.getElementById('setWhatsapp') as HTMLInputElement).value = '77079998877';
    b.window.document.getElementById('setSave')!.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
    await b.quiet('the save');

    expect(b.saved).toHaveLength(1);
    expect(b.saved[0].whatsapp).toBe('77079998877');
    expect(b.saved[0].reviews).toContain('Айгерим');
    expect(Object.keys(b.saved[0]).sort()).toEqual(['kaspiUrl', 'reviews', 'whatsapp']);
    expect(b.posts.some((p) => p.includes('/admin/settings'))).toBe(true);
    expect(b.window.document.getElementById('setMsg')!.textContent).toContain('Сохранено');
  });
});
