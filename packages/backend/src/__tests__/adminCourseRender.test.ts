/**
 * Render the Курс Ма!Ма! tab and author a lesson the way staff would.
 *
 * The course is what makes the комплект worth 39 000 ₸ rather than 29 800, so
 * this form is where that difference is actually produced. It had no field for
 * the lesson summary — the API has accepted summaryRu/summaryKk since the
 * course shipped and the app renders it under every lesson title, but there was
 * nowhere to type one. Every lesson went out as a bare title, and the feature
 * looked like it did not exist.
 *
 * "The markup contains an input" proves nothing here: what matters is what the
 * PUT carries and what comes back into the form when a lesson is edited.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const lesson = (id: string, titleRu: string, sort: number) => ({
  id,
  course: 'mama',
  titleRu,
  titleKk: null,
  youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
  summaryRu: null,
  summaryKk: null,
  sort,
  published: true,
});

const LESSONS = {
  lessons: [
    {
      id: '11111111-1111-1111-1111-111111111111',
      course: 'mama',
      titleRu: 'Первые 40 дней',
      titleKk: 'Алғашқы 40 күн',
      youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
      summaryRu: 'Что происходит с телом и когда обращаться к врачу.',
      summaryKk: 'Денеде не болады және қашан дәрігерге бару керек.',
      sort: 10,
      published: true,
    },
    lesson('22222222-2222-2222-2222-222222222222', 'Грудное вскармливание', 20),
    lesson('33333333-3333-3333-3333-333333333333', 'Сон малыша', 30),
    // A draft. Nobody can watch it, so nobody's progress may be measured
    // against it — three published lessons is the denominator, not four.
    { ...lesson('44444444-4444-4444-4444-444444444444', 'Черновик', 40), published: false },
  ],
};

/// Three customers who bought the same thing and did three different things
/// with it: one finished it, one opened one lesson and stopped, one has never
/// pressed play. Telling those apart is the entire point of the column.
const ENTITLEMENTS = {
  entitlements: [
    { phone: '77001112233', feature: 'mama_course', orderId: null, grantedBy: 's', note: 'заказ', at: '2026-07-01T10:00:00.000Z' },
    { phone: '77002223344', feature: 'mama_course', orderId: null, grantedBy: 's', note: null, at: '2026-07-02T10:00:00.000Z' },
    { phone: '77003334455', feature: 'mama_course', orderId: null, grantedBy: 's', note: null, at: '2026-07-03T10:00:00.000Z' },
  ],
};

const PROGRESS = {
  progress: [
    { phone: '77001112233', started: 3, completed: 3, lastLessonId: '33333333-3333-3333-3333-333333333333', lastLessonTitle: 'Сон малыша', lastAt: '2026-07-20T09:00:00.000Z' },
    { phone: '77002223344', started: 1, completed: 0, lastLessonId: '11111111-1111-1111-1111-111111111111', lastLessonTitle: 'Первые 40 дней', lastAt: '2026-07-05T09:00:00.000Z' },
  ],
};

interface Page {
  window: JSDOM['window'];
  errors: string[];
  saved: Array<Record<string, unknown>>;
  $: (sel: string) => HTMLElement | null;
}

async function render(): Promise<Page> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const saved: Array<Record<string, unknown>> = [];
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
      window.fetch = (async (path: string, opts?: { method?: string; body?: string }) => {
        const p = String(path);
        // Who is signed in. Without this the panel ran with an empty role,
        // which no real session produces — and the course tab is now two
        // capability-guarded cards (`content` for the lessons, `orders` for
        // the access list), so an empty role draws neither.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен' }) };
        }
        if (opts?.method === 'PUT' && p.includes('/admin/course/lessons')) {
          saved.push(JSON.parse(opts.body ?? '{}'));
          return { ok: true, status: 200, json: async () => ({ ok: true, id: 'new' }) };
        }
        if (p.includes('/admin/course/progress')) {
          return { ok: true, status: 200, json: async () => PROGRESS };
        }
        const body = p.includes('/admin/course/lessons')
          ? LESSONS
          : p.includes('/admin/entitlements')
            ? ENTITLEMENTS
            : { };
        return { ok: true, status: 200, json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(120);
  window.document.querySelector('[data-view="course"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(250);

  return {
    window,
    errors,
    saved,
    $: (sel) => window.document.querySelector(sel),
  };
}

function type(page: Page, id: string, value: string): void {
  const el = page.$('#' + id) as HTMLInputElement;
  el.value = value;
  el.dispatchEvent(new page.window.Event('input', { bubbles: true }));
}

const submit = (page: Page) =>
  page.$('#lessonForm')!.dispatchEvent(
    new page.window.Event('submit', { bubbles: true, cancelable: true }));

describe('authoring a lesson', () => {
  let page: Page;
  beforeEach(async () => { page = await render(); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('has somewhere to type the summary the app shows', async () => {
    // The field the app renders under every title. Without it the лесson list
    // in the app is a column of bare names.
    expect(page.$('#lessonSummary'), 'no Russian summary field').not.toBeNull();
    expect(page.$('#lessonSummaryKk'), 'no Kazakh summary field').not.toBeNull();
  });

  it('sends the summary with the lesson', async () => {
    type(page, 'lessonTitle', 'Первые 40 дней');
    type(page, 'lessonUrl', 'https://youtu.be/aaaaaaaaaaa');
    type(page, 'lessonSummary', 'Что происходит с телом.');
    type(page, 'lessonSummaryKk', 'Денеде не болады.');
    submit(page);
    await new Promise((r) => setTimeout(r, 60));

    expect(page.saved).toHaveLength(1);
    expect(page.saved[0].summaryRu).toBe('Что происходит с телом.');
    expect(page.saved[0].summaryKk).toBe('Денеде не болады.');
  });

  /// Checking the link before it reaches a paying customer.
  ///
  /// A mistyped or simply wrong URL saved cleanly, published, and failed in
  /// the app — where the person who can fix it never sees it. YouTube's own
  /// still for the id is the cheapest possible check: if the right video
  /// appears, the link is right.
  describe('the link preview', () => {
    it('shows the video the link points at', async () => {
      type(page, 'lessonUrl', 'https://youtu.be/dQw4w9WgXcQ');
      await new Promise((r) => setTimeout(r, 30));

      expect((page.$('#lessonPreview') as HTMLElement).hidden).toBe(false);
      expect((page.$('#lessonThumb') as HTMLImageElement).getAttribute('src'))
        .toBe('https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg');
      expect((page.$('#lessonOpen') as HTMLAnchorElement).getAttribute('href'))
        .toBe('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    it('reads the id out of every shape a person pastes', async () => {
      for (const url of [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      ]) {
        type(page, 'lessonUrl', url);
        await new Promise((r) => setTimeout(r, 20));
        expect((page.$('#lessonThumb') as HTMLImageElement).getAttribute('src'),
          url).toContain('dQw4w9WgXcQ');
      }
    });

    it('says so when the link is not a video at all', async () => {
      // A channel page and a playlist both used to save cleanly.
      type(page, 'lessonUrl', 'https://www.youtube.com/@anabala');
      await new Promise((r) => setTimeout(r, 30));

      expect((page.$('#lessonPreview') as HTMLElement).hidden).toBe(false);
      expect(page.$('#lessonPreviewMsg')!.textContent).toMatch(/не ссылка на конкретное видео/i);
      expect((page.$('#lessonThumb') as HTMLImageElement).hasAttribute('src')).toBe(false);
    });

    it('shows nothing at all before anything is typed', async () => {
      expect((page.$('#lessonPreview') as HTMLElement).hidden).toBe(true);
    });
  });

  /// Putting the lessons in order.
  ///
  /// A course is a sequence, and ordering it meant typing sort numbers —
  /// working out that "between 20 and 30" is 25 to slip a lesson in, for
  /// thirty of them. The numbers are still there for a wholesale renumber;
  /// day to day it is a pair of arrows.
  describe('reordering', () => {
    it('shows position, not the raw sort value', async () => {
      // 10 / 20 / 30 tells a reader nothing about which is second.
      const list = page.$('#lessonList')!.textContent ?? '';
      expect(list).toContain('1');
      expect(list).toContain('2');
    });

    it('cannot move the first lesson up or the last one down', async () => {
      const ups = page.window.document.querySelectorAll('.lup');
      const downs = page.window.document.querySelectorAll('.ldn');
      expect((ups[0] as HTMLButtonElement).disabled, 'the first can move up').toBe(true);
      expect((downs[downs.length - 1] as HTMLButtonElement).disabled,
        'the last can move down').toBe(true);
    });

    it('swaps a lesson with the one below it', async () => {
      // Second row down: it and the third swap sort values.
      const downs = page.window.document.querySelectorAll('.ldn');
      (downs[1] as HTMLElement).dispatchEvent(
        new page.window.MouseEvent('click', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 80));

      expect(page.saved).toHaveLength(2);
      const byId = Object.fromEntries(page.saved.map((s) => [s.id, s.sort]));
      expect(byId['22222222-2222-2222-2222-222222222222']).toBe(30);
      expect(byId['33333333-3333-3333-3333-333333333333']).toBe(20);
    });

    it('carries the rest of the lesson through the move', async () => {
      // The save is a full upsert, so a move that forgot a field would blank
      // the title or unpublish the lesson.
      const downs = page.window.document.querySelectorAll('.ldn');
      (downs[0] as HTMLElement).dispatchEvent(
        new page.window.MouseEvent('click', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 80));

      const moved = page.saved.find((s) => s.id === '11111111-1111-1111-1111-111111111111')!;
      expect(moved.titleRu).toBe('Первые 40 дней');
      expect(moved.summaryRu).toBe('Что происходит с телом и когда обращаться к врачу.');
      expect(moved.published).toBe(true);
      expect(moved.youtubeUrl).toBe('https://youtu.be/dQw4w9WgXcQ');
    });
  });

  /// Who is actually watching what they bought.
  ///
  /// Access answers "did she pay". It never answered the question the
  /// комплект's 9 200 ₸ premium rests on: is she watching it. Somebody handed
  /// the course three weeks ago who has opened nothing is a call worth making,
  /// and that row was indistinguishable from every other row.
  describe('progress beside access', () => {
    const rows = (page: Page) =>
      [...page.window.document.querySelectorAll('#entBody tr')] as HTMLElement[];

    it('shows how far each customer has got', async () => {
      const cells = rows(page).map((r) => r.textContent ?? '');
      expect(cells[0], 'the one who finished').toContain('3 / 3');
      expect(cells[1], 'the one who opened one lesson').toContain('0 / 3');
    });

    it('says outright that somebody has never started', async () => {
      // The row that matters most, and the one an empty cell would hide: blank
      // reads as "no data" and gets scrolled past.
      expect(rows(page)[2].textContent).toMatch(/не начинала/i);
    });

    it('distinguishes opened from watched through', async () => {
      // 0 finished out of 8 opened is a different customer from 0 out of 0.
      expect(rows(page)[1].textContent).toMatch(/начато 1/i);
      expect(rows(page)[0].textContent, 'nothing to add when they match')
        .not.toMatch(/начато/i);
    });

    it('names the last lesson she was on, and when', async () => {
      expect(rows(page)[0].textContent).toContain('Сон малыша');
      expect(rows(page)[1].textContent).toContain('Первые 40 дней');
    });

    it('counts against published lessons only', async () => {
      // Four lessons exist; one is a draft nobody can watch. Counting it would
      // show every customer permanently behind, for a reason no one can see.
      const done = rows(page)[0].textContent ?? '';
      expect(done).toContain('3 / 3');
      expect(done, 'the draft was counted').not.toContain('3 / 4');
    });

    it('still draws the access list when progress is unavailable', async () => {
      // The older half of this table is the more important one. A server not
      // yet migrated 404s the progress route, and "who has access" must survive
      // that rather than going blank.
      const html = readFileSync(PANEL, 'utf8');
      const dom = new JSDOM(html, {
        runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin',
        beforeParse(window) {
          window.HTMLCanvasElement.prototype.getContext = (() => null) as never;
          window.scrollTo = () => {};
          window.fetch = (async (path: string) => {
            const p = String(path);
            if (p.includes('/admin/me')) {
              return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен' }) };
            }
            if (p.includes('/admin/course/progress')) {
              return { ok: false, status: 404, json: async () => ({ error: 'not_found' }) };
            }
            const body = p.includes('/admin/course/lessons') ? LESSONS
              : p.includes('/admin/entitlements') ? ENTITLEMENTS : {};
            return { ok: true, status: 200, json: async () => body };
          }) as never;
        },
      });
      const w = dom.window;
      await new Promise((r) => setTimeout(r, 120));
      w.document.querySelector('[data-view="course"]')!
        .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
      await new Promise((r) => setTimeout(r, 250));

      const body = w.document.querySelector('#entBody')!.textContent ?? '';
      expect(body, 'the access list went blank').toContain('77001112233');
      expect(body).toMatch(/не начинала/i);
    });
  });

  it('sends null rather than an empty string when it is left blank', async () => {
    // The column is nullable and the app checks for null; '' would render an
    // empty second line under the title.
    type(page, 'lessonTitle', 'Урок без описания');
    type(page, 'lessonUrl', 'https://youtu.be/bbbbbbbbbbb');
    submit(page);
    await new Promise((r) => setTimeout(r, 60));

    expect(page.saved[0].summaryRu).toBeNull();
    expect(page.saved[0].summaryKk).toBeNull();
  });
});
