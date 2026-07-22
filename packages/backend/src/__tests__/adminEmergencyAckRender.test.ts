/**
 * The emergency feed's acknowledge action, rendered for real (jsdom). An
 * unacknowledged emergency shows a "Подтвердить" button; an acknowledged one
 * shows who cleared it — the back-office action restored now that the backend
 * stores it.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 1, ingestLastHour: 0 };
const EMERGENCIES = {
  emergencies: [
    { id: 'u1|2026-07-15T08:00:00.000Z', userId: 'u1', displayName: 'Aigerim S.', code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-07-15T08:00:00.000Z', acknowledgedAt: null, acknowledgedBy: null },
    { id: 'u2|2026-07-15T07:00:00.000Z', userId: 'u2', displayName: 'Madina K.', code: 'HIGH_FEVER', severity: 'emergency', at: '2026-07-15T07:00:00.000Z', acknowledgedAt: '2026-07-15T07:05:00.000Z', acknowledgedBy: 's1' },
  ],
};

async function boot() {
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
        const body = p.includes('/admin/emergencies') ? EMERGENCIES
          : p.includes('/admin/stats') ? STATS
          : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });
  const { window } = dom;
  await new Promise((r) => setTimeout(r, 150));
  return {
    text: (sel: string) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel: string) => window.document.querySelectorAll(sel).length,
    errors,
  };
}

describe('admin emergency feed — acknowledge', () => {
  it('offers Подтвердить for an open emergency and shows who cleared an acked one', async () => {
    const page = await boot();
    expect(page.errors).toEqual([]);
    // One open (button) + one acknowledged (no button, shows the checkmark).
    expect(page.count('#feedFull [data-ack]')).toBe(1);
    const t = page.text('#feedFull');
    expect(t).toContain('Подтвердить');
    expect(t).toContain('✓ Подтверждено');
  });
});
