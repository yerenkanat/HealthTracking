/**
 * Кадр 17c «Детектор плача», rendered for real (jsdom).
 *
 * adminAllViewsRender proves the tab draws. This proves it draws the TRUTH,
 * which on this screen is a specific and easy thing to get wrong:
 *
 *   · with analyses and no verdicts there is no accuracy, and the tile has to
 *     say «оценок пока нет · собираем с …» rather than «0 %». One is "we do
 *     not know yet", the other is "the model is always wrong", and the panel
 *     is where somebody decides to move the threshold on the strength of it.
 *   · the threshold box is filled from the SERVER. A box pre-filled with the
 *     shipped 45 while the database holds 70 invites an operator to press
 *     Сохранить and silently undo somebody's decision.
 *   · saving reads the answer. A PUT whose response is dropped redraws an
 *     unchanged screen, which reads as a stale render rather than a refusal.
 *   · «послушать запись» is answered in words, because it cannot be answered
 *     with a button: the clip is never stored.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

interface Sent { path: string; method: string; body: unknown }

/** The shape GET /admin/cry really answers with. */
function payload(over: Record<string, unknown> = {}) {
  return {
    windowDays: 30,
    analyses: 5,
    byReason: [
      { reason: 'hungry', count: 3, avgConfidence: 0.72, belowThreshold: 1, correct: 2, wrong: 0 },
      { reason: 'tired', count: 2, avgConfidence: 0.34, belowThreshold: 2, correct: 0, wrong: 1 },
    ],
    unrated: 2,
    lastAt: '2026-08-10T21:14:00.000Z',
    firstAt: '2026-07-29T04:02:00.000Z',
    minConfidence: 0.45,
    defaultMinConfidence: 0.45,
    thresholdSource: 'default',
    thresholdUpdatedAt: null,
    maxMinConfidence: 0.95,
    rated: 3,
    correct: 2,
    accuracy: 2 / 3,
    source: 'mother_verdicts',
    sourceNote: 'Точность считается только по разборам, которые мама оценила сама («это было верно?»). ' +
      'Уверенность модели — это её мнение о себе, и точностью не является.',
    audioNote: 'Записи не хранятся: клип уходит в классификатор и нигде не сохраняется, ' +
      'поэтому послушать разбор из панели нельзя.',
    rule: 'Окно — 30 дней. «Ниже порога» — разборы с уверенностью меньше 45 %: приложение по ним НЕ называет причину.',
    ...over,
  };
}

async function open(opts: { data?: Record<string, unknown>; failCry?: boolean; failWrite?: boolean } = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

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
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        const method = (init?.method ?? 'GET').toUpperCase();
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(init.body) : null });
          if (opts.failWrite) return { ok: false, status: 500, json: async () => ({}) };
          return { ok: true, status: 200, json: async () => JSON.parse(init!.body!) };
        }
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/cry')) {
          if (opts.failCry) return { ok: false, status: 503, json: async () => ({ error: 'cry_stats_unavailable' }) };
          return { ok: true, status: 200, json: async () => payload(opts.data) };
        }
        return { ok: true, status: 200, json: async () => ({}) };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="cry"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Детектор плача tab');
  const text = (sel: string) =>
    (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim();
  return { window, sent, errors, text, quiet: settle.quiet };
}

describe('the cry-detector tab', () => {
  it('boots and fills, without an error anywhere', async () => {
    const p = await open();
    expect(p.errors).toEqual([]);
    const t = p.text('#cry');
    expect(t).toContain('Голод');
    expect(t).toContain('Усталость');
    expect(t.length).toBeGreaterThan(80);
  });

  it('with no verdicts it says so instead of printing 0 %', async () => {
    const p = await open({
      data: { rated: 0, correct: 0, accuracy: null, unrated: 5,
        byReason: [{ reason: 'hungry', count: 5, avgConfidence: 0.72, belowThreshold: 1, correct: 0, wrong: 0 }] },
    });
    const t = p.text('#cryMetrics');
    expect(t).toContain('оценок пока нет');
    // The date it has been collecting since — an empty state with no date in it
    // reads as an excuse.
    expect(t).toContain('29.07');
    expect(t, 'a confident «0 %» where nothing has been rated').not.toMatch(/Точность\s*0 %/);
    // The row's own accuracy cell is the same claim in the table.
    expect(p.text('#cryBody')).toContain('оценок нет');
  });

  it('prints accuracy over rated rows, and says how many that is', async () => {
    const p = await open();
    const t = p.text('#cryMetrics');
    expect(t).toContain('67 %');            // 2 of 3 rated
    expect(t).toContain('по 3 оценкам мам'); // never «из 5 разборов»
  });

  it('never offers to play a recording, and says why', async () => {
    const p = await open();
    expect(p.window.document.querySelectorAll('#cry audio').length).toBe(0);
    expect(p.text('#cryFoot')).toContain('не хранятся');
  });

  it('fills the threshold box from the server, not from a constant here', async () => {
    const p = await open({ data: { minConfidence: 0.7, thresholdSource: 'override', thresholdUpdatedAt: '2026-08-01T09:00:00.000Z' } });
    const input = p.window.document.getElementById('cryThresh') as HTMLInputElement;
    expect(input.value).toBe('70');
    const rule = p.text('#cryThreshRule');
    expect(rule).toContain('70 %');
    expect(rule).toContain('45 %');            // what it was changed from
    expect(rule).toContain('без обновления приложения'); // the consequence
  });

  it('saving sends a fraction and confirms it', async () => {
    const p = await open();
    const input = p.window.document.getElementById('cryThresh') as HTMLInputElement;
    input.value = '60';
    (p.window.document.getElementById('cryThreshForm') as HTMLFormElement)
      .dispatchEvent(new p.window.Event('submit', { bubbles: true, cancelable: true }));
    await p.quiet('the threshold save');
    const put = p.sent.find((s) => s.path.includes('/admin/cry/threshold'));
    expect(put, 'Сохранить sent nothing').toBeTruthy();
    expect(put!.method).toBe('PUT');
    // 0..1 on the wire, everywhere: the ×100 exists for the human only.
    expect(put!.body).toEqual({ minConfidence: 0.6 });
    expect(p.text('#cryThreshMsg')).toContain('сохранён');
  });

  it('a refused save says so rather than looking saved', async () => {
    const p = await open({ failWrite: true });
    (p.window.document.getElementById('cryThreshForm') as HTMLFormElement)
      .dispatchEvent(new p.window.Event('submit', { bubbles: true, cancelable: true }));
    await p.quiet('the refused save');
    const msg = p.text('#cryThreshMsg');
    expect(msg).toContain('Не удалось');
    expect(msg).toContain('ничего не изменилось');
  });

  it('a failed load reads as a failure, not as an empty detector', async () => {
    const p = await open({ failCry: true });
    const t = p.text('#cryBody');
    expect(t).toContain('Не удалось');
    // And no metric tiles are left standing with numbers nobody can vouch for.
    expect(p.text('#cryMetrics')).toBe('');
    // The threshold box is emptied too. A box still holding 45 beside «порог
    // неизвестен» is an invitation to press Сохранить and write back a number
    // nobody has confirmed is the one in force.
    expect((p.window.document.getElementById('cryThresh') as HTMLInputElement).value).toBe('');
    expect(p.text('#cryThreshRule')).toContain('неизвестен');
  });
});
