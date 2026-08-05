/**
 * `hidden` has to actually hide.
 *
 * The bug this exists for cost the owner two days. Signing in set
 * `gate.hidden = true` and the card stayed on screen, because the `hidden`
 * attribute works only through the user-agent stylesheet's `display:none` and
 * ANY author rule setting `display` outranks it — here `.loginwrap{display:grid}`.
 *
 * So the panel behind it had loaded perfectly: /admin/me answered 200, every
 * view fetched its data, the page polled every 20 seconds. Nothing was broken
 * and there was no error to show, because nothing had failed. The owner typed a
 * correct password into a screen that had no reason to respond, over and over,
 * while the server logged successful sign-in after successful sign-in.
 *
 * This is a SOURCE-level check, and deliberately so: jsdom's getComputedStyle
 * does not model this part of the cascade. A test written against it passed
 * with the bug reintroduced — it could not fail, which makes it worse than no
 * test. What can be checked honestly is that the rule exists and that no
 * element toggled by `hidden` has a `display` rule able to beat it.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');
const html = readFileSync(PANEL, 'utf8');

/** Every class on an element that carries the `hidden` attribute in the markup. */
function classesToggledByHidden(): Set<string> {
  const out = new Set<string>();
  // Tags that have both a class attribute and a bare `hidden`.
  for (const tag of html.match(/<[a-z]+[^>]*\bhidden\b[^>]*>/g) ?? []) {
    const cls = tag.match(/class="([^"]+)"/);
    if (cls) for (const c of cls[1].split(/\s+/)) if (c) out.add(c);
  }
  return out;
}

describe('the hidden attribute', () => {
  it('is enforced globally', () => {
    // Without this line, every `element.hidden = true` in the panel is a
    // suggestion that any `display` rule can ignore.
    expect(html, 'no global [hidden] rule — see the header of this file')
      .toMatch(/\[hidden\]\s*\{\s*display:\s*none\s*!important\s*\}/);
  });

  it('found elements that use it', () => {
    // The vacuity guard. If the markup scan stops matching, the check below
    // passes over an empty set and proves nothing.
    const classes = classesToggledByHidden();
    expect(classes.size, 'no hidden elements found — the scan is broken').toBeGreaterThan(2);
    // The two that mattered: the sign-in overlay and the dashboard behind it.
    expect(classes.has('loginwrap'), 'the sign-in gate is no longer toggled by hidden').toBe(true);
    expect(classes.has('app'), 'the dashboard shell is no longer toggled by hidden').toBe(true);
  });

  it('beats every display rule on the elements it toggles', () => {
    // The global rule is !important, so this can only fail if someone writes an
    // !important display of their own. Named here so the next person sees why
    // that would be a bad idea rather than discovering it the way we did.
    const offenders: string[] = [];
    for (const cls of classesToggledByHidden()) {
      const rule = new RegExp(`\\.${cls}\\s*\\{[^}]*display:[^;}]*!important`, 'i');
      if (rule.test(html)) offenders.push(cls);
    }
    expect(offenders, `these override the [hidden] rule: ${offenders.join(', ')}`).toEqual([]);
  });
});
