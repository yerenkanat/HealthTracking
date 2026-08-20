/**
 * A name typed by a stranger must not become script in the back office.
 *
 * `POST /shop/leads` is unauthenticated, routed to the public internet, and
 * validated only for length. The name it carries is rendered by the panel into
 * a double-quoted HTML attribute:
 *
 *     <select class="lstatus" data-who="${esc(l.customerName)}" …>
 *
 * Until 2026-08-20 the `esc` in that script block replaced only `& < >`. A
 * name of `Aigul" onfocus=alert(1) autofocus x="` broke out of the attribute
 * and ran in the panel's origin — as the signed-in owner, with their whole
 * capability set. HttpOnly does not help: the panel's own fetch is
 * `credentials: "same-origin"`, so injected script does not need to read the
 * cookie, it just calls `/admin/users/:id/detail` and `/admin/safety` as the
 * owner and walks every family's health record and every child's location out
 * of the building. The audit log would record those reads as the owner's,
 * under a reason the attacker chose — the accountability mechanism actively
 * lying about what happened.
 *
 * The panel has TWO `esc` helpers in two script blocks. The other one already
 * escaped `"`. Two functions with the same name and different behaviour is why
 * this survived review, so this file checks EVERY one it can find rather than
 * a single known line.
 *
 * There was no test matching xss|escape|inject in 190 backend test files.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const panel = readFileSync(
  fileURLToPath(new URL('../../../admin/index.html', import.meta.url)),
  'utf8',
);

/** Every `.replace(/…/g` character class used by an `esc` definition. */
function escCharClasses(): string[] {
  const out: string[] = [];
  const re = /esc\s*(?:=\s*\(s\)\s*=>|\(s\)\s*\{[^}]*?)[\s\S]{0,120}?replace\(\/\[([^\]]+)\]\/g/g;
  for (let m = re.exec(panel); m; m = re.exec(panel)) out.push(m[1]);
  return out;
}

describe('the admin panel escapes what strangers type', () => {
  it('every esc() escapes both tag delimiters AND the double quote', () => {
    const classes = escCharClasses();
    // Floor: a regex that matches nothing would make this file vacuous, which
    // is the failure mode of every source-reading guard.
    expect(classes.length, 'found no esc() definitions — the scan broke')
      .toBeGreaterThanOrEqual(2);

    for (const cls of classes) {
      expect(cls, `esc() with class [${cls}] does not escape a double quote, and `
        + 'this panel interpolates esc() inside double-quoted attributes')
        .toContain('"');
      expect(cls, `esc() with class [${cls}] does not escape <`).toContain('<');
      expect(cls, `esc() with class [${cls}] does not escape &`).toContain('&');
    }
  });

  it('the hostile name cannot break out of the leads attribute', () => {
    // Run the panel's own function rather than a copy of it: a test that
    // reimplements the escape proves nothing about the shipped one.
    const src = panel.match(/function esc\(s\)\{return String\(s\)[^\n]*\}/);
    expect(src, 'the leads-row esc() is no longer a findable function').not.toBeNull();
    // eslint-disable-next-line no-new-func
    const esc = new Function(`${src![0]}; return esc;`)() as (s: string) => string;

    const hostile = 'Aigul" onfocus=alert(document.cookie) autofocus x="';
    const attr = `<select data-who="${esc(hostile)}">`;

    expect(attr, 'the attribute was broken out of').not.toContain('" onfocus');
    // NOT asserting the absence of the word «autofocus»: the escaped value
    // legitimately contains it, as inert text inside the quoted value. The
    // question is never whether hostile WORDS survive — it is whether the
    // value can leave its quotes. The quote count below answers that exactly,
    // and an assertion on the words would fail on a correct escape.
    expect(esc(hostile)).toContain('&quot;');
    // The whole hostile string must survive as ONE attribute value.
    expect(attr.match(/"/g)?.length, 'more quotes than the two delimiters').toBe(2);
  });

  it('the two script blocks do not disagree about escaping', () => {
    // The defect was not a missing character. It was two helpers with one name
    // behaving differently, so reviewing either one told you nothing about the
    // other.
    const classes = escCharClasses().map((c) => [...new Set(c)].sort().join(''));
    expect(new Set(classes).size,
      `esc() implementations differ: ${JSON.stringify(classes)}`).toBe(1);
  });
});
