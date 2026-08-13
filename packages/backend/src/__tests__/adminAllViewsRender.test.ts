/**
 * Open every tab in the admin panel and check it actually renders.
 *
 * There are twelve render tests for this panel and each one opens the tab it is
 * about. Nothing opened ALL of them, which is how a crash in the KPI tiles sat
 * on the Обзор tab: `drawBiTrend` guarded `!BI` and then read `BI.dauSeries`,
 * so one absent field threw inside boot() and took the whole screen with it. It
 * was found by accident while writing a test about the shop settings.
 *
 * The failure mode this catches is specific and easy to miss: the panel boots
 * from an async chain, so a throw is an unhandled REJECTION. It never reaches
 * the VirtualConsole, vitest prints it beside a green run, and the tab is left
 * half-drawn. So this listens on the process, and asserts each view put
 * something on screen — an empty section and a crashed section look identical
 * from the outside.
 *
 * The stub answers with the shape each endpoint really returns. Where a view
 * fails here, the first question is whether the fixture is wrong rather than
 * the panel: that is how the BI crash was diagnosed, and getting it backwards
 * would mean "fixing" working code.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { buildSyntheticPopulation } from '../analytics/syntheticPopulation.js';
import { antenatalProtocol } from '../antenatal/protocol.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/**
 * Every tab in the sidebar.
 *
 * `safety` is not one any more: «SOS и зоны» is the lower half of «Экстренные»
 * since the seven-section rail, where the artifact gives Экстренные no
 * sub-items. It is checked below, on the screen it now lives on.
 */
const VIEWS = [
  'overview', 'analytics', 'users', 'kids', 'devices',
  'emergencies', 'audit', 'content', 'antenatal', 'pregweeks',
  'childdev', 'vaccines', 'audio', 'shop', 'marketing',
] as const;

const NOW = new Date('2026-07-21T12:00:00Z');

const day = (n: number) => `2026-08-${String(n).padStart(2, '0')}`;
const series = (v: number) => [1, 2, 3].map((i) => ({ date: day(i), value: v + i }));

/** The shapes the real routes answer with. */
const FIXTURES: Record<string, unknown> = {
  '/admin/stats': { activeUsers: 12, devicesOnline: 7, alertsToday: 1, ingestLastHour: 40 },
  // The REAL payload, from the real metrics engine over a synthetic
  // population — not a hand-written shape.
  //
  // BiMetrics has a dozen nested fields (retention.d7.rate, newUsers.d30,
  // adoption keyed by event kind, the growth accounting). Writing that by hand
  // is how a fixture drifts from the endpoint, and a drifted fixture makes this
  // file report bugs in working code: my first attempt omitted `newUsers` and
  // `retention` and blamed the panel for reading them.
  '/admin/bi': computeBiMetrics({ ...buildSyntheticPopulation(NOW), now: NOW }),
  '/admin/analytics': {
    totals: { users: 74, children: 51, devices: 11, logs: 900 },
    content: { items: 40, linked: 31, stages: 101, filled: 62 },
  },
  '/admin/users': {
    users: [{ id: 'u1', displayName: 'Айгерім', phone: '+77073452244', locale: 'kk', children: 2, createdAt: day(1) }],
  },
  '/admin/children/stats': {
    total: 51, boys: 26, girls: 22, unknown: 3, withDob: 48,
    byAge: [{ bucket: '0–1', count: 12 }, { bucket: '1–3', count: 19 }, { bucket: '3–7', count: 15 }, { bucket: '7+', count: 5 }],
  },
  '/admin/devices': {
    devices: [{ id: 'd1', name: 'Umay Watch', kind: 'band', online: true, lastSeen: day(3), childName: 'Сұлтан' }],
  },
  '/admin/safety': {
    events: [{ id: 'e1', childName: 'Сұлтан', kind: 'left', zoneName: 'Школа', at: day(3) }],
  },
  '/admin/emergencies': {
    emergencies: [{ id: 'em1', userName: 'Айгерім', triage: 'high', at: day(3), acknowledgedAt: null, systolic: 152, diastolic: 96 }],
  },
  '/admin/audit': {
    audit: [{ id: 'a1', staffId: 's1', action: 'view_emergencies', target: null, at: day(3) }],
  },
  '/admin/content': { stages: {} },
  // Frame 06. The preview route must come first in the longest-match sort, so
  // it is spelled out rather than left to /admin/broadcasts.
  '/admin/broadcasts/new/preview': { segment: {}, matched: 3, excluded: 1, deliverable: 2, minGapDays: 7, describe: 'Все' },
  '/admin/broadcasts': {
    broadcasts: [{
      id: 'bc-1', titleRu: 'Второй скрининг', bodyRu: 'Окно 18–21 неделя.',
      titleKk: 'Екінші скрининг', bodyKk: '18–21 апта.',
      segment: { audience: 'pregnant' }, status: 'published', createdBy: 's1',
      createdAt: day(1), updatedAt: day(1), publishedAt: day(2), delivered: 12,
    }],
    minGapDays: 7, audiences: ['all', 'pregnant', 'mothers', 'infants'],
    locales: ['ru', 'kk'], segmentFields: ['audience', 'locale'], infantMaxMonths: 12,
  },
  '/admin/audio': { audio: [] },
  '/admin/shop/variants': { variants: [{ id: 'v1', productName: 'Часы', color: 'black', stock: 12, priceMinor: 2490000 }] },
  '/admin/shop/orders': { orders: [] },
  '/admin/shop/leads': { leads: [] },
  // NOT an /admin route: the Дородовое наблюдение tab reads the public
  // protocol the app uses. Worth noting because an audit of "endpoints with
  // no caller" earlier flagged /admin/reference/antenatal as unwired — it is not,
  // the admin panel is its caller.
  '/admin/reference/antenatal': antenatalProtocol,
  '/admin/settings': { settings: { whatsapp: '77073452244', reviews: '', rating: '', reviewCount: '', kaspiUrl: '' } },
};

