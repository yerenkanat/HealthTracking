/**
 * Nothing reaches a Kazakh mother in Russian without her being told.
 *
 * docs/CLAUDE-admin-design.md §"Публикация контента": «Двуязычность
 * обязательна: без казахской версии кнопка «Опубликовать» заблокирована.»
 *
 * The app's fallback is one line — `byLocale[locale] ?? byLocale['ru']` — and
 * it is the right fallback: a card with an empty title is worse than a card in
 * the wrong language. What made it a defect is that it is SILENT. A woman who
 * set the app to Kazakh gets Russian guidance about her own pregnancy, with
 * nothing on the screen to say the translation is missing rather than that the
 * app ignored her choice, and nobody in the back office can see it either.
 *
 * So the rule is enforced where the content is written, which is the only place
 * a person can act on it.
 *
 * PURE: takes a record of locale → text and answers what is missing. No schema
 * library, no repository, so the same check runs on one item, on a bulk import
 * of a hundred stages, and in a test.
 */

/**
 * The two the product ships in.
 *
 * `en` exists in the app's own strings and in demo content, but nothing is
 * SOLD in English — the landing, the packaging and the support line are Russian
 * and Kazakh — so an English translation is welcome and never required.
 */
export const REQUIRED_LOCALES = ['ru', 'kk'] as const;
export type RequiredLocale = (typeof REQUIRED_LOCALES)[number];

/** Present and not just whitespace. A title of "  " renders as a blank card. */
function has(text: Record<string, string> | undefined, locale: string): boolean {
  return (text?.[locale] ?? '').trim().length > 0;
}

/**
 * Which required locales this piece of text is missing.
 *
 * Empty means it is ready. The order is [REQUIRED_LOCALES]' order, so the
 * message a person reads is stable rather than dependent on object key order.
 */
export function missingLocales(text: Record<string, string> | undefined): RequiredLocale[] {
  return REQUIRED_LOCALES.filter((l) => !has(text, l));
}

export interface BilingualProblem {
  /** Which item — the id a person sees in the CMS. */
  id: string;
  /** Which field of it: 'title' or 'summary'. */
  field: string;
  /** What is not there yet. */
  missing: RequiredLocale[];
}

/**
 * Check every translatable field of one item.
 *
 * Both fields are reported, not just the first: someone fixing a card wants to
 * know it needs a Kazakh summary too, rather than saving, being refused again,
 * and learning the requirements one round trip at a time.
 */
export function bilingualProblems(item: {
  id: string;
  title?: Record<string, string>;
  summary?: Record<string, string>;
}): BilingualProblem[] {
  const out: BilingualProblem[] = [];
  for (const field of ['title', 'summary'] as const) {
    const missing = missingLocales(item[field]);
    if (missing.length) out.push({ id: item.id, field, missing });
  }
  return out;
}

const LOCALE_NAME: Record<RequiredLocale, string> = { ru: 'русской', kk: 'казахской' };
const FIELD_NAME: Record<string, string> = { title: 'заголовка', summary: 'описания' };

/**
 * The problems as a sentence somebody can act on, in the language the panel is
 * written in.
 *
 * A 400 that says "validation failed" sends a content editor to ask a
 * developer. This one names the card, the field and the language.
 */
export function bilingualMessage(problems: BilingualProblem[]): string {
  return problems
    .map((p) => `«${p.id}»: нет ${p.missing.map((l) => LOCALE_NAME[l]).join(' и ')} версии ` +
      `${FIELD_NAME[p.field] ?? p.field}`)
    .join('; ');
}
