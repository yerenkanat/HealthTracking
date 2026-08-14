/**
 * «Не обработано: N» — the number that drives the callback queue.
 *
 * It counted `status === 'new'` over ONE page of /admin/shop/leads (limit 100)
 * and printed it as a total, while «Сводка» two clicks away printed «9 из 34»
 * from a real count(*). The queue was worked off the smaller number, and since
 * the page is newest-first, what falls off it are the oldest uncalled leads —
 * the women who have been waiting longest.
 *
 * Three states, and the panel must be able to tell them apart on screen:
 *   - the page held the whole table  → the count IS the total;
 *   - it did not, but «Сводка» is loaded → use the served count(*);
 *   - it did not, and it is not      → say «не менее», never a bare number.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const lead = (id: string, status: string) => ({
  id, customerName: `Клиент ${id}`, phone: '+7 707 345 22 44',
  package: 'Комплект', locale: 'ru', status, createdAt: '2026-08-01T09:12:00.000Z',
});

/** Снимок «Сводки» с настоящим count(*): 34 заявки, 9 без звонка. */
const SNAPSHOT = {
  asOf: '2026-08-06T10:00:00.000Z',
  users: { total: 240, newToday: 3, new7d: 19, new30d: 62, dau: 41, wau: 120, mau: 190, retentionD7: 0.34 },
  mothers: { pregnant: 90, mothers: 130, both: 22, unknown: 42 },
  children: { total: 0, boys: 0, girls: 0, unknown: 0, withDob: 0, byAge: [] },
  devices: { total: 96, online: 61, watches: 54, trackers: 42, unassigned: 7, unregistered: 0 },
  cities: [], citiesUnknown: 240,
  commerce: {
    leads: { total: 34, new: 9 },
    orders: { total: 31, new: 4, confirmed: 3, shipped: 12, delivered: 10, cancelled: 2 },
    revenueMinor: 65_000_00, pipelineMinor: 12_400_00, avgOrderMinor: 2_954_00,
    stock: { units: 120, retailMinor: 200_000_00, costMinor: 130_000_00, unitsWithoutCost: 20 },
    lowStock: [],
  },
  course: { lessons: 0, granted: 0, started: 0, finished: 0, lessonsCompleted: 0, active7d: 0 },
};

interface Page {
  text(sel: string): string;
  errors: string[];
}

/**
 * @param leadsBody what GET /admin/shop/leads answers
 * @param withSummary open «Сводка» first, so the served count(*) is in memory
 */
async function render(leadsBody: unknown, withSummary = false): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
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
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/dashboard')) {
          return withSummary
            ? { ok: true, status: 200, json: async () => SNAPSHOT }
            : { ok: false, status: 403, json: async () => ({ error: 'forbidden' }) };
        }
        const body = p.includes('/admin/shop/leads') ? leadsBody
          : p.includes('/admin/shop/orders') ? { orders: [] }
            : p.includes('/admin/shop/variants') ? { variants: [] }
              : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(150);
  if (withSummary) {
    window.document.querySelector('[data-view="overview"]')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await wait(200);
  }
  window.document.querySelector('[data-view="shop"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(250);

  return {
    errors,
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
  };
}

describe('when the page held every lead', () => {
  it('prints the count as the total it is, and says the rule', async () => {
    const page = await render({
      leads: [lead('l-1', 'new'), lead('l-2', 'called'), lead('l-3', 'new')],
      counts: { shown: 3, uncalled: 2 }, limit: 100, exact: true,
    });
    expect(page.errors).toEqual([]);
    expect(page.text('#shopLeadsSub')).toContain('не обработано: 2');
    expect(page.text('#shopLeadsFoot')).toContain('вместила таблицу целиком');
  });
});

describe('when the page did not hold every lead', () => {
  const TRUNCATED = {
    leads: [lead('l-1', 'new'), lead('l-2', 'new')],
    counts: { shown: 2, uncalled: 2 }, limit: 2, exact: false,
  };

  it('uses the count(*) «Сводка» already served, not the page it can see', async () => {
    const page = await render(TRUNCATED, true);
    expect(page.errors).toEqual([]);
    // 9 of 34, from the dashboard — NOT the 2 on this page.
    expect(page.text('#shopLeadsSub')).toContain('не обработано: 9');
    expect(page.text('#shopLeadsSub')).toContain('34');
    expect(page.text('#shopLeadsFoot')).toContain('последние 2');
  });

  it('calls the number a floor when nothing has served the total', async () => {
    // A seller has no `finance`, so /admin/dashboard refuses her and there is
    // no count(*) anywhere on her screen. The panel must not print the page's
    // count as if it were the answer.
    const page = await render(TRUNCATED, false);
    expect(page.errors).toEqual([]);
    const sub = page.text('#shopLeadsSub');
    expect(sub).toContain('не менее 2');
    expect(sub).toContain('показаны последние 2');
    expect(page.text('#shopLeadsFoot')).toContain('точное');
  });
});

describe('an older backend that sends only the rows', () => {
  it('still counts, and still states its rule', async () => {
    const page = await render({ leads: [lead('l-1', 'new'), lead('l-2', 'called')] });
    expect(page.errors).toEqual([]);
    expect(page.text('#shopLeadsSub')).toContain('не обработано: 1');
    expect(page.text('#shopLeadsFoot')).not.toBe('');
  });

  it('says «нет заявок» for an empty queue rather than «не обработано: 0»', async () => {
    const page = await render({ leads: [], counts: { shown: 0, uncalled: 0 }, limit: 100, exact: true });
    expect(page.text('#shopLeadsSub')).toBe('нет заявок');
    expect(page.text('#shopLeads')).toContain('Заявок пока нет');
  });
});
