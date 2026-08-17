/**
 * The two screens the medical-review rule needs to be usable.
 *
 * medicalReview.test.ts proves the rule. This proves somebody can work with it:
 * an author can mark a card medical and save it as a draft, and a clinician can
 * find what is waiting and sign it off. A rule with no way to satisfy it is a
 * wall, and the way round a wall is to stop marking cards medical.
 *
 * The checkbox reading is here because it broke on the first attempt in a way
 * no API test could see: the editor read every field with `.value`, and a
 * checkbox's `.value` is the string "on" — truthy for `medical` AND for
 * `draft`, so every card in the stage became a medical draft.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Seven fixed sleeps — 300 after boot, 300 per tab, 200–250 per action —
 * decided their verdict on elapsed wall-clock rather than on the work being
 * finished, so they changed answer under load. The review queue is drawn from
 * a second request that chains off the tab click, so a window that closed early
 * read an EMPTY queue, and «an empty queue says why it is empty» would have
 * passed on it.
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

const CATALOG = {
  stages: {
    w23: [
      {
        id: 'w23-bleeding', kind: 'lesson', medical: true, draft: true,
        title: { ru: 'Кровотечение', kk: 'Қан кету' },
        summary: { ru: 'Когда звонить', kk: 'Қашан қоңырау шалу' },
      },
      {
        id: 'w23-nursery', kind: 'lesson',
        title: { ru: 'Комната малыша', kk: 'Бөбек бөлмесі' },
        summary: { ru: 'Что подготовить', kk: 'Нені дайындау' },
      },
    ],
  },
  coverage: { total: 101, filled: ['w23'], empty: [], items: 2, linked: 0, sharedOnly: [] },
};

const BODY_RU = 'Кровотечение во втором триместре бывает разным.\n\nАлая кровь со сгустками — звоните сейчас.';
const BODY_KK = 'Екінші триместрдегі қан кету әртүрлі болады.\n\nҰйыған қызыл қан — қазір қоңырау шалыңыз.';
const FLAGS_RU = 'Прокладка полностью промокает за час.';

const QUEUE = {
  waiting: [
    {
      stage: 'w20', id: 'w20-movements', title: 'Шевеления', reason: 'stale', draft: false,
      summary: { ru: 'Сколько раз в день', kk: 'Күніне неше рет' },
      body: { ru: 'Считайте шевеления после еды.', kk: 'Тамақтан кейін санаңыз.' },
      redFlags: { ru: 'Меньше десяти за двенадцать часов — звоните.', kk: 'Он реттен аз болса — қоңырау шалыңыз.' },
      url: '', video: '',
    },
    {
      stage: 'w23', id: 'w23-bleeding', title: 'Кровотечение', reason: 'never', draft: true,
      summary: { ru: 'Когда звонить', kk: 'Қашан қоңырау шалу' },
      body: { ru: BODY_RU, kk: BODY_KK },
      redFlags: { ru: FLAGS_RU, kk: 'Бір сағатта прокладка толады.' },
      url: 'https://example.kz/bleeding',
      video: 'hls: https://cdn/x.m3u8',
    },
  ],
};

interface Sent { path: string; method: string; body: Record<string, unknown> | null }

async function open(role: string, queue: unknown = QUEUE) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
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

      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
        }
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role, displayName: 'Ерен' }
          : p.includes('/admin/content/review-queue') ? queue
          : p.includes('/admin/content') ? CATALOG
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  const $ = (sel: string) => window.document.querySelector(sel) as HTMLElement;
  const openTab = async (view: string) => {
    window.document.querySelector(`[data-view="${view}"]`)!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await settle.quiet(`the ${view} tab`);
  };
  return { window, errors, sent, $, openTab, quiet: settle.quiet };
}

describe('the author marks a card, and it survives the round trip', () => {
  it('shows the medical and draft flags in the state they were saved', async () => {
    const { window, errors, openTab, quiet } = await open('owner');
    expect(errors, errors.join('\n')).toEqual([]);
    await openTab('content');
    (window.document.querySelector('[data-stage="w23"]') as HTMLElement)
      ?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the w23 stage');

    const items = window.document.querySelectorAll('#stageItems .item');
    expect(items.length).toBe(2);
    const flag = (i: number, name: string) =>
      (items[i].querySelector(`input[data-f="${name}"]`) as HTMLInputElement).checked;
    expect(flag(0, 'medical')).toBe(true);
    expect(flag(0, 'draft')).toBe(true);
    expect(flag(1, 'medical')).toBe(false);
    expect(flag(1, 'draft')).toBe(false);
  });

  it('says where the card stands with the doctor', async () => {
    const { window, openTab, quiet } = await open('owner');
    await openTab('content');
    (window.document.querySelector('[data-stage="w23"]') as HTMLElement)
      ?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the w23 stage');
    const items = window.document.querySelectorAll('#stageItems .item');
    expect(items[0].querySelector('.reviewstate')!.textContent).toContain('ждёт проверки');
    // A card nobody marked medical says nothing — a badge on every card would
    // make the marked ones invisible.
    expect(items[1].querySelector('.reviewstate')!.textContent!.trim()).toBe('');
  });

  it('a checkbox is read as a flag, not as the string "on"', async () => {
    // The editor reads every field with `.value`, and a checkbox's value is
    // "on" whether it is ticked or not — which set every card in the stage to
    // a medical draft the first time this was written.
    const { window, sent, openTab, quiet } = await open('owner');
    await openTab('content');
    (window.document.querySelector('[data-stage="w23"]') as HTMLElement)
      ?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the w23 stage');

    // Untick both on the medical card, leave the other alone, and publish.
    const first = window.document.querySelectorAll('#stageItems .item')[0];
    for (const name of ['medical', 'draft']) {
      const box = first.querySelector(`input[data-f="${name}"]`) as HTMLInputElement;
      box.checked = false;
      box.dispatchEvent(new window.Event('input', { bubbles: true }));
    }
    (window.document.querySelector('#saveStage') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the publish');

    const put = sent.find((r) => r.method === 'PUT' && r.path.includes('/admin/content/w23'));
    expect(put, 'publish is wired to nothing').toBeDefined();
    const items = (put!.body as { items: Array<Record<string, unknown>> }).items;
    // Absent, not `false` and certainly not "on".
    expect(items[0].medical).toBeUndefined();
    expect(items[0].draft).toBeUndefined();
    expect(items[1].medical).toBeUndefined();
  });
});

describe('the clinician finds the work', () => {
  it('lists what is waiting, worst first, with the reason', async () => {
    const { $, openTab } = await open('clinician');
    await openTab('review');
    const text = $('#reviewBody').textContent ?? '';
    expect(text).toContain('Шевеления');
    expect(text).toContain('Кровотечение');
    // The live-but-edited card outranks the new draft: it is on somebody's
    // phone right now saying something nobody has read.
    expect(text.indexOf('Шевеления')).toBeLessThan(text.indexOf('Кровотечение'));
    expect(text).toContain('текст изменён после проверки');
    expect(text).toContain('ещё не проверялся');
  });

  it('the tab carries the count, so it is visible without opening it', async () => {
    const { $, openTab } = await open('clinician');
    await openTab('review');
    expect($('#reviewBadgeCount').hidden).toBe(false);
    expect($('#reviewBadgeCount').textContent).toBe('2');
  });

  it('shows the whole text being signed, not just the headline', async () => {
    // The signature quotes the article and the red-flag block (textFingerprint).
    // A title-only row makes «Подтвердить» a rubber stamp over paragraphs the
    // clinician has never seen — and no other screen in their role shows a body.
    const { window, openTab } = await open('clinician');
    await openTab('review');
    const card = window.document.querySelector('[data-review="w23|w23-bleeding"]') as HTMLElement;
    expect(card, 'the card is not drawn').toBeTruthy();
    const text = card.textContent ?? '';
    for (const p of [BODY_RU.split('\n\n')[0], BODY_RU.split('\n\n')[1], BODY_KK.split('\n\n')[0]]) {
      expect(text, `missing from the review row: ${p}`).toContain(p);
    }
    expect(text).toContain(FLAGS_RU);
    expect(text).toContain('Когда звонить');
    // …and where the material itself lives, which the fingerprint also covers.
    expect(text).toContain('https://example.kz/bleeding');
    expect(text).toContain('https://cdn/x.m3u8');
  });

  it('the red-flag block comes first, as it does on the phone', async () => {
    const { window, openTab } = await open('clinician');
    await openTab('review');
    const card = window.document.querySelector('[data-review="w23|w23-bleeding"]') as HTMLElement;
    const text = card.textContent ?? '';
    expect(text.indexOf(FLAGS_RU)).toBeLessThan(text.indexOf(BODY_RU.split('\n\n')[0]));
    // And the button is BELOW the text: level with the title it is pressed
    // without scrolling, which is the stamp this screen exists to prevent.
    const blocks = card.querySelectorAll('.revblock');
    expect(blocks.length).toBeGreaterThan(0);
    const foot = card.querySelector('.revfoot');
    expect(foot?.querySelector('[data-approve]'), 'the button left the footer').toBeTruthy();
    const order = [...card.querySelectorAll('.revblock, .revfoot')];
    expect(order[order.length - 1].className).toContain('revfoot');
  });

  it('a card with no text says so rather than showing an empty row', async () => {
    // «Пустые состояния говорят причину». A medical card that is only a link is
    // a real shape, and the reviewer must know that is ALL they are signing.
    const { window, openTab } = await open('clinician', {
      waiting: [{
        stage: 'w23', id: 'w23-link', title: 'Ссылка', reason: 'never', draft: false,
        summary: {}, body: {}, redFlags: {}, url: '', video: '',
      }],
    });
    await openTab('review');
    const card = window.document.querySelector('[data-review="w23|w23-link"]') as HTMLElement;
    expect(card.textContent).toContain('нет ни текста, ни ссылки');
  });

  it('signing off posts to the review route for that exact card', async () => {
    const { window, sent, openTab, quiet } = await open('clinician');
    await openTab('review');
    (window.document.querySelector('[data-approve]') as HTMLElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the sign-off');

    const post = sent.find((r) => r.method === 'POST' && r.path.includes('/review'));
    expect(post, 'the approve button is wired to nothing').toBeDefined();
    expect(post!.path).toContain('/admin/content/w20/w20-movements/review');
  });

  it('an empty queue says why it is empty and what fills it', async () => {
    // «Пустые состояния говорят причину и одно действие.» "Нет данных" on this
    // screen reads as "the queue is broken".
    const { $, openTab } = await open('clinician', { waiting: [] });
    await openTab('review');
    const text = $('#reviewBody').textContent ?? '';
    expect(text).toContain('весь медицинский текст подписан');
    expect(text).toContain('помечает карточку как медицинскую');
    expect($('#reviewBadgeCount').hidden).toBe(true);
  });

  it('is not a tab for whoever writes the content', async () => {
    // Authoring is `content`, approving is `health`. Showing an editor a tab
    // that 403s teaches them the panel is broken, not that the rule exists.
    const { window } = await open('content');
    const tab = window.document.querySelector('.nav[data-view="review"]') as HTMLElement;
    expect(tab.hidden).toBe(true);
  });
});
