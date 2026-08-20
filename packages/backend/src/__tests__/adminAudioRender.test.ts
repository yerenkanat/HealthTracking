/**
 * Render the admin panel's «Ежедневное аудио» tab for real (jsdom) — frames 17
 * and 17a.
 *
 * The tab used to be a flat list and an upload box: nothing said how much of
 * the calendar was covered, how much of it existed in Kazakh, or which days
 * were still missing. This checks the three things that replaced that, and it
 * checks them against numbers COMPUTED from the fixture rather than against
 * numbers typed into the panel — a metric this test agrees with because both
 * sides hard-code «64» would be worse than no metric.
 *
 * Two claims the schedule must NOT make are asserted as absences: it prints no
 * calendar date (the table stores a day of pregnancy / day of life, and the
 * server has no due date to turn one into a date), and it never says an empty
 * run switches the block off in the app — there is no such rule and the schema
 * cannot express one.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** What GET /admin/audio?track=pregnancy answers with, shaped like DailyAudioMeta. */
const RU_DAYS = [1, 2, 3, 5, 8, 13];
const KK_DAYS = [1, 2];
const AUDIO = [
  ...RU_DAYS.map((day) => ({ track: 'pregnancy', day, locale: 'ru', title: `День ${day} · о малыше`, mime: 'audio/mpeg', size: 51200, updatedAt: '2026-08-01T10:00:00.000Z' })),
  ...KK_DAYS.map((day) => ({ track: 'pregnancy', day, locale: 'kk', title: null, mime: 'audio/mpeg', size: 40960, updatedAt: '2026-08-01T10:00:00.000Z' })),
];

const WINDOW = 21;
/** Holes BELOW the furthest published day — what «дней без записи» counts. */
const holes = (days: number[]) => Math.max(0, Math.max(...days) - new Set(days).size);

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  value(sel: string): string;
  /** Make GET /admin/audio answer 500 from now on, as a dropped connection does. */
  breakAudio(broken: boolean): void;
  errors: string[];
  rejections: string[];
  window: import('jsdom').DOMWindow;
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function boot(): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const rejections: string[] = [];
  // Flipped by breakAudio(). Everything else keeps answering, so the failure
  // under test is the list read and nothing else.
  let audioBroken = false;
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  process.on('unhandledRejection', (r) => rejections.push(String(r)));
  const settle = panelSettle();
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
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      settle.attach(window as never, async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/audio')) {
          if (audioBroken) {
            return { ok: false, status: 500, text: async () => 'boom', json: async () => ({}) };
          }
          // The panel asks per track; only «Беременность» has anything.
          return { ok: true, status: 200, json: async () => ({ audio: p.includes('track=pregnancy') ? AUDIO : [] }) };
        }
        return { ok: true, status: 200, json: async () => ({}) };
      });
    },
  });
  const { window } = dom;
  await settle.quiet('boot');
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    value: (sel) => (window.document.querySelector(sel) as { value?: string } | null)?.value ?? '',
    breakAudio: (broken) => { audioBroken = broken; },
    errors,
    rejections,
    window,
    quiet: settle.quiet,
  };
}

async function click(page: Rendered, sel: string) {
  const el = page.window.document.querySelector(sel);
  if (!el) throw new Error(`nothing to click at ${sel}`);
  el.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet(`the click on ${sel}`);
}

