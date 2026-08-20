/**
 * «Фото ещё не загружено», drawn in a browser rather than asserted in source.
 *
 * Two <img> tags in the panel carried `onerror="this.replaceWith(…)"`. An
 * inline event handler IS script, and the back office is now served under
 * `script-src 'self' 'nonce-…'` (src/http/securityHeaders.ts) which refuses
 * one — so both attributes would have become dead markup the day the CSP
 * shipped: the operator would get the browser's broken-image glyph where the
 * panel used to say the photo is missing, and the only trace would be a
 * console line nobody has open. That is the shape of failure this repo keeps
 * paying for, and it is why the handlers moved to one delegated listener.
 *
 * Asserted through a real DOM and a real dispatched `error`, because "the code
 * for it is in the file" is exactly what was true before and is not the claim.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/**
 * Boot the panel far enough for its document-level listeners to be installed.
 *
 * Nothing here needs a view rendered — the listener is registered at the top of
 * the first IIFE — so every request answers with an empty object and the page
 * is simply allowed to go quiet.
 */
async function boot() {
  const settle = panelSettle();
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(readFileSync(PANEL, 'utf8'), {
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
      settle.attach(window as never, async () => ({ ok: true, status: 200, text: async () => '', json: async () => ({}) }));
    },
  });
  await settle.quiet('the panel to finish booting');
  return { window: dom.window as unknown as Window & typeof globalThis, errors };
}

/** Put an <img> on the page, fail it, and hand back what took its place. */
function failedImage(window: Window & typeof globalThis, onfail: string): Element | null {
  const doc = window.document;
  const img = doc.createElement('img');
  img.setAttribute('data-onfail', onfail);
  img.setAttribute('src', '/shop/products/watch/photo');
  const host = doc.createElement('div');
  host.id = 'fallback-host';
  host.appendChild(img);
  doc.body.appendChild(host);
  // `error` from an <img> does not bubble, so this only reaches a listener
  // registered in the CAPTURE phase — which is the thing being tested.
  img.dispatchEvent(new window.Event('error'));
  return host.firstElementChild;
}

describe('a photo that will not load says so', () => {
  it('boots without throwing', async () => {
    const { errors } = await boot();
    expect(errors, errors.join('\n')).toEqual([]);
  });

  it('replaces a warehouse thumbnail with the blank chip', async () => {
    const { window } = await boot();
    const replaced = failedImage(window, 'thumb');
    expect(replaced, 'the <img> is still there — nothing handled the error').not.toBeNull();
    expect(replaced!.tagName).toBe('SPAN');
    expect(replaced!.className).toBe('thumb none');
    // The operator's tooltip. A blank square that does not say why is a defect
    // report waiting to be filed against a working server.
    expect(replaced!.getAttribute('title')).toBe('Фото не открылось');
  });

  it('replaces the catalogue preview with the sentence', async () => {
    const { window } = await boot();
    const replaced = failedImage(window, 'note');
    expect(replaced!.tagName).toBe('DIV');
    expect(replaced!.className).toBe('note');
    expect(replaced!.textContent).toBe('Фото ещё не загружено.');
  });

  it('leaves an image alone when it is not one of ours', async () => {
    // The listener is on the document and sees every error on the page,
    // including from markup that has its own handling. It must not eat those.
    const { window } = await boot();
    const replaced = failedImage(window, '');
    expect(replaced!.tagName).toBe('IMG');
  });
});
