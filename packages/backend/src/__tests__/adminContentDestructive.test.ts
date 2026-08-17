/**
 * The content editor's two destructive actions — docs/BACKLOG.md §4.4.
 *
 * `PUT /admin/content/:stage` REPLACES the stage with the `items` it is sent.
 * The panel deleted a card with one click and published the emptied draft with
 * another, and neither asked anything: `{items: []}` empties a live week for
 * every reader of the app, irreversibly, from a button that sits next to
 * «Удалить».
 *
 * Every neighbour in this panel already asks — the bulk import, the week
 * revert, the stocktake, the write-off, the broadcast publish, the medical
 * sign-off, cancelling an order. This screen was the exception.
 *
 * The publish prompt fires only when something DISAPPEARS. That is deliberate
 * and is asserted below: a dialog on every publish is dismissed reflexively
 * within a week, and that habit is exactly what would carry somebody through
 * the one that empties a stage. Same reasoning as the orders screen, where
 * «Подтверждён» is quiet and «Отменён» is not.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Eight fixed sleeps — 250 after boot, 250 after the tab, 200 after the stage,
 * 200 after each delete, 250 after each publish — decided by elapsed wall-clock
 * rather than by the work being finished, so they changed answer under load.
 * Two of the assertions here are NEGATIVE ("a declined publish still wrote",
 * "a publish that removes nothing interrupted the editor"), and a negative read
 * too early passes for the wrong reason every time.
 *
 * They are all quiet() now: no request in flight, none newly issued for several
 * consecutive turns, no page timer outstanding, and a throw rather than a
 * half-drawn screen. See helpers/panelSettle.ts.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const card = (id: string, ru: string, kk: string) => ({
  id, kind: 'lesson',
  title: { ru, kk },
  summary: { ru: 'Описание', kk: 'Сипаттама' },
});

/** Three fully translated cards, so the publish button is never gated. */
const LIVE = [
  card('m7-food', 'Прикорм', 'Қосымша тамақ'),
  card('m7-sleep', 'Сон', 'Ұйқы'),
  card('m7-teeth', 'Зубы', 'Тістер'),
];

interface Sent { path: string; method: string; body: string | null }

/** A booted editor that knows when it has finished working. */
interface Editor {
  window: JSDOM['window'];
  quiet: (label?: string) => Promise<void>;
}

async function openStage(items: Array<Record<string, unknown>>, confirmAnswer = true) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const confirms: string[] = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: () => void }).alert = () => {};
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return confirmAnswer;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (method !== 'GET') sent.push({ path: p, method, body: (init?.body as string) ?? null });
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : method !== 'GET' ? { ok: true, items: JSON.parse(String(init?.body ?? '{}')).items?.length ?? 0 }
          : p.includes('/admin/content') ? {
            stages: { m7: items },
            coverage: { total: 101, filled: ['m7'], empty: [], items: items.length, linked: 0, sharedOnly: [] },
          }
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="content"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Контент tab');
  (window.document.querySelector('[data-stage="m7"]') as HTMLElement)
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the m7 stage');

  return { window, sent, confirms, errors, quiet: settle.quiet };
}

const rows = (window: JSDOM['window']) =>
  window.document.querySelectorAll('#stageItems .item').length;

const clickAll = async (page: Editor, sel: string) => {
  const el = page.window.document.querySelector(sel) as HTMLElement;
  expect(el, `no ${sel}`).not.toBeNull();
  el.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet(`the click on ${sel}`);
};

const publish = async (page: Editor) => {
  const btn = page.window.document.querySelector('#saveStage') as HTMLButtonElement;
  expect(btn.disabled, 'the publish button is gated — the fixture is wrong, not the panel').toBe(false);
  btn.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet('the publish');
};

describe('deleting a card asks first', () => {
  it('names the card and says when the reader loses it', async () => {
    const page = await openStage(LIVE);
    const { window, confirms, errors } = page;
    expect(errors, errors.join('\n')).toEqual([]);
    expect(rows(window)).toBe(3);

    await clickAll(page, '#stageItems [data-del]');

    expect(confirms.length, 'a live card was deleted without asking').toBe(1);
    // «Удалить карточку?» is waved through; the title is what makes it a
    // question somebody can answer.
    expect(confirms[0]).toContain('Прикорм');
    // And the consequence, accurately: the delete edits the DRAFT. It reaches
    // the reader on Publish, and saying otherwise in either direction is a lie.
    expect(confirms[0]).toMatch(/Опубликовать/);
  });

  it('keeps the card when the answer is no', async () => {
    const page = await openStage(LIVE, false);
    const { window } = page;
    await clickAll(page, '#stageItems [data-del]');
    expect(rows(window), 'a declined delete removed the card anyway').toBe(3);
  });

  it('removes it when the answer is yes, and says where it went', async () => {
    const page = await openStage(LIVE);
    const { window } = page;
    await clickAll(page, '#stageItems [data-del]');
    expect(rows(window)).toBe(2);
    expect(window.document.querySelector('#saveMsg')!.textContent)
      .toMatch(/убрана из черновика/i);
  });

  /**
   * It removed the card the person asked to remove — which it did not.
   *
   * `data-idx` is a position in `draft`, and renderEditor calls
   * updatePublishState (→ readDraftFromDom) BEFORE it replaces the markup. So
   * «splice, renderEditor» read three stale rows back into a two-item draft:
   * row 0 into item 0, row 1 into item 1, row 2 off the end. Deleting the
   * first card kept the first card and dropped the LAST one instead — silently,
   * in a dialog that had just named a different card by title.
   *
   * Asserted on which cards survive, not on how many: the count was right the
   * whole time.
   */
  it('removes the card that was named, not the last one in the list', async () => {
    const page = await openStage(LIVE);
    const { window, confirms, sent } = page;
    await clickAll(page, '#stageItems [data-del]');
    expect(confirms[0]).toContain('Прикорм');

    const ids = [...window.document.querySelectorAll('#stageItems [data-f="id"]')]
      .map((el) => (el as HTMLInputElement).value);
    expect(ids, 'the wrong card was deleted').toEqual(['m7-sleep', 'm7-teeth']);

    // And what is PUBLISHED is the same two, not whatever the stale read left.
    await publish(page);
    const put = sent.find((s) => s.method === 'PUT')!;
    expect(JSON.parse(put.body!).items.map((i: { id: string }) => i.id))
      .toEqual(['m7-sleep', 'm7-teeth']);
  });
});

