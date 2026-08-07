/**
 * «Опубликовать» is locked until the Kazakh version is there.
 *
 * The server refuses it either way — content/bilingual.ts, checked over HTTP in
 * bilingual.test.ts — so what this covers is the part a person experiences:
 * finding out while they are typing, rather than after writing three cards and
 * losing the round trip to a 400.
 *
 * Rendered in a browser, because "disabled" in the markup and disabled on the
 * screen are two different claims, and the second one is the one that matters.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** A stage with one card, translated or not, as GET /admin/content returns it. */
function catalogWith(item: Record<string, unknown>) {
  return {
    stages: { w20: [item] },
    coverage: { total: 101, filled: ['w20'], empty: [], items: 1, linked: 0, sharedOnly: [] },
  };
}

const TRANSLATED = {
  id: 'w20-breathing', kind: 'lesson',
  title: { ru: 'Дыхание', kk: 'Тыныс алу' },
  summary: { ru: 'Про дыхание', kk: 'Тыныс туралы' },
};
const RUSSIAN_ONLY = {
  id: 'w20-breathing', kind: 'lesson',
  title: { ru: 'Дыхание' },
  summary: { ru: 'Про дыхание' },
};

async function openStage(item: Record<string, unknown>) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Array<{ path: string; method: string }> = [];
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

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        sent.push({ path: p, method: init?.method ?? 'GET' });
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/content') ? catalogWith(item)
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
  // Open the stage the fixture filled.
  const cell = window.document.querySelector('[data-stage="w20"]') as HTMLElement | null;
  cell?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 200));

  return {
    window, errors, sent,
    button: window.document.querySelector('#saveStage') as HTMLButtonElement,
    note: window.document.querySelector('#publishBlocked') as HTMLElement,
  };
}

describe('the publish button', () => {
  it('is live when both languages are filled', async () => {
    const { button, note, errors } = await openStage(TRANSLATED);
    expect(errors, errors.join('\n')).toEqual([]);
    expect(button.disabled, 'a fully translated stage cannot be published').toBe(false);
    expect(note.hidden).toBe(true);
  });

  it('is locked when the Kazakh version is missing', async () => {
    const { button } = await openStage(RUSSIAN_ONLY);
    expect(button.disabled).toBe(true);
  });

  it('says which card and which field, not "заполните все поля"', async () => {
    // The version of this that helps nobody is a generic message that sends
    // somebody hunting through fourteen cards for the one empty box.
    const { note } = await openStage(RUSSIAN_ONLY);
    expect(note.hidden).toBe(false);
    expect(note.textContent).toContain('w20-breathing');
    expect(note.textContent).toContain('казахский');
    expect(note.textContent).toContain('заголовок');
  });

  it('unlocks as soon as the last Kazakh field is typed into', async () => {
    // The check has to run on input. Re-checking only on a later re-render
    // leaves the button dead under a form that is now complete, which reads as
    // the panel being broken.
    const { window, button } = await openStage(RUSSIAN_ONLY);
    expect(button.disabled).toBe(true);

    for (const sel of ['[data-f="title.kk"]', '[data-f="summary.kk"]']) {
      const input = window.document.querySelector(sel) as HTMLInputElement;
      expect(input, `${sel} is not on the card`).toBeTruthy();
      input.value = 'Тыныс алу';
      input.dispatchEvent(new window.Event('input', { bubbles: true }));
    }
    await new Promise((r) => setTimeout(r, 50));
    expect(button.disabled, 'both Kazakh fields are filled and it is still locked').toBe(false);
  });

  it('whitespace does not unlock it', async () => {
    const { window, button } = await openStage(RUSSIAN_ONLY);
    for (const sel of ['[data-f="title.kk"]', '[data-f="summary.kk"]']) {
      const input = window.document.querySelector(sel) as HTMLInputElement;
      input.value = '   ';
      input.dispatchEvent(new window.Event('input', { bubbles: true }));
    }
    await new Promise((r) => setTimeout(r, 50));
    expect(button.disabled).toBe(true);
  });
});
