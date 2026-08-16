/**
 * Frame 08b — deleting a category, from the panel — docs/BACKLOG.md §3.2.
 *
 * DELETE /admin/shop/categories/:id was written, audited and guarded with a
 * 409, and nothing ever called it: the panel only ever PUT. A mistyped category
 * therefore stayed in the storefront rail for good, because the only way to
 * remove it was a curl command.
 *
 * What the 409 actually protects is the thing the confirmation has to say. The
 * foreign key is ON DELETE SET NULL, so without the check the delete would
 * SUCCEED and quietly uncategorise every product on that shelf. Products are
 * never deleted — in either outcome — and the screen says that rather than a
 * generic «это действие необратимо».
 *
 * Executed in jsdom (`runScripts: 'dangerously'`), because the panel is one
 * file a browser runs top to bottom and «verified structurally» would not
 * catch a slip that takes every later block with it.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const product = (id: string, category: string | null) => ({
  id, name: `Товар ${id}`, nameKk: null,
  priceMinor: 100_000, costMinor: null, active: true, sort: 1, sku: null,
  kind: 'simple', category, stage: null,
  descriptionRu: null, descriptionKk: null,
  ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
  seoSlug: null, seoTitle: null, seoDescription: null,
  stock: 1, lowStock: false, variants: [],
});

/** «watch» holds a product; «gifts» is the empty, mistyped one. */
const CATALOG = {
  stages: ['pregnancy', 'any'],
  categories: [
    { id: 'watch', nameRu: 'Смарт-часы', nameKk: 'Смарт-сағат', sort: 10 },
    { id: 'gifts', nameRu: 'Подрки', nameKk: null, sort: 20 },
  ],
  products: [product('watch', 'watch')],
};

interface Sent { url: string; method: string }

interface Rendered {
  text(sel: string): string;
  el(sel: string): Element | null;
  click(sel: string): Promise<void>;
  confirms: string[];
  sent: Sent[];
  errors: string[];
  /** How many times the catalogue was (re)read. */
  loads: number;
}

async function boot(opts: { answer?: boolean; deleteStatus?: number } = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const confirms: string[] = [];
  const sent: Sent[] = [];
  let loads = 0;
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/admin/ui', virtualConsole: vc,
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
      window.fetch = (async (path: string, init?: { method?: string }) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (method !== 'GET') sent.push({ url: p, method });
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (method === 'DELETE') {
          const code = opts.deleteStatus ?? 200;
          return {
            ok: code === 200, status: code,
            text: async () => (code === 409 ? '{"error":"category_in_use"}' : ''),
            json: async () => (code === 200 ? { ok: true } : { error: 'category_in_use' }),
          };
        }
        if (p.includes('/admin/shop/products')) {
          loads += 1;
          return { ok: true, status: 200, json: async () => CATALOG };
        }
        if (p.includes('/admin/children/stats')) {
          return { ok: true, status: 200, json: async () => ({ total: 0, boys: 0, girls: 0, unknown: 0, withDob: 0, byAge: [] }) };
        }
        return { ok: false, status: 500, json: async () => ({}) };
      }) as never;
    },
  });

  const { window } = dom;
  const settle = (ms = 200) => new Promise((r) => setTimeout(r, ms));
  await settle(150);
  window.document.querySelector('[data-view="catalog"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle(250);

  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    el: (sel) => window.document.querySelector(sel),
    click: async (sel) => {
      const el = window.document.querySelector(sel) as HTMLElement | null;
      expect(el, `no ${sel}`).not.toBeNull();
      el!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle(250);
    },
    confirms, sent, errors,
    get loads() { return loads; },
  };
}

describe('the category card lists what can be deleted', () => {
  it('boots without throwing', async () => {
    const p = await boot();
    expect(p.errors, p.errors.join('\n')).toEqual([]);
  });

  it('offers a delete button per category, with its code and its product count', async () => {
    const p = await boot();
    const t = p.text('#catCatList');
    expect(t).toContain('Подрки');
    expect(t).toContain('gifts');
    expect(t).toContain('товаров: 0');
    expect(t).toContain('товаров: 1');
  });

  /**
   * The refusal, said BEFORE the click rather than after a 409: the panel
   * already knows the count, and a button that can only fail is worse than a
   * button that explains itself.
   */
  it('disables the button on a category that still holds products, and says why', async () => {
    const p = await boot();
    const busy = p.el('button[data-delcat="watch"]') as HTMLButtonElement;
    expect(busy.disabled).toBe(true);
    expect(busy.getAttribute('title')).toContain('переведите');
    const free = p.el('button[data-delcat="gifts"]') as HTMLButtonElement;
    expect(free.disabled).toBe(false);
  });

  it('states the rule under the list — what the 409 protects', async () => {
    const p = await boot();
    const rule = p.text('#catCatRule');
    expect(rule).toContain('только пустую');
    expect(rule).toContain('Товары не удаляются');
  });
});

describe('deleting one asks first', () => {
  it('names the category and its code, and says what happens to the products', async () => {
    const p = await boot();
    await p.click('button[data-delcat="gifts"]');
    expect(p.confirms.length, 'a category was deleted without asking').toBe(1);
    expect(p.confirms[0]).toContain('Подрки');
    expect(p.confirms[0]).toContain('gifts');
    // The consequence, accurately: the rail loses the category, the shelf keeps
    // its products.
    expect(p.confirms[0]).toContain('Товары не удаляются');
    expect(p.confirms[0]).toMatch(/витрин/i);
  });

  it('sends nothing when the answer is no', async () => {
    const p = await boot({ answer: false });
    await p.click('button[data-delcat="gifts"]');
    expect(p.sent.filter((s) => s.method === 'DELETE')).toEqual([]);
  });

  it('sends the DELETE to the id it named, and reloads the catalogue', async () => {
    const p = await boot();
    const before = p.loads;
    await p.click('button[data-delcat="gifts"]');
    const del = p.sent.find((s) => s.method === 'DELETE');
    expect(del, 'the confirmed delete never reached the server').toBeDefined();
    expect(del!.url).toBe('/admin/shop/categories/gifts');
    expect(p.loads, 'the list was not re-read after the delete').toBeGreaterThan(before);
    expect(p.text('#catCatMsg')).toContain('удалена');
  });
});

describe('a refusal is reported as a refusal', () => {
  it('says the server kept the category and why, instead of a tick', async () => {
    // The concurrent case: the panel's count was stale and the server refused.
    const p = await boot({ deleteStatus: 409 });
    await p.click('button[data-delcat="gifts"]');
    const msg = p.text('#catCatMsg');
    expect(msg).toContain('не удалена');
    expect(msg).toContain('в ней есть товары');
    expect(p.el('#catCatMsg')!.className).toContain('err');
  });

  it('reports any other failure with its status rather than swallowing it', async () => {
    const p = await boot({ deleteStatus: 500 });
    await p.click('button[data-delcat="gifts"]');
    const msg = p.text('#catCatMsg');
    expect(msg).toContain('Не удалось удалить');
    expect(msg).toContain('500');
  });
});
