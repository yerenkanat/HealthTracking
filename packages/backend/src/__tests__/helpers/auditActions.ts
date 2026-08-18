/**
 * The list of audit actions the server can write, read off the server.
 *
 * The panel translates an action key into a Russian phrase through
 * `AUDIT_ACTIONS` in `packages/admin/index.html`; anything missing from that
 * map falls through to `a.action` and prints the raw key. A Russian-speaking
 * reviewer then sees «broadcast_publish» beside the row, and the log that makes
 * staff access to a mother's record reviewable stops being reviewable.
 *
 * Four such keys were labelled by hand, and roughly twenty more were found the
 * same way — by diffing every `writeAudit` call site against the map. Doing
 * that once fixes today; a hardcoded list of expected keys in a test rots the
 * moment somebody adds a route. So this reads the CALL SITES, and the test
 * derives its expectation from them: a new unlabelled action fails the build
 * without anybody having to remember this file exists.
 *
 * Static, not runtime: exercising all ~80 routes would need every capability,
 * every fixture and every 4xx path, and the ones hardest to reach are exactly
 * the ones a label would be forgotten for.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve, sep } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
/** packages/backend/src */
const SRC = resolve(here, '../..');
/** packages/admin/index.html */
export const PANEL_HTML = resolve(here, '../../../../admin/index.html');

export interface AuditCallSite {
  /** The string that reaches the `action` column. */
  key: string;
  /** Repo-relative path and line, so a failure names what to open. */
  where: string;
}

/**
 * Action keys built from an expression rather than written as a literal.
 *
 * There is one, and resolving it needs a fact the call site does not carry —
 * the enum of the status it interpolates. Rather than guess, the expression
 * source is matched exactly and expanded here. A NEW template expression, or an
 * edit to this one, is not in the table and throws: unresolved beats silently
 * dropped, because a dropped key is an unlabelled action that no longer fails.
 */
const TEMPLATE_KEYS: Record<string, string[]> = {
  // routes/inventory.ts, POST /admin/device-registry/:serial/status.
  // The status is z.enum(['stock', 'sold', 'blocked']) at the top of that file.
  'device_${parsed.data.status}': ['device_stock', 'device_sold', 'device_blocked'],
};

/**
 * Labels kept for actions nothing writes any more.
 *
 * Not dead code to delete: the rows are still in the production audit table and
 * still have to read as Russian. Every entry names what replaced it, so this
 * cannot quietly become a bin for typos.
 */
export const RETIRED_ACTIONS: Record<string, string> = {
  // Retired in 612c413 — GET /admin/users/:id/health was folded into the mother
  // card, which audits as view_user_detail under the same guard.
  view_health: 'view_user_detail',
  // Retired in 1b2b37b — POST /admin/settings/test-telegram became
  // POST /admin/integrations/telegram/check, which audits as integration_check.
  test_telegram: 'integration_check',
};

function tsFiles(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    // Tests write audit rows of their own; those are fixtures, not routes, and
    // counting them would let a test invent a requirement for the panel.
    if (e.isDirectory()) { if (e.name !== '__tests__') tsFiles(p, out); }
    else if (e.name.endsWith('.ts')) out.push(p);
  }
  return out;
}

/** The argument text of every `writeAudit(...)`, by balanced parenthesis. */
function writeAuditArgs(src: string): { arg: string; line: number }[] {
  const out: { arg: string; line: number }[] = [];
  const re = /writeAudit\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    let i = m.index + m[0].length;
    let depth = 1;
    while (i < src.length && depth > 0) {
      const c = src[i];
      if (c === '(') depth += 1;
      else if (c === ')') depth -= 1;
      i += 1;
    }
    out.push({
      arg: src.slice(m.index + m[0].length, i - 1),
      line: src.slice(0, m.index).split('\n').length,
    });
  }
  return out;
}

/**
 * Every action key any route in `packages/backend/src` can write.
 *
 * Throws on an `action:` it cannot resolve. That is deliberate: a silent skip
 * would turn "we cannot tell" into "nothing to check".
 */
