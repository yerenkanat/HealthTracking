/**
 * Lift the legal copy out of the app's l10n table into legal/legal.json.
 *
 * Run once, by hand, to seed the shared file. After that legal/legal.json is
 * the SOURCE: the backend serves /privacy and /terms from it, the app reads
 * the same strings through its l10n table, and a test in each package fails if
 * the two ever say different things.
 *
 * Written as a file rather than `node -e` because the pattern needs escaped
 * quotes and backslashes, and passing those through a shell mangles them —
 * which is how the first two attempts at this produced an unterminated
 * character class.
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const L10N = resolve(here, '../app/lib/l10n/l10n.dart');
const OUT = resolve(here, '../legal/legal.json');

const src = readFileSync(L10N, 'utf8');

/** One `'key': { AppLocale.ru: '…', … },` entry, across however many lines. */
const ENTRY = /^ {2}'(legal_[a-z_]+)': \{([\s\S]*?)\},\s*$/gm;

/** A single-quoted Dart string, allowing escaped quotes inside. */
function valueFor(body, locale) {
  const re = new RegExp(String.raw`AppLocale\.${locale}: '((?:[^'\\]|\\.)*)'`);
  const m = body.match(re);
  if (!m) return null;
  // Decode Dart's escapes in ONE pass. Two chained replaces got \n wrong twice
  // over: it was not handled at all, so a paragraph break came out of here as
  // the two characters \ and n and every multi-paragraph section drifted from
  // the app the moment anyone re-ran this file.
  return m[1].replace(/\\(.)/g, (_, c) =>
    c === 'n' ? '\n' : c === 't' ? '\t' : c === 'r' ? '\r' : c);
}

const strings = {};
for (const m of src.matchAll(ENTRY)) {
  strings[m[1]] = {
    ru: valueFor(m[2], 'ru'),
    kk: valueFor(m[2], 'kk'),
    en: valueFor(m[2], 'en'),
  };
}

const missing = Object.entries(strings)
  .filter(([, v]) => !v.ru || !v.kk || !v.en)
  .map(([k]) => k);
if (missing.length) {
  console.error('incomplete translations:', missing.join(', '));
  process.exit(1);
}

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, `${JSON.stringify({ strings }, null, 2)}\n`);
console.log(`wrote ${Object.keys(strings).length} strings to legal/legal.json`);
