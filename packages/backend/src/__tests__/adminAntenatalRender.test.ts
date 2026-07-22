/**
 * Render the admin panel's antenatal tab and patient drawer for real (jsdom),
 * not just grep the HTML. The protocol view must fill with the 8 visits served
 * by GET /antenatal/protocol, and a patient's drawer must show which visit she
 * is due — the "window into the app" the panel is supposed to be.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { antenatalProtocol } from '../antenatal/protocol.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
  window: import('jsdom').DOMWindow;
}

/** Boot the real panel; only /antenatal/protocol answers, so it stays on MOCK
 * users (which carry gestational weeks) for the drawer. */
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
      // jsdom does not implement CSS.escape, which openUser() uses to find the row.
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/antenatal/protocol')) {
          return { ok: true, status: 200, json: async () => antenatalProtocol };
        }
        // The users list is API-driven; answer it so rows render. The panel
        // seeds the drawer's gestational week from its own MOCK.users (u1 = 28w),
        // so /admin/stats stays down and the panel remains in mock mode.
        if (p.includes('/admin/users')) {
          return {
            ok: true,
            status: 200,
            json: async () => ({ total: 1, users: [{ id: 'u1', displayName: 'Aigerim S.', phone: '+77073452244', dueDate: '2026-11-14T00:00:00.000Z', lastMetricAt: '2026-07-21T11:30:00.000Z' }] }),
          };
        }
        return { ok: false, status: 500, json: async () => ({}) }; // everything else down → mock mode
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
  await new Promise((r) => setTimeout(r, 120));
}

describe('admin antenatal tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="antenatal"]');
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('fills the view with the eight visits from the served protocol', () => {
    expect(page.count('#antenatal .an-grid .an-visit')).toBe(8);
    const t = page.text('#antenatal');
    expect(t).toContain('Визит 1');
    expect(t).toContain('Визит 8');
    // A known item label and a risk tag both rendered.
    expect(t).toContain('Фолиевая кислота 400 мкг в день');
    expect(t).toContain('по показаниям');
  });

  it('lists the time-sensitive screening windows', () => {
    expect(page.text('#antenatal')).toMatch(/нельзя пропустить/);
  });
});

describe('admin patient drawer — antenatal status', () => {
  it('shows which visit the mother is due, from her gestational week', async () => {
    const page = await boot();
    await click(page, '[data-view="users"]');
    // MOCK user u1 is at 28 weeks → visit 3 is due now.
    await click(page, '#usersBody tr[data-user="u1"]');
    const drawer = page.text('#drawer');
    expect(drawer).toContain('Антенатальный план');
    expect(drawer).toContain('Визит 3 из 8');
    expect(drawer).toContain('пора на визит');
  });
});
