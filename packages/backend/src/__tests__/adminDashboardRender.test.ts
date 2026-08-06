/**
 * Render the Dashboard and read the numbers a person would act on.
 *
 * This screen is the one an owner opens first, and it is read to decide things
 * — order more stock, chase the unshipped orders, stop advertising in a city
 * nobody lives in. A number that renders wrong here is worse than one that
 * does not render at all: an empty card is obviously empty, while "выручка
 * 156 000 ₸" that quietly counts cancelled orders reads as a fact.
 *
 * So these assert on the painted text against a known snapshot, and — as much
 * as anything else — on what the screen says when there is nothing to show.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const SNAPSHOT = {
  asOf: '2026-08-06T10:00:00.000Z',
  users: { total: 240, newToday: 3, new7d: 19, new30d: 62, dau: 41, wau: 120, mau: 190, retentionD7: 0.34 },
  // Deliberately overlapping and NOT summing to 240 — a mother expecting her
  // second is in two of these rows.
  mothers: { pregnant: 90, mothers: 130, both: 22, unknown: 42 },
  children: {
    total: 150, boys: 80, girls: 65, unknown: 5, withDob: 140,
    byAge: [{ bucket: '0–1', count: 40 }, { bucket: '1–3', count: 55 },
      { bucket: '3–7', count: 30 }, { bucket: '7+', count: 15 }],
  },
  devices: { total: 96, online: 61, watches: 54, trackers: 42, unassigned: 7 },
  cities: [{ city: 'Алматы', users: 88 }, { city: 'Астана', users: 51 }, { city: 'Шымкент', users: 24 }],
  citiesUnknown: 77,
  commerce: {
    leads: { total: 34, new: 9 },
    orders: { total: 31, new: 4, confirmed: 3, shipped: 12, delivered: 10, cancelled: 2 },
    revenueMinor: 65_000_00,
    pipelineMinor: 12_400_00,
    avgOrderMinor: 2_954_00,
    stock: { units: 120, retailMinor: 200_000_00, costMinor: 130_000_00, unitsWithoutCost: 20 },
    lowStock: ['tracker'],
  },
  // Given to 40, opened by 25, finished by 9 — the fifteen who never pressed
  // play are the point of the card.
  course: { lessons: 12, granted: 40, started: 25, finished: 9, lessonsCompleted: 180, active7d: 14 },
};

/** Nothing has happened yet. Every card has to say so in its own words. */
const EMPTY = {
  asOf: '2026-08-06T10:00:00.000Z',
  users: { total: 0, newToday: 0, new7d: 0, new30d: 0, dau: 0, wau: 0, mau: 0, retentionD7: null },
  mothers: { pregnant: 0, mothers: 0, both: 0, unknown: 0 },
  children: { total: 0, boys: 0, girls: 0, unknown: 0, withDob: 0, byAge: [] },
  devices: { total: 0, online: 0, watches: 0, trackers: 0, unassigned: 0 },
  cities: [], citiesUnknown: 0,
  commerce: {
    leads: { total: 0, new: 0 },
    orders: { total: 0, new: 0, confirmed: 0, shipped: 0, delivered: 0, cancelled: 0 },
    revenueMinor: 0, pipelineMinor: 0, avgOrderMinor: null,
    stock: { units: 0, retailMinor: 0, costMinor: 0, unitsWithoutCost: 0 },
    lowStock: [],
  },
  course: { lessons: 0, granted: 0, started: 0, finished: 0, lessonsCompleted: 0, active7d: 0 },
};

interface Page {
  text(sel: string): string;
  errors: string[];
  window: JSDOM['window'];
}

/** `null` for the snapshot means /admin/dashboard answers 500. */
async function render(snapshot: unknown): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
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
        if (p.includes('/admin/dashboard')) {
          return snapshot === null
            ? { ok: false, status: 500, json: async () => ({}) }
            : { ok: true, status: 200, json: async () => snapshot };
        }
        const body = p.includes('/admin/stats')
          ? { activeUsers: 0, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0, alertsConfigured: true }
          : p.includes('/admin/emergencies')
            ? { emergencies: [] }
            : p.includes('/admin/bi')
              ? null
              : { };
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 350));

  return {
    window,
    errors,
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
  };
}

