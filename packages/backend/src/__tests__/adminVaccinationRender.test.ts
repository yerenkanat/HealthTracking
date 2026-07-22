/**
 * Render the admin panel's vaccination tab for real (jsdom). It must fill with
 * the immunisation schedule served by GET /vaccination/schedule, grouped by age.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { vaccinationSchedule } from '../vaccination/schedule.js';

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
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/vaccination/schedule')) return { ok: true, status: 200, json: async () => vaccinationSchedule };
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

describe('admin vaccination tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    page.window.document.querySelector('[data-view="vaccines"]')!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 120));
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('renders the schedule grouped by age', () => {
    // One card per distinct scheduled age.
    const ages = new Set(vaccinationSchedule.vaccines.map((v) => v.atMonth));
    expect(page.count('#vaccines .an-grid .an-visit')).toBe(ages.size);
    const t = page.text('#vaccines');
    expect(t).toContain('При рождении'); // month 0
    expect(t).toContain('Гепатит B');
    expect(t).toContain('доза'); // multi-dose vaccines show a dose tag
  });
});
