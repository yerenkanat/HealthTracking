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
  /** Which field of it: 'title', 'summary', 'body' or 'redFlags'. */
  field: string;
  /** What is not there yet. */
  missing: RequiredLocale[];
}

/** Nothing written in ANY language — the field has not been started. */
function unwritten(text: Record<string, string> | undefined): boolean {
  return Object.values(text ?? {}).every((v) => (v ?? '').trim().length === 0);
}

/**
 * Check every translatable field of one item.
 *
 * All fields are reported, not just the first: someone fixing a card wants to
 * know it needs a Kazakh summary too, rather than saving, being refused again,
 * and learning the requirements one round trip at a time.
 *
 * TWO CLASSES OF FIELD, and the difference is the whole reason this is not one
 * loop.
 *
 * `title` and `summary` are the card itself — a card without them is not a
 * card, so both languages are always required.
 *
 * `body` and `redFlags` (admin frame 16a — the article) are OPTIONAL, and have
 * to stay optional: 364 items were published before an article could be written
 * at all, and none of them carries one. Requiring both languages of a field
 * nobody has filled in would refuse every save of every existing stage — the
 * bilingual rule would go from "publish in both languages" to "the CMS is
 * broken", and the way round a broken CMS is to stop using the field.
 *
 * So an unwritten article is not a problem; a HALF-WRITTEN one is. The moment
 * somebody types a Russian paragraph, the Kazakh one is required — which is the
 * rule as written, applied at the point it starts to mean something.
 */
export function bilingualProblems(item: {
  id: string;
  title?: Record<string, string>;
  summary?: Record<string, string>;
  body?: Record<string, string>;
  redFlags?: Record<string, string>;
}): BilingualProblem[] {
  const out: BilingualProblem[] = [];
  for (const field of ['title', 'summary'] as const) {
    const missing = missingLocales(item[field]);
    if (missing.length) out.push({ id: item.id, field, missing });
  }
  for (const field of ['body', 'redFlags'] as const) {
    if (unwritten(item[field])) continue;
    const missing = missingLocales(item[field]);
    if (missing.length) out.push({ id: item.id, field, missing });
  }
  return out;
}

const LOCALE_NAME: Record<RequiredLocale, string> = { ru: 'русской', kk: 'казахской' };
const FIELD_NAME: Record<string, string> = {
  title: 'заголовка',
  summary: 'описания',
  // The pregnancy calendar's three fields (frame 14b). Named here rather than
  // in the route so both editors refuse a save in the same words — a content
  // editor who has seen this sentence on a timeline card should not have to
  // learn a second dialect of it on the week screen.
  baby: 'текста «О малыше»',
  you: 'текста «О вас»',
  recommend: 'рекомендации',
  // The immunisation calendar's two fields (frames 15 / 15a). Same reasoning as
  // the pregnancy fields above: one dialect of this sentence across the whole
  // back office.
  name: 'названия прививки',
  note: 'пояснения к прививке',
  // The article (frame 16a). A guide used to be a headline and a link out; the
  // text itself now lives here, and a half-translated article is exactly the
  // silent Russian fallback this module exists to stop — only longer.
  body: 'текста статьи',
  redFlags: 'блока «Красный флаг»',
};

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
