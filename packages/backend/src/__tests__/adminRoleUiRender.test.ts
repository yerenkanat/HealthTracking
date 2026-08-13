/**
 * The panel shows a person what their job needs and nothing else.
 *
 * The server now refuses what a role may not have, which is the part that
 * matters. What it cannot do is stop the panel PAINTING a tab that will only
 * ever answer 403 — and a warehouse hand who opens «Пользователи» and sees an
 * empty table has not learned that she is not allowed; she has learned that the
 * panel is broken, and she will say so.
 *
 * So the panel carries its own copy of the matrix, and this file holds it to
 * two things:
 *
 *   1. it must equal the server's, or the panel hides a tab that works and
 *      shows one that does not;
 *   2. the hiding must actually happen in a browser, on the nav AND on the
 *      dashboard cards, including for a bookmarked #hash.
 *
 * Rendered in jsdom rather than asserted as source, because the difference
 * between `hidden` in the markup and hidden on the screen is exactly the class
 * of bug this is here to catch.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { ROLE_CAPS, STAFF_ROLES, type StaffRole } from '../auth/capabilities';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** Open the panel signed in as [role], and let it settle. */
async function openAs(role: StaffRole, hash = '') {
  const html = readFileSync(PANEL, 'utf8');
  const vc = new VirtualConsole();
  const errors: string[] = [];
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: `http://localhost/admin/ui${hash}`,
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

      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role, displayName: 'Ерен' }) };
        }
        // Everything else answers empty. What this file cares about is what the
        // panel DRAWS for a role, not what any endpoint returns.
        return { ok: true, status: 200, text: async () => '', json: async () => ({}) };
      }) as never;
    },
  });

  await new Promise((r) => setTimeout(r, 250));
  return { window: dom.window, errors };
}

/**
 * The «SOS и зоны» card — the geofence feed, on the Экстренные screen.
 *
 * Found by its heading rather than by its capability, so that dropping the
 * capability reports the leak instead of reporting a missing card.
 */
function sosCard(window: JSDOM['window']): HTMLElement {
  const card = [...window.document.querySelectorAll('#emergencies .card')]
    .find((c) => (c.querySelector('h3')?.textContent ?? '').includes('SOS'));
  expect(card, 'the SOS feed is gone from the Экстренные screen').toBeDefined();
  expect(
    (card as HTMLElement).dataset.cap,
    'the SOS card stopped naming `health` — every role with `emergencies` can now see where children are',
  ).toBe('health');
  return card as HTMLElement;
}

/** The capability each nav item declares, read from the panel's own markup. */
function navCaps(window: JSDOM['window']): Map<string, string | null> {
  const out = new Map<string, string | null>();
  for (const el of window.document.querySelectorAll('.nav[data-view]')) {
    out.set((el as HTMLElement).dataset.view!, (el as HTMLElement).dataset.cap ?? null);
  }
  return out;
}

describe('the panel and the server agree on what a role may do', () => {
  it('the copied matrix is identical to auth/capabilities.ts', async () => {
    const { window } = await openAs('owner');
    const copied = (window as unknown as { ROLE_CAPS?: Record<string, string[]> }).ROLE_CAPS
      // The panel's script runs in an IIFE, so the matrix is not on window.
      // Read it out of the source instead — still the real value, since the
      // literal is what the browser evaluates.
      ?? JSON.parse(
        readFileSync(PANEL, 'utf8')
          .match(/const ROLE_CAPS=(\{[\s\S]*?\});/)![1]
          .replace(/(\w+):/g, '"$1":')
          .replace(/,(\s*[}\]])/g, '$1'),
      );

    for (const role of STAFF_ROLES) {
      expect(copied[role], `the panel has no entry for ${role}`).toBeDefined();
      expect([...copied[role]].sort(), `${role} differs between panel and server`)
        .toEqual([...ROLE_CAPS[role]].sort());
    }
    expect(Object.keys(copied).sort()).toEqual([...STAFF_ROLES].sort());
  });

  it('every capability a nav item names is a real one', async () => {
    const { window } = await openAs('owner');
    const real = new Set(ROLE_CAPS.owner);
    for (const [view, cap] of navCaps(window)) {
      if (cap === null) continue;
      expect(real.has(cap as never), `${view} names '${cap}', which no role can hold`).toBe(true);
    }
  });
});

