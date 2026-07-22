/**
 * Render the admin panel's pregnancy-calendar tab and patient drawer for real
 * (jsdom). The tab must fill with week chips and the selected week's content
 * from GET /pregnancy/weeks, switch language, and the patient drawer must show
 * "this week" content for the mother's gestational week.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { pregnancyCalendar } from '../pregnancy/weeks.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
  window: import('jsdom').DOMWindow;
}

async function boot(): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
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
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/pregnancy/weeks')) return { ok: true, status: 200, json: async () => pregnancyCalendar };
        if (p.includes('/admin/users')) {
          return { ok: true, status: 200, json: async () => ({ total: 1, users: [{ id: 'u1', displayName: 'Aigerim S.', phone: '+77073452244', dueDate: '2026-11-14T00:00:00.000Z', lastMetricAt: '2026-07-21T11:30:00.000Z' }] }) };
        }
        return { ok: false, status: 500, json: async () => ({}) };
      }) as never;
    },
  });
  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    errors,
    window,
  };
}
async function click(page: Rendered, sel: string) {
  page.window.document.querySelector(sel)!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 100));
}

describe('admin pregnancy-calendar tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="pregweeks"]');
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows a week chip per calendar week and the default week content', () => {
    expect(page.count('#pwWeeks .pw-wk')).toBe(pregnancyCalendar.weeks.length);
    expect(page.count('#pwBody .pw-card')).toBe(3); // baby / you / recommend
    expect(page.text('#pwBody')).toContain('Неделя 12');
  });

  it('switches to a chosen week', async () => {
    await click(page, '#pwWeeks .pw-wk[data-week="6"]');
    const week6 = pregnancyCalendar.weeks.find((w) => w.week === 6)!;
    expect(page.text('#pwBody')).toContain(week6.ru.baby.slice(0, 20));
  });

  it('switches language to Kazakh', async () => {
    await click(page, '.pw-l[data-lang="kk"]');
    expect(page.text('#pwBody')).toContain('Апта');
  });
});

describe('admin patient drawer — this week content', () => {
  it('shows this-week baby/you text for the mother’s gestational week', async () => {
    const page = await boot();
    await click(page, '[data-view="users"]');
    await click(page, '#usersBody tr[data-user="u1"]'); // MOCK u1 = 28 weeks
    const drawer = page.text('#drawer');
    expect(drawer).toContain('Эта неделя');
    const week28 = pregnancyCalendar.weeks.find((w) => w.week === 28)!;
    expect(drawer).toContain(week28.ru.baby.slice(0, 20));
  });
});
