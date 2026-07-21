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

/** What GET /admin/users really answers — one real person, not six invented. */
const USERS = {
  total: 1,
  users: [
    {
      id: '11111111-1111-1111-1111-111111111111',
      displayName: 'Айгерим',
      phone: '+77001112233',
      dueDate: '2026-11-14T00:00:00.000Z',
      lastMetricAt: '2026-07-21T11:30:00.000Z',
    },
  ],
};

const AUDIT = {
  audit: [
    { staffId: 's1', action: 'view_health', target: 'Айгерим', at: '2026-07-21T09:41:00.000Z' },
    { staffId: 's2', action: 'list_users', target: null, at: '2026-07-21T09:31:00.000Z' },
  ],
};

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

/**
 * Load the panel, let it boot, click through to [view], return its text.
 *
 * [down] names path fragments whose requests should fail, so a test can take
 * one endpoint away without taking the whole panel with it.
 */
async function render(bi: unknown, view: string, down: string[] = []): Promise<Rendered> {
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
        if (down.some((d) => p.includes(d))) {
          return { ok: false, status: 500, json: async () => ({}) };
        }
        const body = p.includes('/admin/bi')
          ? bi
          : p.includes('/admin/analytics')
            ? ANALYTICS
            : p.includes('/admin/users')
              ? USERS
              : p.includes('/admin/audit')
                ? AUDIT
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
    for (const label of ['Новые', 'Вернулись', 'Остались', 'Ушли', 'Чистое изменение']) {
      expect(t).toContain(label);
    }
    // "Остались" is the base that stayed, not a movement, so it carries no
    // sign. It used to render as "=73", an equation missing a side.
    expect(t).not.toMatch(/=\s*\d/);
  });

  it('shows the funnel loss BETWEEN the stages, not inside a label', () => {
    const t = page.text('#anFunnel');
    expect(t).toContain('Зарегистрировались');
    expect(t).toContain('Три активных дня');
    // The drop is its own element between two rows. Concatenated into the
    // lower stage's label it read "Первое действие 97% от предыдущего" — one
    // run-on line that hid where users are actually lost.
    expect(page.count('#anFunnel .fdrop')).toBe(3); // one between each pair
    expect(t).toMatch(/дошли/);
    const label = page.text('#anFunnel .mrow-label');
    expect(label).not.toMatch(/%/);
  });

  it('puts every figure in a tabular column, not inline with the words', () => {
    // Values were pasted next to the label as ordinary prose, so nothing lined
    // up down the card and the numbers could not be compared by eye.
    expect(page.count('#anGrowth .mrow-value')).toBeGreaterThan(3);
    expect(page.count('#anAdoption .mrow-value')).toBeGreaterThan(3);
  });

  it('defers the how-it-is-counted prose behind a disclosure', () => {
    // Every card carried a paragraph above or below its data. True, and worth
    // keeping — but read daily by people who learned it once, so it pushed the
    // numbers down and got skipped. Closed by default, same place every time.
    for (const sel of ['#anGrowth', '#anFunnel', '#anAdoption']) {
      expect(page.count(`${sel} details.note`), `${sel} lost its rationale`).toBe(1);
      expect(page.count(`${sel} details.note[open]`), `${sel} opens it unasked`).toBe(0);
    }
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

describe('the tabs that were showing invented data', () => {
  // GET /admin/users and GET /admin/audit both existed, were authorized and
  // audited — and the panel called neither. Both tabs rendered hardcoded
  // arrays, in Live mode as well as demo. Someone searching for a patient who
  // had just phoned would be told she does not exist, and the audit log — the
  // record of which staff member opened which woman's data — showed five lines
  // that existed nowhere but the browser tab.
  it('the user list comes from the server', async () => {
    const page = await render(FULL, 'users');
    expect(page.errors).toEqual([]);
    const t = page.text('#usersBody');
    expect(t).toContain('Айгерим');
    expect(t).toContain('+77001112233');
    // The six demo names must not appear once a real answer exists.
    for (const invented of ['Madina', 'Zarina', 'Aruzhan', 'Saltanat']) {
      expect(t).not.toContain(invented);
    }
  });

  it('dates in the user list are in the language the panel is written in', async () => {
    const page = await render(FULL, 'users');
    const t = page.text('#usersBody');
    expect(t).toContain('ноя 2026'); // not "Nov 2026"
    expect(t).toMatch(/назад|только что/); // not "18m ago"
    expect(t).not.toMatch(/\b(Nov|Sep|Jan|Oct|Dec|Feb)\b/);
    expect(t).not.toMatch(/\d+[mh] ago/);
  });

  it('the audit log is the audit log', async () => {
    const page = await render(FULL, 'audit');
    expect(page.errors).toEqual([]);
    const t = page.text('#auditBody');
    // A phrase a person reads, not the wire code.
    expect(t).toContain('Открыл(а) медданные');
    expect(t).not.toContain('view_health');
    // A bare "09:41" is unambiguous only until tomorrow exists.
    expect(t).toMatch(/\d{2}\.\d{2}\s+\d{2}:\d{2}/);
  });

  it('every table-backed tab renders SOMETHING, not a bare header', async () => {
    // The page is two IIFEs that cannot see each other's declarations. Calling
    // a helper across that boundary throws a ReferenceError inside an async
    // loader, where nothing surfaces it — the tab simply paints its header and
    // no rows, which is indistinguishable from "no data". That is exactly how
    // the Устройства tab looked while it was broken, and no assertion here
    // noticed, because none of them looked at it.
    for (const [view, sel] of [
      ['devices', '#devicesBody'],
      ['safety', '#safetyBody'],
      ['users', '#usersBody'],
      ['audit', '#auditBody'],
    ] as const) {
      const page = await render(FULL, view);
      expect(page.errors, `${view} threw`).toEqual([]);
      expect(page.text(sel).length, `${view} rendered no row at all`).toBeGreaterThan(0);
    }
  });

  it('says when a list could not be loaded, rather than showing it as empty', async () => {
    // Blank-because-loading, blank-because-empty and blank-because-failed were
    // one blank screen. A back-office that cannot reach its API must not look
    // like a product with no users.
    const page = await render(FULL, 'users', ['/admin/users']);
    expect(page.errors).toEqual([]);
    expect(page.text('#usersBody')).toMatch(/Не удалось загрузить/);
    // And the rest of the panel is untouched by one endpoint being down.
    expect(page.text('#kpis')).toContain('Устройств онлайн');
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
