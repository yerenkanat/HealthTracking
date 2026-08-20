/**
 * Two classes the panel used and never defined — docs/BACKLOG.md §5.4, §8.1.
 *
 *   `.chip.crit` — set on «списание» in the returns ledger and on «без ответа»
 *   in the support queue. `.chip` exists, `.chip.warn` and `.chip.ok` exist,
 *   `.chip.crit` never did. A critical status therefore rendered as a plain
 *   white lozenge: it read as chrome, on the two rows in the panel that cost
 *   money and lose a customer.
 *
 *   `.formmsg.err` — set on #finMsg and friends. Only `.bad` and `.ok` were
 *   defined, so a message that means "this did not load" rendered in the muted
 *   grey of a hint.
 *
 * Checked through getComputedStyle on a REAL rendered element, not by grepping
 * the stylesheet: the failure mode here is precisely that the markup names a
 * class and the cascade has nothing to say about it, and only the cascade can
 * report that. jsdom does not resolve custom properties, so a token-valued
 * declaration comes back as the literal `var(--crit-text)` — which is still
 * proof that a rule matched, and is asserted as such.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');
const panelHtml = readFileSync(PANEL, 'utf8');

/** Just the stylesheet, in a document we can hang test elements off. */
function styled() {
  const styles = [...panelHtml.matchAll(/<style>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');
  const dom = new JSDOM(`<!doctype html><html><head><style>${styles}</style></head><body></body></html>`);
  return dom.window;
}

function paint(window: JSDOM['window'], className: string) {
  const el = window.document.createElement('span');
  el.className = className;
  el.textContent = 'x';
  window.document.body.appendChild(el);
  const cs = window.getComputedStyle(el);
  return { color: cs.color, background: cs.backgroundColor || '' };
}

describe('a critical status is painted, not left as chrome', () => {
  it('.pill.crit carries the crit colour', () => {
    const window = styled();
    const crit = paint(window, 'pill crit');
    const plain = paint(window, 'pill');
    expect(crit.color, '.pill.crit does not colour anything').not.toBe(plain.color);
    expect(crit.color).toContain('crit');
  });

  it('.chip.crit is still undefined, which is why the call sites moved', () => {
    // Not a wish: if somebody defines it later this fails, and they will find
    // this comment and the five competing chip vocabularies §8.1 counts. The
    // point of the fix was to stop using the word, not to add a sixth spelling.
    const window = styled();
    expect(paint(window, 'chip crit').color).toBe(paint(window, 'chip').color);
  });

  it('nothing in the panel sets `chip crit` any more', () => {
    // The two call sites the backlog names: «списание» in the returns ledger
    // and «без ответа» in the support queue.
    expect(panelHtml, 'a status is rendering as a white lozenge again')
      .not.toMatch(/class\s*=\s*['"]chip crit['"]/);
    expect(panelHtml).not.toMatch(/class\s*=\s*['"]chip\s+crit/);
  });
});

describe('a message that means "this failed" is red', () => {
  it('.formmsg.err is a real rule and not the muted default', () => {
    const window = styled();
    const err = paint(window, 'formmsg err');
    const plain = paint(window, 'formmsg');
    expect(err.color, '.formmsg.err renders grey where it means red').not.toBe(plain.color);
    expect(err.color).toContain('crit');
  });

  it('.formmsg.bad still means the same thing, so both spellings are safe', () => {
    // Two families already disagree in this file — `.savebar.err` next to
    // `.formmsg.bad`. Defining the alias is what makes a sixth call site that
    // types the wrong one harmless instead of silent.
    const window = styled();
    expect(paint(window, 'formmsg err').color).toBe(paint(window, 'formmsg bad').color);
  });
});

/**
 * The rendered ledger, not the stylesheet: the class has to be on the element
 * a person actually looks at.
 */
describe('the returns ledger paints a write-off', () => {
  it('renders «списание» as a pill with the crit modifier', async () => {
    const FINANCE = {
      from: '2026-08-01', to: '2026-08-31', planProgress: null,
      money: { earnedMinor: 0, promisedMinor: 0, lostMinor: 0, discountMinor: 0 },
      margin: { marginMinor: 0, coverage: 1 },
      returns: {
        returnedUnits: 1, soldUnits: 10, returnRate: 0.1, writeOffCostMinor: 500000,
        events: [
          { at: '2026-08-10T10:00:00Z', productName: 'Часы', color: 'чёрный', units: 1, reason: 'writeoff', note: 'разбит экран' },
          { at: '2026-08-09T10:00:00Z', productName: 'Часы', color: 'белый', units: 1, reason: 'return', note: null },
        ],
      },
      caveats: [], byDay: [], byProduct: [], plan: null,
    };

    const settle = panelSettle();
  const dom = new JSDOM(panelHtml, {
      runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin/ui',
      beforeParse(window) {
        window.HTMLCanvasElement.prototype.getContext = (() => null) as never;
        window.scrollTo = () => {};
        Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
        (window as unknown as { alert: () => void }).alert = () => {};
        settle.attach(window as never, async (path: string) => {
          const p = String(path);
          const body = p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
            : p.includes('/admin/finance') ? FINANCE : {};
          return { ok: true, status: 200, text: async () => '', json: async () => body };
        });
      },
    });
    const w = dom.window;
    await settle.quiet('boot');
    w.document.querySelector('[data-view="finance"]')!
      .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the Финансы tab');

    const cells = [...w.document.querySelectorAll('#finReturns span')] as HTMLElement[];
    const writeOff = cells.find((el) => el.textContent === 'списание');
    expect(writeOff, 'the write-off row is gone from the ledger').toBeTruthy();
    expect(writeOff!.className, 'a write-off is a white lozenge again').toBe('pill crit');
    // Painted, in the document that carries the stylesheet.
    expect(w.getComputedStyle(writeOff!).color).toContain('crit');
  });
});
