/**
 * The back-office design system, as docs/CLAUDE-admin-design.md states it.
 *
 * §1 is the whole argument: an operator looks at this for eight hours and works
 * from the keyboard, so the panel is dense tables, small radii, tabular figures
 * and colour only where it means something. The app's warm padded look is
 * deliberately NOT carried across, and these assertions exist so the next
 * person who likes the app's cards does not quietly bring them here.
 *
 * Read from the stylesheet rather than a rendered pixel: these are rules about
 * the system, and jsdom does not do layout anyway.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const panel = readFileSync(resolve(here, '../../../admin/index.html'), 'utf8');

/** The `:root` block — the light theme's tokens. */
const root = panel.slice(panel.indexOf(':root{'), panel.indexOf('}', panel.indexOf(':root{')));

describe('the admin is denser than the app, on purpose', () => {
  it('reads at 13px, not the app 15', () => {
    expect(panel).toMatch(/body\{[^}]*font-size:13px/);
  });

  it('lines its numbers up', () => {
    // Figures live in columns here. Proportional digits make a stock count
    // unreadable at a glance, which is the one thing this screen is for.
    expect(panel).toMatch(/body\{[^}]*font-variant-numeric:tabular-nums/);
  });

  it('uses a container radius, not a pillow', () => {
    expect(root).toContain('--r:10px');
  });

  it('gives a table row 10px of padding, not 13', () => {
    expect(panel).toMatch(/\btd\{padding:10px 16px/);
  });

  it('puts the table head on its own tint, uppercase and small', () => {
    expect(panel).toMatch(/\bth\{[^}]*font-size:11px/);
    expect(panel).toMatch(/\bth\{[^}]*letter-spacing:\.06em/);
    expect(panel).toMatch(/\bth\{[^}]*background:var\(--surface-2\)/);
  });
});

describe('the navigation is dark chrome', () => {
  it('the rail is the ink colour, not a white surface', () => {
    // Taking navigation out of the reading area is what lets the tables be as
    // quiet as they are.
    expect(root).toContain('--side:#1E1A1D');
    expect(panel).toMatch(/\.side\{background:var\(--side\)/);
  });

  it('the active item is a white plate', () => {
    // On a dark rail a tinted pill does not read; the spec asks for a plate.
    expect(panel).toMatch(/\.nav\.active\{background:#fff/);
  });

  it('is 216px wide', () => {
    expect(panel).toContain('grid-template-columns:216px 1fr');
  });
});

describe('colour says something or is not used', () => {
  it('the action colour is the spec crimson', () => {
    expect(root).toContain('--accent:#C2003F');
    expect(root).toContain('--danger:#A8002F');
  });

  it('a row needing attention is tinted, never recoloured text', () => {
    // Colour on the text competes with the status chip already saying it.
    expect(panel).toMatch(/tbody tr\.attn-warn\{background:var\(--warn-soft\)/);
    expect(panel).toMatch(/tbody tr\.attn-crit\{background:var\(--crit-soft\)/);
  });

  it('status chips are chips, not badges', () => {
    expect(panel).toMatch(/\.pill\{[^}]*border-radius:5px/);
    // The old style shouted in uppercase inside a dense row.
    expect(panel).not.toMatch(/\.pill\{[^}]*text-transform:uppercase/);
  });
});

describe('the fonts the spec names', () => {
  it('asks for Manrope and JetBrains Mono', () => {
    expect(panel).toContain('family=Manrope');
    expect(panel).toContain('family=JetBrains+Mono');
  });

  it('keeps system fallbacks behind both', () => {
    // A blocked or slow CDN must cost shape, not the panel. Staff use this to
    // run the business; it cannot depend on Google being reachable.
    expect(root).toMatch(/--sans:"Manrope",system-ui/);
    expect(root).toMatch(/--mono:"JetBrains Mono",ui-monospace/);
  });

  it('loads them without blocking on the network', () => {
    expect(panel).toContain('display=swap');
    expect(panel).toContain('rel="preconnect"');
  });
});
