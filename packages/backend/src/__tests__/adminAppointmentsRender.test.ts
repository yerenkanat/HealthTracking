/**
 * The admin patient drawer shows a mother's upcoming visits (from
 * GET /admin/users/:id/detail, which now carries her appointments). Rendered for
 * real in jsdom — the "window into the app" staff need to see the antenatal plan
 * she is actually keeping.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };
const USERS = { total: 1, users: [{ id: 'u1', displayName: 'Aigerim S.', phone: '+77073452244', dueDate: '2026-11-14T00:00:00.000Z', lastMetricAt: '2026-07-21T11:30:00.000Z' }] };
const DETAIL = {
  displayName: 'Aigerim S.',
  phone: '+77073452244',
  appointments: [
    { id: 'a1', title: 'Приём у гинеколога', at: '2026-08-03T09:30:00.000Z', note: '' },
    { id: 'a2', title: 'УЗИ второго триместра', at: '2026-08-20T10:00:00.000Z', note: '' },
  ],
};
const WELLNESS = {
  sleep: [
    { night: '2026-07-21', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25 },
    { night: '2026-07-20', deepMin: 70, remMin: 90, lightMin: 250, awakeMin: 35 },
  ],
  days: [],
  alerts: [],
};

async function boot() {
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
        return new Proxy({ canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      window.fetch = (async (path: string) => {
        const p = String(path);
        // Only the endpoints this test needs answer; the rest degrade (the panel
        // keeps BI null and falls back rather than crashing on a malformed body).
        const body = p.includes('/admin/users/u1/detail') ? DETAIL
          : p.includes('/admin/users/u1/wellness') ? WELLNESS
          : p.includes('/admin/users') ? USERS
          : p.includes('/admin/stats') ? STATS
          : p.includes('/pregnancy/weeks') ? { weeks: [] }
          : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });
  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(150);
  return {
    text: (sel: string) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    errors,
    window,
    click: async (sel: string) => { window.document.querySelector(sel)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true })); await wait(150); },
  };
}

describe('admin patient drawer — upcoming visits', () => {
  it('lists her appointments, soonest first', async () => {
    const page = await boot();
    await page.click('[data-view="users"]');
    await page.click('#usersBody tr[data-user="u1"]');
    const drawer = page.text('#drawer');
    expect(page.errors).toEqual([]);
    expect(drawer).toContain('Ближайшие визиты');
    expect(drawer).toContain('Приём у гинеколога');
    expect(drawer).toContain('УЗИ второго триместра');
    // Soonest first (Aug 3 before Aug 20).
    expect(drawer.indexOf('гинеколога')).toBeLessThan(drawer.indexOf('УЗИ второго'));
  });

  it('shows her recent sleep — the same nights the app Sleep card shows', async () => {
    const page = await boot();
    await page.click('[data-view="users"]');
    await page.click('#usersBody tr[data-user="u1"]');
    const drawer = page.text('#drawer');
    expect(page.errors).toEqual([]);
    expect(drawer).toContain('Сон (последние ночи)');
    // Night 1 total asleep = 95 + 105 + 280 = 480 min = 8ч 0мин.
    expect(drawer).toContain('8ч 0мин');
    // The deep/REM breakdown is shown too.
    expect(drawer).toContain('глуб.');
  });
});
