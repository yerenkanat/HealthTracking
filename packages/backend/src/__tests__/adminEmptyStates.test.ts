/**
 * «Пустые состояния говорят причину и одно действие.»
 *
 * The last unmet line of docs/CLAUDE-admin-design.md's merge checklist.
 *
 * A panel full of «Пока нет данных» is indistinguishable from a panel that
 * failed to load, and the two call for opposite responses: one is "wait", the
 * other is "somebody go and look". Worse, several of these screens are empty
 * for reasons the reader cannot act on at all — a child appears in the fleet
 * when a mother adds it in the app, and there is no button here that will ever
 * change that. Saying so is the difference between a screen that is waiting and
 * one that is broken.
 *
 * Read from the source rather than rendered. Every one of these lives in a
 * branch that needs a differently-shaped empty payload, and eleven jsdom boots
 * to assert eleven strings buys nothing over reading the strings — what matters
 * is that none of them is a bare "нет данных", and that is a property of the
 * text. The two that ARE rendered elsewhere (the review queue, the stock
 * banner) are covered in their own files.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = readFileSync(resolve(here, '../../../admin/index.html'), 'utf8');

/**
 * Every empty state the panel can paint, pulled from its two helpers.
 *
 * `dashEmpty` fills a dashboard card; `tableNote` fills a table body. Anything
 * that is neither is a one-off, and the count check below is what stops this
 * file quietly measuring three strings after somebody adds a third helper.
 */
function emptyStates(): string[] {
  const out: string[] = [];
  for (const re of [/dashEmpty\("([^"]+)"\)/g, /tableNote\(\d+,\s*"([^"]+)"\)/g]) {
    for (const m of PANEL.matchAll(re)) out.push(m[1]);
  }
  return out;
}

/** A failure is not an empty state: "could not load" is a different screen. */
const isFailure = (s: string) => /Не удалось|Проверьте доступ/.test(s);

describe('every empty state says more than "nothing here"', () => {
  it('found them — this file is worthless if the helpers get renamed', () => {
    const all = emptyStates();
    expect(all.length).toBeGreaterThan(8);
    expect(all.some((s) => s.includes('складе'))).toBe(true);
  });

  it('none is a bare statement of absence', () => {
    // The shape being banned is one short sentence ending in "нет." — which is
    // exactly what the panel used to say on seven screens.
    const bare = emptyStates()
      .filter((s) => !isFailure(s))
      .filter((s) => s.length < 45);
    expect(
      bare,
      `these say that something is missing and nothing else: ${bare.join(' | ')}. ` +
        'Add why it is empty and what happens next.',
    ).toEqual([]);
  });

  it('each one either names a next step or says what fills it', () => {
    // Two honest kinds. Some of these screens have an action — «оприходуйте
    // поставку», «откройте доступ». Others fill themselves when a mother does
    // something in the app, and pretending otherwise would send somebody
    // looking for a button that does not exist.
    // An imperative, by its ending rather than by a list of verbs. The list
    // version passed until the moment somebody wrote «Записывайте» — a
    // whitelist of words is a whitelist of the words already written.
    // `\b` is no use here: JavaScript defines a word boundary over ASCII, so a
    // Cyrillic letter is a non-word character and there is never a boundary
    // after «…йте». A lookahead for "not a letter" is the same intent that
    // works on this alphabet.
    const ACTION = /[а-яё]{3}(йте|ите)(?![а-яё])|вкладк|форме выше/i;
    const FILLS_ITSELF = /появ(ится|ятся|ляется|ляются)|приходят|входит/i;

    const silent = emptyStates()
      .filter((s) => !isFailure(s))
      .filter((s) => !ACTION.test(s) && !FILLS_ITSELF.test(s));
    expect(
      silent,
      `these do not say what to do or what will fill them: ${silent.join(' | ')}`,
    ).toEqual([]);
  });

  it('a failure to load still reads as a failure, not as emptiness', () => {
    // The other half of the rule. «Заказов пока нет» shown because the request
    // 500ed is the worst message on the panel: it is calmly, confidently wrong.
    const failures = emptyStates().filter(isFailure);
    expect(failures.length).toBeGreaterThan(2);
    for (const f of failures) {
      expect(f, `"${f}" reads as emptiness rather than a failure`).toMatch(/Не удалось/);
    }
  });
});