describe('what each role sees', () => {
  it('an owner sees every tab', async () => {
    const { window, errors } = await openAs('owner');
    expect(errors, errors.join('\n')).toEqual([]);
    const hidden = [...window.document.querySelectorAll('.nav[data-view]')]
      .filter((el) => (el as HTMLElement).hidden)
      .map((el) => (el as HTMLElement).dataset.view);
    expect(hidden).toEqual([]);
  });

  it('a warehouse hand sees Склад, and no customer anywhere', async () => {
    const { window, errors } = await openAs('warehouse');
    expect(errors, errors.join('\n')).toEqual([]);
    const shown = (v: string) =>
      !(window.document.querySelector(`.nav[data-view="${v}"]`) as HTMLElement).hidden;

    expect(shown('stock')).toBe(true);
    for (const v of ['users', 'kids', 'devices', 'audit', 'staff', 'shop', 'content']) {
      expect(shown(v), `${v} must be hidden from a warehouse hand`).toBe(false);
    }
    // «SOS и зоны» has no nav item of its own since the seven-section rail: it
    // is a card on the Экстренные screen, carrying the same `health`
    // capability the tab used to. Asserted on the card, because that is now the
    // thing that either appears or does not.
    expect(sosCard(window).hidden, 'the SOS feed must be hidden from a warehouse hand').toBe(true);
  });

  it('a seller sees orders and stock, and neither children nor the audit log', async () => {
    const { window } = await openAs('seller');
    const shown = (v: string) =>
      !(window.document.querySelector(`.nav[data-view="${v}"]`) as HTMLElement).hidden;

    expect(shown('shop')).toBe(true);
    expect(shown('stock')).toBe(true);
    expect(shown('users')).toBe(true); // contacts — «контакты» is in her list
    for (const v of ['kids', 'devices', 'audit', 'staff']) {
      expect(shown(v), `${v} must be hidden from a seller`).toBe(false);
    }
    expect(sosCard(window).hidden, 'the SOS feed must be hidden from a seller').toBe(true);
  });

  it('an operator gets the alarms but not where the children are', async () => {
    // The merge put two capabilities on one screen. An operator holds
    // `emergencies` and not `health`, so she must reach the feed and not the
    // geofence table — the exact leak the merge could have introduced.
    const { window, errors } = await openAs('operator');
    expect(errors, errors.join('\n')).toEqual([]);
    expect((window.document.querySelector('.nav[data-view="emergencies"]') as HTMLElement).hidden)
      .toBe(false);
    expect(sosCard(window).hidden, 'an operator must not see where children are').toBe(true);
  });

  it('a clinician gets both halves of the Экстренные screen', async () => {
    const { window } = await openAs('clinician');
    expect((window.document.querySelector('.nav[data-view="emergencies"]') as HTMLElement).hidden)
      .toBe(false);
    expect(sosCard(window).hidden).toBe(false);
  });

  it('a content editor sees the CMS and the course, and no orders', async () => {
    const { window } = await openAs('content');
    const shown = (v: string) =>
      !(window.document.querySelector(`.nav[data-view="${v}"]`) as HTMLElement).hidden;
    expect(shown('content')).toBe(true);
    expect(shown('course')).toBe(true);
    expect(shown('audio')).toBe(true);
    expect(shown('shop')).toBe(false);
    expect(shown('users')).toBe(false);
  });

  it('the dashboard cards go with the tabs', async () => {
    // Hiding «Склад» in the rail while the Продажи card still sits on the home
    // screen is the same leak with an extra click removed.
    const { window } = await openAs('warehouse');
    const cards = [...window.document.querySelectorAll('.card[data-cap]')] as HTMLElement[];
    expect(cards.length, 'no dashboard card declares a capability').toBeGreaterThan(3);
    for (const card of cards) {
      const allowed = card.dataset.cap === 'stock';
      expect(card.hidden, `card '${card.dataset.cap}'`).toBe(!allowed);
    }
  });
});

describe('a hidden tab is not reachable by other means', () => {
  it('a bookmarked #audit does not open the audit log for a seller', async () => {
    // The owner's browser, handed to somebody else. The server would refuse
    // the data; what this stops is the panel standing on a blank tab.
    const { window } = await openAs('seller', '#audit');
    expect((window.document.querySelector('#audit') as HTMLElement).classList.contains('active'))
      .toBe(false);
    const active = window.document.querySelector('.nav.active') as HTMLElement | null;
    expect(active).not.toBeNull();
    expect(active!.hidden).toBe(false);
  });

  it('a role with no dashboard still lands somewhere real', async () => {
    const { window } = await openAs('warehouse');
    const active = window.document.querySelector('.nav.active') as HTMLElement;
    expect(active.hidden).toBe(false);
    const view = window.document.querySelector(`#${active.dataset.view}`) as HTMLElement;
    expect(view.classList.contains('active')).toBe(true);
  });
});

describe('the roster can hand out every role the server accepts', () => {
  it('the add-staff picker offers all of them, each explained', async () => {
    const source = readFileSync(PANEL, 'utf8');
    const labels = source.match(/const roleLbl=\{([\s\S]*?)\n  \};/)![1];
    for (const role of STAFF_ROLES) {
      expect(labels, `no label for ${role} — it can be guarded but not granted`)
        .toMatch(new RegExp(`\\b${role}:`));
      // A bare slug tells whoever is adding a colleague nothing about how much
      // of other people's data they are about to hand over.
      expect(labels).toMatch(new RegExp(`\\b${role}:"${role} — .{8,}"`));
    }
  });

  it('every role has a Russian word for the sidebar footer', async () => {
    // The footer prints ROLE_RU[role]. A role missing from it falls back to the
    // English key — which is the defect the footer was built to end.
    const ru = readFileSync(PANEL, 'utf8').match(/const ROLE_RU=\{([\s\S]*?)\n {2}\};/)![1];
    for (const role of STAFF_ROLES) {
      expect(ru, `no Russian label for ${role} — the footer would print the wire key`)
        .toMatch(new RegExp(`\\b${role}:"[^"]+"`));
    }
    const { window } = await openAs('warehouse');
    expect(window.document.getElementById('staffRole')!.textContent).toBe('склад');
  });
});
