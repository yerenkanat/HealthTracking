/**
 * The topic a guide is filed under, in the panel that sets it.
 *
 * The app draws four tiles («Гиды», app screen 27). Which tile a card lands on
 * is an editorial decision, so there has to be a control for it — and the
 * control has to SURVIVE a publish, which is the part that quietly fails: the
 * draft is read back out of the DOM field by field, and a selector that only
 * looked at `input` would drop every `select` silently. That is not
 * hypothetical here; it is exactly what happened to the video provider once.
 *
 * Rendered in a browser rather than grepped, because "there is a <select> in
 * the markup" and "a person can choose a topic and publish it" are two
 * different claims.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UNTAGGED = {
  id: 'm7-food', kind: 'lesson',
  title: { ru: 'Прикорм', kk: 'Қосымша тамақ' },
  summary: { ru: 'С чего начать', kk: 'Неден бастау керек' },
};

function catalogWith(items: Array<Record<string, unknown>>) {
  return {
    stages: { m7: items },
    coverage: {
      total: 101, filled: ['m7'], empty: [], items: items.length, linked: 0, sharedOnly: [],
    },
  };
}

async function openStage(items: Array<Record<string, unknown>>) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Array<{ path: string; method: string; body?: string }> = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = () => {};

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        sent.push({ path: p, method: init?.method ?? 'GET', body: init?.body as string });
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/content') ? catalogWith(items)
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 250));
  window.document.querySelector('[data-view="content"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 250));
  const cell = window.document.querySelector('[data-stage="m7"]') as HTMLElement | null;
  cell?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 200));

  return { window, errors, sent };
}

describe('choosing which shelf a guide goes on', () => {
  it('the editor row has a topic control with the four the app draws', async () => {
    const { window, errors } = await openStage([UNTAGGED]);
    expect(errors, errors.join('\n')).toEqual([]);
    const select = window.document.querySelector(
      '#stageItems [data-f="topic"]',
    ) as HTMLSelectElement | null;
    expect(select, 'no way to file a card under a topic').toBeTruthy();
    const values = [...select!.options].map((o) => o.value);
    // The empty option is «по этапу», not a fifth shelf.
    expect(values).toEqual(['', 'pregnancy', 'baby', 'child', 'mother']);
  });

  it('shows an untagged card where it will actually land', async () => {
    // «Пусто» does not mean «нигде»: m7 puts it on the baby shelf. Leaving the
    // author to guess is how a card gets tagged wrong to be safe.
    const { window } = await openStage([UNTAGGED]);
    const row = window.document.querySelector('#stageItems .item') as HTMLElement;
    expect(row.textContent).toContain('по этапу');
    expect(row.textContent).toContain('Малыш');
  });

  it('a chosen topic survives Publish', async () => {
    // The whole risk. readDraftFromDom rebuilds each item from the DOM, and a
    // field it does not read is erased on every save — silently, because the
    // request still succeeds.
    const { window, sent } = await openStage([UNTAGGED]);
    const select = window.document.querySelector(
      '#stageItems [data-f="topic"]',
    ) as HTMLSelectElement;
    select.value = 'mother';
    select.dispatchEvent(new window.Event('change', { bubbles: true }));

    (window.document.querySelector('#saveStage') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));

    const put = sent.find((r) => r.method === 'PUT' && r.path.includes('/admin/content/m7'));
    expect(put, 'nothing was published').toBeTruthy();
    expect(JSON.parse(put!.body!).items[0].topic).toBe('mother');
  });

  it('an already-tagged card keeps its topic through a publish that changes nothing else', async () => {
    const { window, sent } = await openStage([{ ...UNTAGGED, topic: 'child' }]);
    const select = window.document.querySelector(
      '#stageItems [data-f="topic"]',
    ) as HTMLSelectElement;
    expect(select.value).toBe('child');

    (window.document.querySelector('#saveStage') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));

    const put = sent.find((r) => r.method === 'PUT' && r.path.includes('/admin/content/m7'));
    expect(JSON.parse(put!.body!).items[0].topic).toBe('child');
  });

  it('the Контент view counts what is still untagged', async () => {
    // Not an error — those cards do appear, on the tile their stage implies.
    // It is worth a number because the fallback cannot produce «Мама»: content
    // about HER is invisible as such until somebody says so.
    const { window } = await openStage([UNTAGGED, { ...UNTAGGED, id: 'm7-teeth', topic: 'baby' }]);
    const summary = window.document.querySelector('#covSummary') as HTMLElement;
    expect(summary.textContent).toContain('1 без темы');
  });

  it('and says nothing when every card is filed', async () => {
    const { window } = await openStage([{ ...UNTAGGED, topic: 'baby' }]);
    const summary = window.document.querySelector('#covSummary') as HTMLElement;
    expect(summary.textContent).not.toContain('без темы');
  });
});
