/**
 * Render the user drawer and read the BP-calibration section it shows.
 *
 * The section is an IIFE with real branching — no calibration, a fresh one, and
 * a stale one each render differently, and a clinician reads the systolic/
 * diastolic vitals differently depending on which. A string check on the source
 * cannot tell a working branch from one that throws on the first line, so this
 * executes the real page: boot it, open a user, and assert on the drawer text.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UID = '11111111-1111-1111-1111-111111111111';
const USERS = {
  total: 1,
  users: [{ id: UID, displayName: 'Айгерим', phone: '+77001112233', dueDate: '2026-11-14T00:00:00.000Z', lastMetricAt: '2026-07-21T11:30:00.000Z' }],
};
const DETAIL = {
  id: UID, displayName: 'Айгерим', phone: '+77001112233', dueDate: '2026-11-14',
  locale: 'ru-KZ', birthDate: null, city: null,
  latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 },
  triage: [], children: [], devices: [], alerts: [], sleepNights: 0, loggedDays: 0,
  appointments: [],
};

/** A wellness payload carrying one bpCalibration (or null). */
function wellness(bpCalibration: unknown) {
  return { sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [], kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration };
}

async function openDrawer(bpCalibration: unknown): Promise<{ drawer: string; errors: string[] }> {
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
      // openUser() selects the clicked row with CSS.escape, which jsdom omits.
      (window as unknown as { CSS: unknown }).CSS = { escape: (s: string) => String(s).replace(/["\\]/g, '\\$&') };
      window.fetch = (async (path: string) => {
        const p = String(path);
        // The BI/analytics dashboards are irrelevant here; let them read as
        // unavailable (a path the panel handles) so the overview KPIs fall back
        // to /admin/stats instead of dereferencing a bi payload we didn't build.
        if (p.includes('/admin/bi') || p.includes('/admin/analytics')) {
          return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
        }
        // Order matters: the more specific per-user paths must be tested before
        // the bare /admin/users prefix they share.
        const body = p.includes('/wellness')
          ? wellness(bpCalibration)
          : p.includes('/detail')
            ? DETAIL
            : p.includes('/admin/users')
              ? USERS
              : p.includes('/admin/stats')
                ? { activeUsers: 1, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }
                : {}; // any other GET → ok, which flips the panel into LIVE mode
        return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(200);
  window.document.querySelector('[data-view="users"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(500); // the user list search is debounced on the server side
  const row = window.document.querySelector(`#usersBody tr[data-user="${UID}"]`);
  if (!row) throw new Error('no user row rendered');
  row.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(200);

  return { drawer: (window.document.querySelector('#drawer')?.textContent ?? '').replace(/\s+/g, ' ').trim(), errors };
}

const daysAgo = (n: number) => new Date(Date.now() - n * 86400000).toISOString();
const CAL = (measuredAt: string) => ({
  systolicOffset: 8, diastolicOffset: 5, calibratedAt: measuredAt,
  cuffSystolic: 130, cuffDiastolic: 85, ppgSystolic: 122, ppgDiastolic: 80,
});

describe('the BP-calibration section in the user drawer', () => {
  it('shows a fresh calibration with its offset, qualifying the BP vitals', async () => {
    const { drawer, errors } = await openDrawer(CAL(daysAgo(2)));
    expect(errors).toEqual([]);
    expect(drawer).toContain('Калибровка давления');
    expect(drawer).toContain('+8/+5 mmHg'); // the cuff − band correction
    expect(drawer).toContain('130/85'); // the cuff reading at calibration
    expect(drawer).not.toMatch(/рекомендуется повторная/); // fresh → no stale flag
  });

  it('flags a stale calibration (older than the app’s 8-day window)', async () => {
    const { drawer, errors } = await openDrawer(CAL(daysAgo(20)));
    expect(errors).toEqual([]);
    expect(drawer).toContain('Калибровка давления');
    expect(drawer).toMatch(/рекомендуется повторная/);
  });

  it('says so plainly when there is no calibration', async () => {
    const { drawer, errors } = await openDrawer(null);
    expect(errors).toEqual([]);
    expect(drawer).toContain('Калибровка давления');
    expect(drawer).toMatch(/Не откалибровано/);
  });
});