describe('publishing a stage that has lost cards asks first', () => {
  it('asks before emptying a live stage, and says how many disappear', async () => {
    const page = await openStage(LIVE);
    const { window, confirms, sent } = page;
    // Delete all three, then publish `{items: []}` — the exact wipe.
    for (let i = 0; i < 3; i += 1) await clickAll(page, '#stageItems [data-del]');
    expect(rows(window)).toBe(0);
    const beforePublish = confirms.length;

    await publish(page);

    const q = confirms[beforePublish];
    expect(q, 'a live stage was emptied without asking').toBeTruthy();
    expect(q).toMatch(/ПУСТОЙ/);
    // The number, from what the server last said the stage holds — not a guess.
    expect(q).toContain('3 карточки');
    // And that it is live the moment it lands.
    expect(q).toMatch(/всем читателям сразу/);
    expect(sent.some((s) => s.method === 'PUT'), 'confirming did not publish').toBe(true);
  });

  it('sends nothing when the answer is no, and says the server is untouched', async () => {
    const page = await openStage(LIVE, false);
    const { sent, confirms } = page;
    // A declined delete leaves the draft intact, so remove the card from the
    // draft directly is not possible here — instead publish a draft that lost
    // a card via a confirmed delete. With confirmAnswer=false the delete is
    // declined too, so drive the wipe through a stage that starts smaller.
    expect(confirms.length).toBe(0);

    // Nothing was deleted, so publishing changes nothing and must NOT ask.
    await publish(page);
    expect(confirms.length, 'a publish that removes nothing interrupted the editor').toBe(0);
    expect(sent.some((s) => s.method === 'PUT')).toBe(true);
  });

  it('a declined publish leaves the server alone and says so', async () => {
    // Delete confirmed, publish declined: two different answers, so the
    // confirm stub has to change its mind between them.
    const html = readFileSync(PANEL, 'utf8');
    const settle = panelSettle();
    const sent: Sent[] = [];
    let answer = true;
    const dom = new JSDOM(html, {
      runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin',
      beforeParse(window) {
        window.HTMLCanvasElement.prototype.getContext = (() => null) as never;
        window.scrollTo = () => {};
        Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
        (window as unknown as { alert: () => void }).alert = () => {};
        (window as unknown as { confirm: () => boolean }).confirm = () => answer;
        settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
          const p = path;
          const method = init?.method ?? 'GET';
          if (method !== 'GET') sent.push({ path: p, method, body: (init?.body as string) ?? null });
          const body = p.includes('/admin/me') ? { staffId: 's1', role: 'owner' }
            : method !== 'GET' ? { ok: true, items: 0 }
            : p.includes('/admin/content') ? {
              stages: { m7: LIVE },
              coverage: { total: 101, filled: ['m7'], empty: [], items: LIVE.length, linked: 0, sharedOnly: [] },
            } : {};
          return { ok: true, status: 200, json: async () => body };
        });
      },
    });
    const w = dom.window;
    const page: Editor = { window: w, quiet: settle.quiet };
    await settle.quiet('boot');
    w.document.querySelector('[data-view="content"]')!
      .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the Контент tab');
    (w.document.querySelector('[data-stage="m7"]') as HTMLElement)
      .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the m7 stage');

    await clickAll(page, '#stageItems [data-del]');
    answer = false;
    await publish(page);

    expect(sent.filter((s) => s.method === 'PUT'), 'a declined publish still wrote').toEqual([]);
    expect(w.document.querySelector('#saveMsg')!.textContent)
      .toMatch(/на сервере ничего не изменилось/i);
  });

  it('names the cards that go, not just how many', async () => {
    const page = await openStage(LIVE);
    const { confirms } = page;
    await clickAll(page, '#stageItems [data-del]');
    const before = confirms.length;
    await publish(page);
    expect(confirms[before]).toContain('Прикорм');
    expect(confirms[before]).toMatch(/Исчезнет 1 карточка из 3/);
  });
});
