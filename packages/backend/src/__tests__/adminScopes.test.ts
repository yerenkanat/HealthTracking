/**
 * The admin page is two script blocks, and they cannot see each other.
 *
 * One is the dashboard, the other the content editor. Each is an IIFE, so a
 * `const` in one is invisible to the other — and a name used across that
 * boundary throws a ReferenceError at the moment of use, inside an async
 * loader, where nothing surfaces it. Every one of those loaders catches and
 * renders its empty row, so the failure arrives as "nothing here yet".
 *
 * That is not hypothetical. `STAFF` was declared in the first block and used by
 * the second block's api() for its auth headers, under a comment reading
 * "deliberately NOT redeclared — see the single STAFF identity above". The
 * intent was right and JavaScript does not work that way: every request that
 * file made threw before it was sent, and Устройства, Безопасность and Контент
 * displayed "nothing here yet" against a server answering 200 with data.
 *
 * Nothing failed. No test noticed. The page looked like a product with no
 * devices rather than a page that could not ask.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(resolve(here, '../../../admin/index.html'), 'utf8');

/** Drop comments and string/template literals so only real code is scanned. */
function code(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1 ')
    .replace(/`(?:\\.|[^`\\])*`/g, '``')
    .replace(/'(?:\\.|[^'\\])*'/g, "''")
    .replace(/"(?:\\.|[^"\\])*"/g, '""');
}

/** The two top-level IIFEs, as source. */
function blocks(): string[] {
  const parts = html.split(/\n\(function\s*\(\)\s*\{/);
  expect(parts.length, 'expected two top-level IIFEs').toBeGreaterThanOrEqual(3);
  return parts.slice(1).map(code);
}

/** Names a block declares: function/const/let/var, and destructured bindings. */
function declared(src: string): Set<string> {
  const out = new Set<string>();
  for (const m of src.matchAll(/\b(?:function|const|let|var|class)\s+([A-Za-z_$][\w$]*)/g)) {
    out.add(m[1]);
  }
  // const { a, b: c } = ... — the bound name is what matters.
  for (const m of src.matchAll(/\b(?:const|let|var)\s*\{([^}]*)\}\s*=/g)) {
    for (const piece of m[1].split(',')) {
      const name = piece.includes(':') ? piece.split(':')[1] : piece;
      const clean = name.trim().replace(/\s*=.*$/, '');
      if (clean) out.add(clean);
    }
  }
  for (const m of src.matchAll(/(?:^|[;{}\s])([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\(/g)) out.add(m[1]);
  // Parameters are declarations too. Without these, every `s`, `e` and `row`
  // used as an argument name looks like a name borrowed from the other block.
  for (const m of src.matchAll(/(?:function\s*[\w$]*\s*|catch\s*)\(([^)]*)\)/g)) {
    for (const p of m[1].split(',')) out.add(p.trim().replace(/[={].*$/, '').trim());
  }
  for (const m of src.matchAll(/\(([^)(]*)\)\s*=>/g)) {
    for (const p of m[1].split(',')) out.add(p.trim().replace(/[={].*$/, '').trim());
  }
  for (const m of src.matchAll(/(?:^|[^\w$.])([A-Za-z_$][\w$]*)\s*=>/g)) out.add(m[1]);
  return out;
}

/**
 * Names the FIRST block declares at its top level.
 *
 * Only these are shareable, and only these are worth checking: a name nested
 * inside a function there was never reachable from anywhere anyway. The file
 * indents top-level declarations by exactly two spaces.
 */
function topLevel(src: string): Set<string> {
  const out = new Set<string>();
  for (const m of src.matchAll(/^ {2}(?:function|const|let|var|class)\s+([A-Za-z_$][\w$]*)/gm)) {
    out.add(m[1]);
  }
  return out;
}

describe('the two script blocks do not reach into each other', () => {
  it('found both blocks and read real code', () => {
    const [a, b] = blocks();
    expect(a.length).toBeGreaterThan(2000);
    expect(b.length).toBeGreaterThan(2000);
    expect(declared(a).size).toBeGreaterThan(15);
    expect(declared(b).size).toBeGreaterThan(10);
  });

  it('the second block declares or imports every name it uses from the first', () => {
    const [first, second] = blocks();
    const mine = declared(second);
    const theirs = topLevel(first);

    // Names the second block references that only the first block declares.
    const borrowed = [...theirs].filter(
      (n) => !mine.has(n) && new RegExp(String.raw`\b${n}\b`).test(second),
    );

    expect(
      borrowed,
      `these are declared in the dashboard block and used by the content block, ` +
        `which cannot see them: ${borrowed.join(', ')}. Pass them through window.UI ` +
        `and destructure at the top, as STAFF and the formatters are.`,
    ).toEqual([]);
  });

  it('anything shared goes through one explicit handoff', () => {
    // A single named object, so the seam is greppable rather than a scattering
    // of window.foo assignments nobody can enumerate.
    const [first] = blocks();
    expect(first).toMatch(/window\.UI\s*=\s*\{/);
    const strays = [...html.matchAll(/window\.([A-Za-z_$][\w$]*)\s*=/g)]
      .map((m) => m[1])
      .filter((n) => n !== 'UI' && n !== 'onerror' && n !== 'onunhandledrejection');
    expect(strays, `share through window.UI, not window.${strays[0]}`).toEqual([]);
  });
});