export function auditCallSites(): AuditCallSite[] {
  const found: AuditCallSite[] = [];
  for (const file of tsFiles(SRC)) {
    const src = readFileSync(file, 'utf8');
    const cut = file.indexOf(`packages${sep}backend`);
    const where = (cut < 0 ? file : file.slice(cut)).split(sep).join('/');
    for (const { arg, line } of writeAuditArgs(src)) {
      const at = `${where}:${line}`;
      // The interface declaration and the pg implementation take the entry as a
      // parameter; only calls that name an action are call sites.
      if (!/\baction\s*:\s*[^;]/.test(arg) || /action\s*:\s*string/.test(arg)) continue;

      const literal = arg.match(/\baction:\s*'([^']*)'/);
      if (literal) { found.push({ key: literal[1], where: at }); continue; }

      const ternary = arg.match(/\baction:\s*[^?'"`]*\?\s*'([^']*)'\s*:\s*'([^']*)'/);
      if (ternary) {
        found.push({ key: ternary[1], where: at }, { key: ternary[2], where: at });
        continue;
      }

      const template = arg.match(/\baction:\s*`([^`]*)`/);
      if (template) {
        const keys = TEMPLATE_KEYS[template[1]];
        if (!keys) {
          throw new Error(
            `${at}: writeAudit builds its action from an expression this helper cannot expand ` +
            `(${template[1]}). Add it to TEMPLATE_KEYS in ` +
            'src/__tests__/helpers/auditActions.ts with the enum it interpolates, ' +
            'or write the key out as a literal.',
          );
        }
        for (const key of keys) found.push({ key, where: at });
        continue;
      }

      throw new Error(
        `${at}: could not read the action out of ` +
        `writeAudit(${arg.replace(/\s+/g, ' ').slice(0, 120)})`,
      );
    }
  }
  return found;
}

/** Distinct action keys, each with one call site to name in a failure. */
export function auditActionKeys(): Map<string, string> {
  const byKey = new Map<string, string>();
  for (const { key, where } of auditCallSites()) if (!byKey.has(key)) byKey.set(key, where);
  return byKey;
}

/**
 * The panel's label map, evaluated rather than pattern-matched.
 *
 * `packages/admin/index.html` is one 840 KB file and the map is a plain object
 * literal inside it, so the block is cut out by brace balance and evaluated. A
 * regex over the lines would count a commented-out key as present, which is
 * the exact failure this is guarding.
 */
export function panelAuditLabels(html = readFileSync(PANEL_HTML, 'utf8')): Record<string, string> {
  const marker = 'const AUDIT_ACTIONS={';
  const start = html.indexOf(marker);
  if (start < 0) throw new Error('AUDIT_ACTIONS is gone from packages/admin/index.html');
  if (html.indexOf(marker, start + 1) >= 0) throw new Error('AUDIT_ACTIONS is declared twice');

  let i = start + marker.length;
  let depth = 1;
  let quote: string | null = null;
  let lineComment = false;
  let blockComment = false;
  while (i < html.length && depth > 0) {
    const c = html[i];
    const next = html[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; }
    else if (blockComment) { if (c === '*' && next === '/') { blockComment = false; i += 1; } }
    else if (quote) { if (c === '\\') i += 1; else if (c === quote) quote = null; }
    else if (c === '/' && next === '/') { lineComment = true; i += 1; }
    else if (c === '/' && next === '*') { blockComment = true; i += 1; }
    else if (c === '"' || c === "'" || c === '`') quote = c;
    else if (c === '{') depth += 1;
    else if (c === '}') depth -= 1;
    i += 1;
  }
  if (depth !== 0) throw new Error('AUDIT_ACTIONS is not closed — the panel would not parse');

  const literal = html.slice(start + marker.length - 1, i);
  return new Function(`return (${literal});`)() as Record<string, string>;
}
