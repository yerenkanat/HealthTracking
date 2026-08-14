/**
 * Admin frame 16a — «Новая статья», rendered by a browser rather than read.
 *
 * contentArticle.test.ts proves the server stores and gates an article. This
 * proves somebody can WRITE one: the boxes exist, they are filled with what was
 * saved, and what is typed into them arrives in the PUT.
 *
 * The middle claim is the one that cannot be checked by reading the file. The
 * editor collected fields with `querySelectorAll("input[data-f], select[data-f]")`
 * — a selector that does not match a textarea. Every article typed into the
 * panel would have been dropped on the way out, and because the server's
 * z.object stores exactly what it is sent, the FIRST save after writing one
 * would have deleted it from the database. Silently, with a green «Опубликовано».
 */

import { describe, it, expect, afterEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const BODY_RU = 'Первый абзац.\n\nВторой абзац.';
const BODY_KK = 'Бірінші абзац.\n\nЕкінші абзац.';

const CATALOG = {
  stages: {
    w23: [
      {
        id: 'w23-bleeding', kind: 'lesson',
        title: { ru: 'Кровотечение', kk: 'Қан кету' },
        summary: { ru: 'Когда звонить', kk: 'Қашан қоңырау шалу' },
        body: { ru: BODY_RU, kk: BODY_KK },
        redFlags: { ru: 'Прокладка за час.', kk: 'Бір сағатта прокладка.' },
      },
      // The shape the whole published catalogue is in: no article at all.
      {
        id: 'w23-nursery', kind: 'lesson',
        title: { ru: 'Комната малыша', kk: 'Бөбек бөлмесі' },
        summary: { ru: 'Что подготовить', kk: 'Нені дайындау' },
      },
    ],
  },
  coverage: { total: 101, filled: ['w23'], empty: [], items: 2, linked: 0, sharedOnly: [] },
};

interface Sent { path: string; method: string; body: Record<string, unknown> | null }

/**
 * Windows opened by this file, closed after each test.
 *
 * The panel polls on a timer. A JSDOM left open keeps firing those timers for
 * the rest of the run, so by the sixth test the event loop is carrying five
 * dead panels and a fixed `setTimeout(300)` is no longer long enough for the
 * live one to finish rendering — which shows up as an assertion about the
 * editor failing while the same assertion passes in isolation. Closing them,
 * and waiting on a CONDITION rather than a duration below, is what makes this
 * file say something about the panel instead of about the machine it ran on.
 */
const openWindows: Array<{ close: () => void }> = [];
afterEach(() => {
  while (openWindows.length) openWindows.pop()!.close();
});

/** Wait until `ready` is true, or fail loudly saying what never happened. */
async function until(what: string, ready: () => boolean, ms = 5000) {
  const deadline = Date.now() + ms;
  while (!ready()) {
    if (Date.now() > deadline) throw new Error(`timed out waiting for: ${what}`);
    await new Promise((r) => setTimeout(r, 20));
  }
}

async function open(catalog: unknown = CATALOG) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Sent[] = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = () => {};
      (window as unknown as { confirm: () => boolean }).confirm = () => true;

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
        }
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/content/review-queue') ? { waiting: [] }
          // A FRESH COPY every time, and this is not fussiness. The panel keeps
          // the parsed catalogue and writes the published draft back into it,
          // so handing out the shared fixture let one test that clears an
          // article delete it for every test that ran afterwards — which reads
          // as "the publish gate does not fire" three tests later, and passes
          // in isolation.
          : p.includes('/admin/content') ? JSON.parse(JSON.stringify(catalog))
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  openWindows.push(window);
  const $ = (sel: string) => window.document.querySelector(sel) as HTMLElement;
  const click = (el: Element) =>
    el.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));

  await until('the panel to boot', () => !!$('[data-view="content"]'));
  click($('[data-view="content"]'));
  await until('the stage map to draw', () => !!$('[data-stage="w23"]'));
  click($('[data-stage="w23"]'));
  // Not a duration: the editor container records which stage it drew and how
  // many cards, and readDraftFromDom refuses to read a DOM that does not match
  // the draft. Asserting against a half-drawn editor is how a green test hides
  // a broken one.
  await until('the stage editor to draw both cards', () =>
    $('#stageItems')?.dataset.drawnstage === 'w23'
    && window.document.querySelectorAll('#stageItems .item').length === 2);

  const items = () => window.document.querySelectorAll('#stageItems .item');
  const area = (i: number, f: string) =>
    items()[i].querySelector(`textarea[data-f="${f}"]`) as HTMLTextAreaElement;
  const type = (el: HTMLTextAreaElement, v: string) => {
    el.value = v;
    el.dispatchEvent(new window.Event('input', { bubbles: true }));
  };
  const publish = async () => {
    click($('#saveStage'));
    await until('the publish to be sent',
      () => sent.some((r) => r.method === 'PUT' && r.path.includes('/admin/content/w23')));
  };
  return { window, errors, sent, $, items, area, type, publish };
}

