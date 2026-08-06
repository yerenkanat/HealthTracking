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

const LESSONS = {
  lessons: [
    {
      id: '11111111-1111-1111-1111-111111111111',
      course: 'mama',
      titleRu: 'Первые 40 дней',
      titleKk: 'Алғашқы 40 күн',
      youtubeUrl: 'https://youtu.be/aaaaaaaaaaa',
      summaryRu: 'Что происходит с телом и когда обращаться к врачу.',
      summaryKk: 'Денеде не болады және қашан дәрігерге бару керек.',
      sort: 10,
      published: true,
    },
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
        if (opts?.method === 'PUT' && p.includes('/admin/course/lessons')) {
          saved.push(JSON.parse(opts.body ?? '{}'));
          return { ok: true, status: 200, json: async () => ({ ok: true, id: 'new' }) };
        }
        const body = p.includes('/admin/course/lessons')
          ? LESSONS
          : p.includes('/admin/entitlements')
            ? { entitlements: [] }
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
