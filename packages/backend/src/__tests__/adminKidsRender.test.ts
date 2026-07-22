/**
 * Render the admin "Дети" demographics tab for real (jsdom): KPIs, the gender
 * split bar, and the age-bucket bars from GET /admin/children/stats.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };
const KIDS = {
  total: 10, boys: 6, girls: 3, unknown: 1, withDob: 9,
  byAge: [
    { bucket: '0–1', count: 2 },
    { bucket: '1–3', count: 3 },
    { bucket: '3–7', count: 3 },
    { bucket: '7+', count: 1 },
  ],
};

interface Rendered { text(s: string): string; count(s: string): number; errors: string[]; }

async function boot(): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin/ui', virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy({ canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.fetch = (async (path: string) => {
        const p = String(path);
        const body = p.includes('/admin/children/stats') ? KIDS
          : p.includes('/admin/stats') ? STATS
          : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });
  const { window } = dom;
  await new Promise((r) => setTimeout(r, 120));
  window.document.querySelector('[data-view="kids"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 120));
  return {
    text: (s) => (window.document.querySelector(s)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (s) => window.document.querySelectorAll(s).length,
    errors,
  };
}

describe('admin children demographics tab', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows the totals, gender split and age buckets', () => {
    const t = page.text('#kidsBody');
    expect(t).toContain('всего детей');
    expect(t).toContain('10'); // total
    expect(t).toContain('60%'); // boys 6/10
    expect(page.count('#kidsBody .k-seg')).toBe(3); // boys / girls / unknown segments
    expect(page.count('#kidsBody .k-agerow')).toBe(4); // four age buckets
  });
});