describe('there is somewhere to write the article', () => {
  it('draws a box per language, for the text and for the red flags', async () => {
    const { errors, area } = await open();
    expect(errors, errors.join('\n')).toEqual([]);
    for (const f of ['body.ru', 'body.kk', 'redFlags.ru', 'redFlags.kk']) {
      expect(area(0, f), `no box for ${f}`).toBeTruthy();
    }
    // English too — it is offered and never required, like every other field.
    expect(area(0, 'body.en')).toBeTruthy();
  });

  it('shows what was saved, newlines and all', async () => {
    const { area } = await open();
    expect(area(0, 'body.ru').value).toBe(BODY_RU);
    expect(area(0, 'body.kk').value).toBe(BODY_KK);
    expect(area(0, 'redFlags.ru').value).toBe('Прокладка за час.');
    // A card with no article shows empty boxes, not the previous card's text.
    expect(area(1, 'body.ru').value).toBe('');
  });

  it('says what the red-flag block is for, and where it will appear', async () => {
    // «Каждая метрика несёт объяснение». A second unlabelled pair of boxes is
    // a field somebody guesses at, and the guess would be "more article".
    const { items } = await open();
    const text = items()[0].textContent ?? '';
    expect(text).toContain('Красный флаг');
    expect(text).toContain('НАД текстом');
    expect(text).toContain('абзац');
  });
});

describe('what is typed is what is saved', () => {
  it('a textarea reaches the PUT — the selector matches it', async () => {
    // The defect: `input[data-f], select[data-f]` does not match a textarea, so
    // every article would have been silently dropped, and the server's
    // z.object would have stored the card without it — deleting the text.
    const { sent, area, type, publish } = await open();
    type(area(1, 'body.ru'), 'Новый текст.\n\nВторой абзац.');
    type(area(1, 'body.kk'), 'Жаңа мәтін.\n\nЕкінші абзац.');
    await publish();

    const put = sent.find((r) => r.method === 'PUT' && r.path.includes('/admin/content/w23'));
    expect(put, 'publish is wired to nothing').toBeDefined();
    const items = (put!.body as { items: Array<Record<string, unknown>> }).items;
    expect(items[1].body).toEqual({
      ru: 'Новый текст.\n\nВторой абзац.',
      kk: 'Жаңа мәтін.\n\nЕкінші абзац.',
    });
    // …and the card that already had one still has it: reading the DOM must
    // not blank a field just because nobody touched it.
    expect((items[0].body as Record<string, string>).ru).toBe(BODY_RU);
    expect(items[0].redFlags).toBeDefined();
  });

  it('clearing both boxes removes the article rather than storing an empty one', async () => {
    // `{}` is not "no article": the publish gate reads "nothing written in any
    // language" as unwritten, and an empty object left behind by a cleared
    // textarea would be downloaded to every phone and rendered nowhere.
    const { sent, area, type, publish } = await open();
    for (const f of ['body.ru', 'body.kk', 'body.en']) type(area(0, f), '');
    await publish();
    const put = sent.find((r) => r.method === 'PUT');
    const items = (put!.body as { items: Array<Record<string, unknown>> }).items;
    expect(items[0].body).toBeUndefined();
    // The red flags were not touched, so they stay.
    expect(items[0].redFlags).toBeDefined();
  });
});

describe('publish is blocked while the article is half-translated', () => {
  it('refuses, and names the article and the language', async () => {
    const { $, area, type } = await open();
    type(area(0, 'body.kk'), '');
    expect(($('#saveStage') as HTMLButtonElement).disabled).toBe(true);
    const note = $('#publishBlocked');
    expect(note.hidden).toBe(false);
    expect(note.textContent).toContain('w23-bleeding');
    expect(note.textContent).toContain('текст статьи');
    expect(note.textContent).toContain('казахский');
  });

  it('names the red-flag block by its own name', async () => {
    const { $, area, type } = await open();
    type(area(0, 'redFlags.kk'), '');
    expect(($('#saveStage') as HTMLButtonElement).disabled).toBe(true);
    expect($('#publishBlocked').textContent).toContain('Красный флаг');
  });

  it('a card with NO article does not block anything', async () => {
    // Every one of the 364 published items is this shape. If an unwritten
    // article read as a missing translation, the button would be dead on every
    // stage in the catalogue and the feature would look like a broken CMS.
    const { $ } = await open();
    expect(($('#saveStage') as HTMLButtonElement).disabled).toBe(false);
    expect($('#publishBlocked').hidden).toBe(true);
  });

  it('and the article unlocks it again the moment the Kazakh box is filled', async () => {
    const { $, area, type } = await open();
    type(area(0, 'body.kk'), '');
    expect(($('#saveStage') as HTMLButtonElement).disabled).toBe(true);
    type(area(0, 'body.kk'), BODY_KK);
    expect(($('#saveStage') as HTMLButtonElement).disabled).toBe(false);
  });
});

describe('the coverage line counts articles', () => {
  it('says how many guides have text, separately from how many have a link', async () => {
    // Without it an editor who has just written twenty articles reads
    // «0 со ссылкой» and concludes that none of them opens.
    const { $ } = await open();
    const text = $('#covSummary').textContent ?? '';
    expect(text).toContain('1 со статьёй');
  });
});
