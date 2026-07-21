/**
 * Render the admin panel and read what it actually shows.
 *
 * adminPanel.test.ts checks that the HTML contains the right strings and route
 * names. That is worth having, and it cannot catch the failure that actually
 * happens: the markup is present, a render function throws on the first line,
 * and the section stays empty. Every check in that file passed while the
 * Аналитика tab rendered nothing at all.
 *
 * So this one executes the page — the real file, the real render path — with a
 * stubbed fetch returning a payload computed by the real metrics engine, and
 * asserts on the resulting text.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { buildSyntheticPopulation } from '../analytics/syntheticPopulation.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NOW = new Date('2026-07-21T12:00:00Z');
const pop = buildSyntheticPopulation(NOW);
const FULL = computeBiMetrics({ ...pop, now: NOW });

const ANALYTICS = {
  totalUsers: 261,
  pregnant: 120,
  withChildren: 140,
  devices: 161,
  contentStages: 40,
  contentItems: 364,
  contentLinked: 300,
};

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
}

/** Load the panel, let it boot, click through to [view], return its text. */
async function render(bi: unknown, view: string): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin/ui',
    virtualConsole: vc,
    // boot() runs the moment the script parses, so the stubs must already be
    // in place — installing them afterwards leaves the first fetch unstubbed
    // and makes a working panel look broken.
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          {
            canvas: { width: 600, height: 170 },
            createLinearGradient: () => ({ addColorStop: noop }),
            measureText: () => ({ width: 10 }),
          },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      window.fetch = (async (path: string) => {
        const p = String(path);
        const body = p.includes('/admin/bi')
          ? bi
          : p.includes('/admin/analytics')
            ? ANALYTICS
            : {};
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document
    .querySelector(`[data-view="${view}"]`)!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(120);

  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    errors,
  };
}

describe('the analytics tab renders the whole product, not the device fleet', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await render(FULL, 'analytics');
  });

  it('runs without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows every section with content', () => {
    for (const sel of ['#anKpis', '#anGrowth', '#anFunnel', '#anAdoption', '#biRetention', '#biEngagement', '#anComposition', '#anContent']) {
      expect(page.text(sel).length, `${sel} rendered empty`).toBeGreaterThan(10);
      expect(page.text(sel), `${sel} reported unavailable`).not.toMatch(/недоступен/);
    }
  });

  it('shows the acquisition windows as headline tiles', () => {
    expect(page.count('#anKpis .kpi')).toBeGreaterThanOrEqual(8);
    const t = page.text('#anKpis');
    for (const label of ['DAU', 'WAU', 'MAU', 'Липкость', 'Чистый прирост', 'Отток']) {
      expect(t).toContain(label);
    }
  });

  it('breaks the base into where its actives came from', () => {
    const t = page.text('#anGrowth');
    for (const label of ['Новые', 'Вернувшиеся', 'Остались', 'Ушли', 'Чистое изменение']) {
      expect(t).toContain(label);
    }
  });

  it('shows the funnel with its conversion between stages', () => {
    const t = page.text('#anFunnel');
    expect(t).toContain('Зарегистрировались');
    expect(t).toContain('Три активных дня');
    expect(t).toMatch(/от предыдущего/);
  });

  it('names every module in adoption, including unused ones', () => {
    const t = page.text('#anAdoption');
    for (const label of ['Здоровье', 'Геолокация', 'Ассистент', 'SOS']) expect(t).toContain(label);
  });

  it('carries the cohort size next to every retention rate', () => {
    const t = page.text('#biRetention');
    expect(t).toContain('D1');
    expect(t).toContain('D30');
    expect(t.match(/когорта/g)?.length).toBe(3);
  });
});

describe('the overview stays operational', () => {
  it('reports live state and points at the analytics tab for the rest', async () => {
    const page = await render(FULL, 'overview');
    expect(page.errors).toEqual([]);
    const t = page.text('#kpis');
    expect(t).toContain('Устройств онлайн');
    expect(t).toContain('Тревог сегодня');
    // The product metrics moved wholesale. Showing retention or the funnel in
    // both places means eventually showing two different values for one thing.
    expect(t).not.toContain('Липкость');
    expect(t).not.toContain('Отток');
    expect(page.text('#overview')).toContain('Аналитика');
  });
});

describe('when the backend is older or absent', () => {
  it('degrades to a message per block instead of throwing', async () => {
    // A deploy is not atomic: this page can load against a backend that has
    // not been updated yet, and an older /admin/bi answers 200 with the newer
    // fields simply missing. Reading through them threw a TypeError and took
    // the entire tab down — a blank screen for a version skew lasting minutes.
    const old = { ...FULL } as Record<string, unknown>;
    delete old.growth;
    delete old.funnel;
    delete old.adoption;
    delete old.wauSeries;
    delete old.retentionCurve;

    const page = await render(old, 'analytics');
    expect(page.errors).toEqual([]);
    // The blocks that CAN still be computed are still shown.
    expect(page.text('#anKpis')).toContain('DAU');
    expect(page.count('#anKpis .kpi')).toBeGreaterThanOrEqual(5);
    expect(page.text('#biRetention')).toContain('D1');
    // The ones that cannot say so, rather than rendering an empty card.
    for (const sel of ['#anGrowth', '#anFunnel', '#anAdoption']) {
      expect(page.text(sel)).toMatch(/более старой версией/);
    }
  });

  it('says the endpoint is unavailable rather than inventing numbers', async () => {
    const page = await render(null, 'analytics');
    expect(page.errors).toEqual([]);
    expect(page.text('#anKpis')).toMatch(/недоступен/);
    for (const sel of ['#anGrowth', '#anFunnel', '#anAdoption', '#biRetention']) {
      expect(page.text(sel)).toMatch(/недоступен/);
    }
  });
});