interface Booted {
  window: JSDOM['window'];
  errors: string[];
  rejections: string[];
}

async function boot(view: string): Promise<Booted> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const rejections: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const onRejection = (reason: unknown) => rejections.push(String(reason));
  process.on('unhandledRejection', onRejection);

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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      window.fetch = (async (path: string) => {
        const p = String(path);
        // The panel now opens on a sign-in gate and asks who is signed in
        // before it renders anything. These tests are about the dashboard,
        // so they answer as a signed-in admin.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        // Longest match first: /admin/shop/leads must not be answered by
        // /admin/shop.
        const key = Object.keys(FIXTURES)
          .filter((k) => p.includes(k))
          .sort((a, b) => b.length - a.length)[0];
        const body = key ? FIXTURES[key] : {};
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 150));
  window.document.querySelector(`[data-view="${view}"]`)?.dispatchEvent(
    new window.MouseEvent('click', { bubbles: true }),
  );
  await new Promise((r) => setTimeout(r, 300));
  process.off('unhandledRejection', onRejection);
  return { window, errors, rejections };
}

describe('every admin view renders', () => {
  it.each(VIEWS)('%s', async (view) => {
    const b = await boot(view);

    expect(b.errors, `${view}: script error`).toEqual([]);
    // The one that matters. A rejection inside the boot chain leaves the tab
    // half-drawn and every other assertion here still passing.
    expect(b.rejections, `${view}: unhandled rejection during render`).toEqual([]);

    const section = b.window.document.querySelector(`section#${view}`);
    expect(section, `${view}: no section in the markup`).not.toBeNull();
    const text = (section!.textContent ?? '').replace(/\s+/g, ' ').trim();
    expect(text.length, `${view}: rendered nothing — an empty tab and a crashed tab look the same`)
      .toBeGreaterThan(20);
    // "Загрузка…" left on screen means the render never replaced the
    // placeholder, which is the visible half of the same failure.
    expect(text, `${view}: still showing its loading placeholder`).not.toMatch(/^Загрузка…$/);
  }, 30_000);

  it('«Экстренные» carries the SOS and geofence feed that used to be its own tab', async () => {
    // The merge is the reason `safety` left the list above. If the table had
    // simply been deleted with the tab, everything here would still be green
    // and the geofence feed would be unreachable in the product.
    const b = await boot('emergencies');
    expect(b.errors, 'script error').toEqual([]);
    expect(b.rejections, 'unhandled rejection').toEqual([]);
    const table = b.window.document.querySelector('#emergencies #safetyBody');
    expect(table, 'the SOS feed is not on the Экстренные screen').not.toBeNull();
    expect(table!.textContent).toContain('Школа');
  }, 30_000);
});