describe('the Dashboard', () => {
  let page: Page;
  beforeAll(async () => { page = await render(SNAPSHOT); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('is called Dashboard, in the header and in the sidebar', () => {
    expect(page.text('#pageTitle')).toBe('Dashboard');
    expect(page.text('[data-view="overview"]')).toContain('Dashboard');
  });

  it('leads with the four numbers a business is run on', () => {
    const t = page.text('#dashKpis');
    expect(t).toContain('240');          // users
    expect(t).toContain('65 000 ₸');     // revenue, shipped only
    expect(t).toContain('96');           // devices in families
    // Orders still to ship, and what they are worth.
    expect(t).toContain('12 400 ₸');
  });

  it('shows pregnancy and motherhood as overlapping, not as a split', () => {
    const t = page.text('#dashAudience');
    expect(t).toContain('Ждут ребёнка');
    expect(t).toContain('90');
    expect(t).toContain('Уже мамы');
    expect(t).toContain('130');
    // 90 + 130 + 42 > 240, and the card has to say why rather than leave a
    // reader to conclude the arithmetic is broken.
    expect(t).toMatch(/не складываются|обе строки/i);
  });

  it('breaks children down by sex and by age', () => {
    const t = page.text('#dashKids');
    expect(t).toContain('Мальчики');
    expect(t).toContain('80');
    expect(t).toContain('Девочки');
    expect(t).toContain('65');
    expect(t).toContain('0–1');
    // Ages are over the 140 with a date of birth, not over all 150.
    expect(t).toContain('140');
  });

  it('ranks the cities and admits how many gave none', () => {
    const t = page.text('#dashCities');
    expect(t).toContain('Алматы');
    expect(t).toContain('88');
    expect(t).toContain('Не указан');
    expect(t).toContain('77');
  });

  it('splits the fleet into watches and trackers, and flags idle trackers', () => {
    const t = page.text('#dashDevices');
    expect(t).toContain('Часы мамы');
    expect(t).toContain('54');
    expect(t).toContain('Детские трекеры');
    expect(t).toContain('42');
    // A tracker paired to no child is watching nobody, and every other count
    // on this page treats it as coverage.
    expect(t).toContain('Трекер без ребёнка');
    expect(t).toContain('7');
  });

  it('counts revenue as what shipped, and says so', () => {
    const t = page.text('#dashCommerce');
    expect(t).toContain('65 000 ₸');
    expect(t).toContain('Отменены');
    expect(t).toMatch(/новый заказ.*звонок/i);
  });

  it('reports margin only over stock whose cost is known', () => {
    const t = page.text('#dashStock');
    expect(t).toContain('120');           // units
    expect(t).toContain('200 000 ₸');     // at retail
    expect(t).toContain('130 000 ₸');     // at cost
    expect(t).toContain('70 000 ₸');      // the margin between them
    // 20 of the 120 have no cost recorded, so the figure is partial and must
    // not be presented as the whole picture.
    expect(t).toMatch(/100 единицам из 120/);
    expect(t).toContain('tracker');       // running out
  });
});

describe('an empty business', () => {
  let page: Page;
  beforeAll(async () => { page = await render(EMPTY); });

  it('says what is empty rather than painting zeroes', () => {
    expect(page.text('#dashKids')).toMatch(/Детей.*пока нет/i);
    expect(page.text('#dashDevices')).toMatch(/устройство.*не подключено/i);
    expect(page.text('#dashCommerce')).toMatch(/Заказов и заявок пока нет/i);
    expect(page.text('#dashStock')).toMatch(/склад.*пусто/i);
  });

  it('does not claim an average order value of zero', () => {
    // 0 ₸ would read as "we sell things and get nothing for them".
    expect(page.text('#dashKpis')).toMatch(/продаж ещё не было/i);
  });
});

/// The course, as a business fact.
///
/// The комплект charges 9 200 ₸ over the two devices for this course, and the
/// dashboard could say what was sold and never whether it was used. Sold is
/// not used, and only one of those is evidence the premium is worth paying.
describe('the course card', () => {
  let page: Page;
  beforeAll(async () => { page = await render(SNAPSHOT); });

  it('shows access against use, not access alone', () => {
    const t = page.text('#dashCourse');
    expect(t).toContain('40');   // granted
    expect(t).toContain('25');   // started
    expect(t).toContain('9');    // finished
  });

  it('names the fifteen who have never pressed play', () => {
    // granted − started. The number that is a task rather than a statistic,
    // and the one nobody could see before: these customers paid for a course
    // and have not opened it.
    const t = page.text('#dashCourse');
    expect(t).toContain('Ни одного урока');
    expect(t).toContain('15');
    expect(t).toMatch(/стоит написать/i);
  });

  it('says nothing is sold yet rather than painting a wall of zeroes', async () => {
    const p = await render({
      ...SNAPSHOT,
      course: { lessons: 12, granted: 0, started: 0, finished: 0, lessonsCompleted: 0, active7d: 0 },
    });
    expect(p.text('#dashCourse')).toMatch(/никому не открыт/i);
  });

  it('says there are no lessons rather than blaming the customers', async () => {
    // 40 people with access and nothing to watch is our problem, not theirs.
    const p = await render({
      ...SNAPSHOT,
      course: { lessons: 0, granted: 40, started: 0, finished: 0, lessonsCompleted: 0, active7d: 0 },
    });
    expect(p.text('#dashCourse')).toMatch(/Уроков ещё нет/i);
  });

  it('does not take the rest of the screen down on an older backend', async () => {
    // A server one deploy behind answers a snapshot with no `course` key. That
    // must grey out this card and leave every other one alone.
    const withoutCourse: Record<string, unknown> = { ...SNAPSHOT };
    delete withoutCourse.course;
    const p = await render(withoutCourse);

    expect(p.errors).toEqual([]);
    expect(p.text('#dashCourse')).toMatch(/недоступна/i);
    expect(p.text('#dashCommerce'), 'the commerce card went down with it')
      .toContain('65 000 ₸');
  });
});

describe('when the backend answers something else', () => {
  it('survives a 200 that is not a snapshot', async () => {
    // A backend one deploy behind, or any handler that answers `{}`, passed
    // the truthiness check and then threw inside the first card — taking the
    // whole screen down, not just the card.
    const page = await render({ users: { total: 5 } });
    expect(page.errors).toEqual([]);
    expect(page.text('#dashCommerce')).toMatch(/недоступна/i);
  });
});

describe('when the snapshot cannot be loaded', () => {
  let page: Page;
  beforeAll(async () => { page = await render(null); });

  it('says the data is missing instead of showing zeroes as facts', async () => {
    // The failure mode this guards: a dashboard that renders 0 ₸ revenue and
    // 0 users because a request failed is indistinguishable from a business
    // that has none, and somebody acts on it.
    for (const sel of ['#dashAudience', '#dashKids', '#dashCities', '#dashDevices', '#dashCommerce', '#dashStock', '#dashCourse']) {
      expect(page.text(sel), sel).toMatch(/недоступна/i);
    }
  });
});