describe('admin «Ежедневное аудио» tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="audio"]');
  });

  it('boots without throwing or rejecting', () => {
    expect(page.errors).toEqual([]);
    expect(page.rejections).toEqual([]);
  });

  it('counts recordings, Kazakh coverage and gaps from the rows it was served', () => {
    const metrics = page.text('#audMetrics');
    expect(page.count('#audMetrics .kpi')).toBe(3);
    // «записей» — BOTH locales together, said so on the tile.
    expect(metrics).toContain('Записей');
    expect(metrics).toContain(String(AUDIO.length));
    expect(metrics).toContain(`RU ${RU_DAYS.length} · ҚАЗ ${KK_DAYS.length}`);
    // «12 из 64 на казахском» — computed, and out of the real total.
    expect(metrics).toContain('На казахском');
    expect(metrics).toContain(`${KK_DAYS.length} из ${AUDIO.length} записей трека`);
    // «дней без записи» — holes below the furthest published day (13 − 6 = 7).
    expect(metrics).toContain('Дней без записи');
    expect(metrics).toContain(String(holes(RU_DAYS)));
    expect(metrics).toContain(`пропуски между 1 и ${Math.max(...RU_DAYS)} днём`);
  });

  it('draws a 21-day window of DAY NUMBERS, empty days amber', () => {
    expect(page.count('#audGrid .aud-day')).toBe(WINDOW);
    // 1,2,3,5,8,13 are inside the first window.
    expect(page.count('#audGrid .aud-day.has')).toBe(RU_DAYS.length);
    expect(page.count('#audGrid .aud-day.gap')).toBe(WINDOW - RU_DAYS.length);
    expect(page.text('#audWindow')).toBe(`Дни 1–${WINDOW}`);
  });

  it('prints no calendar date anywhere on the schedule', () => {
    // The schema stores a day of pregnancy / day of life. Deriving «14 августа»
    // from it would need a due date this panel does not have.
    const text = page.text('#audSchedule');
    expect(text).not.toMatch(/\d{1,2}[./]\d{1,2}[./]\d{2,4}/);
    expect(text).not.toMatch(/20\d\d-\d\d-\d\d/);
    expect(text).not.toMatch(/январ|феврал|март|апрел|мая|июн|июл|август|сентябр|октябр|ноябр|декабр/i);
  });

  it('states its rule, and does not claim empty days switch the block off', () => {
    const note = page.text('#audGridNote');
    expect(note).toContain(`жёлтым — ${WINDOW - RU_DAYS.length} дней без записи`);
    expect(note).toContain('а не даты');
    // The spec's «три пустых дня отключают блок» is not a rule this product
    // has, so the panel must not imply it.
    expect(note).toContain('блок в приложении от этого не отключается');
  });

  it('clicking a day loads the upload form for that day', async () => {
    await click(page, '#audGrid .aud-day[data-audday="5"]');
    expect(page.value('#audDay')).toBe('5');
    // An existing title comes back too, so replacing a clip cannot silently
    // blank the name it was published under.
    expect(page.value('#audTitle')).toBe('День 5 · о малыше');
    expect(page.text('#audMsg')).toContain('заменит существующую запись');

    await click(page, '#audGrid .aud-day[data-audday="7"]');
    expect(page.value('#audDay')).toBe('7');
    expect(page.text('#audMsg')).not.toContain('заменит');
  });

  it('pages the window forward and back, and home', async () => {
    await click(page, '#audNext');
    expect(page.text('#audWindow')).toBe(`Дни ${WINDOW + 1}–${WINDOW * 2}`);
    expect(page.count('#audGrid .aud-day.gap')).toBe(WINDOW); // nothing recorded that far out
    await click(page, '#audPrev');
    expect(page.text('#audWindow')).toBe(`Дни 1–${WINDOW}`);
    await click(page, '#audNext');
    await click(page, '#audStart');
    expect(page.text('#audWindow')).toBe(`Дни 1–${WINDOW}`);
  });

  it('recounts everything when the language changes', async () => {
    await click(page, '#audLocale button[data-locale="kk"]');
    const metrics = page.text('#audMetrics');
    // The total is language-independent; the gaps are not.
    expect(metrics).toContain(String(AUDIO.length));
    expect(metrics).toContain('язык KK');
    expect(page.count('#audGrid .aud-day.has')).toBe(KK_DAYS.length);
    expect(page.text('#audGridNote')).toContain('язык KK');
    // …and the list under it follows.
    expect(page.count('#audList .arow')).toBe(KK_DAYS.length);
  });

  it('an empty track reads as empty, not as the previous track\'s numbers', async () => {
    // «Развитие ребёнка» is served an empty list here — a real answer, not a
    // failure. It must read as empty rather than keeping «Записей 8» standing.
    await click(page, '#audLocale button[data-locale="ru"]');
    await click(page, '#audTrack button[data-track="child"]');
    expect(page.text('#audMetrics')).toContain('записей пока нет');
    expect(page.count('#audGrid .aud-day.has')).toBe(0);
    expect(page.count('#audGrid .aud-day.gap')).toBe(WINDOW);
    expect(page.text('#audList')).toContain('Пока нет аудио');
  });

  it('says so, and blanks the tiles, when the list cannot be read at all', async () => {
    // The case above never reaches renderAudio's catch: an empty list is a
    // successful read. THIS one is the failure — /admin/audio 500s while she
    // switches track, which is when the previous track's «Записей 8» and «Дней
    // без записи 7» would otherwise stay on screen under the new heading and be
    // read as the new calendar's coverage.
    await click(page, '#audTrack button[data-track="pregnancy"]');
    expect(page.text('#audMetrics')).toContain(String(AUDIO.length)); // numbers on screen…

    page.breakAudio(true);
    await click(page, '#audTrack button[data-track="child"]');
    try {
      expect(page.text('#audList')).toContain('Не удалось загрузить аудио');
      // Not a single number survives: no tile, no day, no window range.
      expect(page.text('#audMetrics')).toBe('');
      expect(page.count('#audMetrics .kpi')).toBe(0);
      expect(page.count('#audGrid .aud-day')).toBe(0);
      expect(page.text('#audWindow')).toBe('—');
      // And it explains WHY the schedule is empty, rather than reading as a
      // calendar with nothing published in it.
      expect(page.text('#audGridNote')).toContain('не загрузился');
      // A failed read must not throw either — the tab stays usable.
      expect(page.errors).toEqual([]);
    } finally {
      page.breakAudio(false);
    }
  });

  it('recovers when the server answers again', async () => {
    // The blanking is not a dead end: the next successful read repopulates.
    await click(page, '#audTrack button[data-track="pregnancy"]');
    expect(page.count('#audMetrics .kpi')).toBe(3);
    expect(page.count('#audGrid .aud-day')).toBe(WINDOW);
    expect(page.text('#audWindow')).toBe(`Дни 1–${WINDOW}`);
  });
});
