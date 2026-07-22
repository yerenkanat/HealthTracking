/**
 * Render the admin panel's baby-development-calendar tab for real (jsdom). The
 * tab must fill with week chips and the selected week's motor/speech/cognition
 * content from GET /child/development, show the WHO weight/height chips and the
 * disclaimer note, and switch language to Kazakh.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { childDevCalendar } from '../child/development.js';

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
        if (p.includes('/child/development')) return { ok: true, status: 200, json: async () => childDevCalendar };
        return { ok: false, status: 500, json: async () => ({}) };
      }) as never;
    },
  });
  const { window } = dom;
  await new Promise((r) => setTimeout(r, 120));
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

describe('admin baby-development-calendar tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="childdev"]');
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows a week chip per calendar week and the default week content', () => {
    expect(page.count('#cdWeeks .pw-wk')).toBe(childDevCalendar.weeks.length);
    expect(page.count('#cdBody .pw-card')).toBe(3); // motor / speech / cognition
    const week24 = childDevCalendar.weeks.find((w) => w.week === 24)!;
    expect(page.text('#cdBody')).toContain(week24.ru.motor.slice(0, 15));
    expect(page.text('#cdBody')).toContain('Вес'); // WHO weight chip
    expect(page.text('#cdBody')).toContain('Рост'); // WHO height chip
  });

  it('shows the paediatrician disclaimer note', () => {
    expect(page.text('#cdBody')).toContain(childDevCalendar.note.ru.slice(0, 20));
  });

  it('switches to a chosen week', async () => {
    await click(page, '#cdWeeks .pw-wk[data-cdweek="1"]');
    const week1 = childDevCalendar.weeks.find((w) => w.week === 1)!;
    expect(page.text('#cdBody')).toContain(week1.ru.motor.slice(0, 15));
  });

  it('switches language to Kazakh', async () => {
    await click(page, '.cd-l[data-cdlang="kk"]');
    expect(page.text('#cdBody')).toContain('апта'); // "N-апта" week badge
  });
});
