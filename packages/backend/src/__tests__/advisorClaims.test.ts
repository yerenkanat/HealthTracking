/**
 * The app must hold ITSELF to the standard it holds the model to.
 *
 * The guardrail blocks the assistant from telling a woman that her specific
 * reading is fine — because a wrist PPG estimate carries ±10-15 mmHg and
 * declaring it healthy can mask something real. The advisor cards on the
 * dashboard are generated from the SAME estimated data and shown in the same
 * app, and the user cannot tell which layer produced a sentence.
 *
 * So every advisory string is run through the same filter the model's output
 * is. If a sentence would be refused coming from the assistant, it should not
 * be shipped as the app's own considered advice.
 *
 * Reads the Dart catalogue directly: the strings live there, and a copy here
 * would drift the moment someone edits the real one.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { _internal } from '../ai/AIGuardrailProcessor';

const l10n = readFileSync(
  fileURLToPath(new URL('../../../../app/lib/l10n/l10n.dart', import.meta.url)),
  'utf8',
);

/** Every advisory body, per locale, straight from the Dart catalogue. */
function advisoryStrings(): Array<{ key: string; locale: string; text: string }> {
  const out: Array<{ key: string; locale: string; text: string }> = [];
  // '  'ADV_X_b': {AppLocale.ru: '…', AppLocale.kk: '…', AppLocale.en: '…'},'
  const row = /'(ADV_[A-Z_0-9]+_b)':\s*\{([^}]*)\}/g;
  for (const m of l10n.matchAll(row)) {
    const key = m[1];
    const body = m[2];
    const entry = /AppLocale\.(ru|kk|en):\s*(['"])([\s\S]*?)\2\s*(?:,|$)/g;
    for (const e of body.matchAll(entry)) {
      out.push({ key, locale: e[1], text: e[3] });
    }
  }
  return out;
}

describe('advisory cards are held to the guardrail’s own standard', () => {
  const strings = advisoryStrings();

  it('found the advisory strings in the Dart catalogue', () => {
    // Guards the guard: a regex that silently matched nothing would make every
    // check below pass while proving nothing at all.
    expect(strings.length).toBeGreaterThan(30);
    expect(new Set(strings.map((s) => s.locale))).toEqual(new Set(['ru', 'kk', 'en']));
  });

  it('no advisory says something the assistant would be blocked from saying', () => {
    const offenders = strings
      .filter((s) => _internal.outputViolates(s.text))
      .map((s) => `${s.key} [${s.locale}]: ${s.text}`);
    expect(offenders, `these would be refused coming from the model:\n${offenders.join('\n')}`)
      .toEqual([]);
  });

  it('none of them prescribes', () => {
    // Belt and braces: the filter above already covers this, but naming it
    // separately means a future change to the reassurance rule cannot quietly
    // stop checking for prescribing.
    const drugs = /\b(ibuprofen|aspirin|paracetamol|ибупрофен|аспирин|парацетамол)\b/i;
    const dosed = /\d+\s*(mg|ml|мг|мл)/i;
    for (const s of strings) {
      expect(drugs.test(s.text), `${s.key} [${s.locale}] names a drug`).toBe(false);
      expect(dosed.test(s.text), `${s.key} [${s.locale}] carries a dose`).toBe(false);
    }
  });
});
