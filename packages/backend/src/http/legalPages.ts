/**
 * `/privacy` and `/terms` — the public legal pages.
 *
 * A store listing will not accept an app that handles a child's geolocation
 * and a woman's reproductive history without a PUBLICLY REACHABLE policy, and
 * Kazakh personal-data law wants one too. The app had these screens inside it,
 * where nobody can read them before installing and no reviewer can link to
 * them.
 *
 * ONE SOURCE. The copy comes from legal/legal.json, which is the same text the
 * app renders through its l10n table — see tools/extract-legal.mjs for how it
 * got there and legalPages.test.ts for the check that they have not since
 * parted company. Two policies that disagree is worse than one that is late:
 * whichever a customer read, the other one is the one we would be held to.
 *
 * The draft banner is carried through rather than dropped. The wording is
 * honest about what the app does and has not been through a lawyer, and a page
 * that quietly stops saying so is making a claim the repository cannot support.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';

export type LegalLocale = 'ru' | 'kk' | 'en';
export const LEGAL_LOCALES: readonly LegalLocale[] = ['ru', 'kk', 'en'];

export interface LegalStrings {
  [key: string]: Record<LegalLocale, string>;
}

/** The sections of each document, in the order the app renders them. */
export const PRIVACY_SECTIONS = [
  ['legal_priv_collect_h', 'legal_priv_collect_b'],
  ['legal_priv_storage_h', 'legal_priv_storage_b'],
  ['legal_priv_cloud_h', 'legal_priv_cloud_b'],
  ['legal_priv_medical_h', 'legal_priv_medical_b'],
  ['legal_priv_controls_h', 'legal_priv_controls_b'],
  ['legal_priv_contact_h', 'legal_priv_contact_b'],
] as const;

export const TERMS_SECTIONS = [
  ['legal_terms_use_h', 'legal_terms_use_b'],
  ['legal_terms_medical_h', 'legal_terms_medical_b'],
  ['legal_terms_emergency_h', 'legal_terms_emergency_b'],
  ['legal_terms_responsib_h', 'legal_terms_responsib_b'],
  ['legal_terms_warranty_h', 'legal_terms_warranty_b'],
  ['legal_terms_law_h', 'legal_terms_law_b'],
] as const;

export function loadLegalStrings(): LegalStrings {
  const raw = readFileSync(
    fileURLToPath(new URL('../../../../legal/legal.json', import.meta.url)),
    'utf8',
  );
  return (JSON.parse(raw) as { strings: LegalStrings }).strings;
}

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

/** Which language to serve. The site is Russian-first; ?lang= overrides. */
export function pickLocale(query: unknown, acceptLanguage?: string): LegalLocale {
  const asked = (query as { lang?: string } | undefined)?.lang;
  if (asked && (LEGAL_LOCALES as readonly string[]).includes(asked)) {
    return asked as LegalLocale;
  }
  const header = (acceptLanguage ?? '').toLowerCase();
  // Kazakh before English: a browser set to kk is far more likely here than
  // one set to en, and matching in declaration order would never reach kk.
  if (header.startsWith('kk')) return 'kk';
  if (header.startsWith('en')) return 'en';
  return 'ru';
}

export function legalPageHtml(
  strings: LegalStrings,
  doc: 'privacy' | 'terms',
  locale: LegalLocale,
): string {
  const t = (key: string) => esc(strings[key]?.[locale] ?? strings[key]?.ru ?? '');
  const sections = doc === 'privacy' ? PRIVACY_SECTIONS : TERMS_SECTIONS;
  const title = t(doc === 'privacy' ? 'legal_privacy_title' : 'legal_terms_title');
  const other = doc === 'privacy' ? '/terms' : '/privacy';
  const otherTitle = t(doc === 'privacy' ? 'legal_terms_title' : 'legal_privacy_title');

  return `<!doctype html>
<html lang="${locale}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Ana-Bala</title>
<meta name="description" content="${title} — Ana-Bala">
<style>
  :root{--ink:#241A22;--cream:#FBF6F3;--dim:#6B5F66;--rule:#E6DCD8;--coral:#B8003F}
  *{box-sizing:border-box}
  body{margin:0;background:var(--cream);color:var(--ink);
    font:16px/1.65 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
    padding:32px 20px 64px;display:flex;justify-content:center}
  main{max-width:680px;width:100%}
  a{color:var(--coral)}
  h1{font-size:28px;line-height:1.2;margin:0 0 6px}
  h2{font-size:19px;margin:32px 0 8px}
  p{margin:0 0 14px;color:var(--dim)}
  .meta{font-size:13px;color:var(--dim);margin-bottom:24px}
  .draft{background:#FFF3D6;border-radius:14px;padding:14px 16px;font-size:14px;
    color:#6B4E00;margin:0 0 28px}
  .langs{margin:28px 0 0;font-size:14px}
  .langs a{margin-right:14px}
  footer{margin-top:40px;padding-top:20px;border-top:1px solid var(--rule);font-size:14px}
</style>
</head>
<body>
<main>
  <h1>${title}</h1>
  <p class="meta">Ana-Bala · ana-bala.kz</p>
  <div class="draft">${t('legal_draft_note')}</div>
  ${sections.map(([h, b]) => `<h2>${t(h)}</h2>\n  <p>${t(b)}</p>`).join('\n  ')}
  <p class="langs">
    <a href="?lang=ru">Русский</a><a href="?lang=kk">Қазақша</a><a href="?lang=en">English</a>
  </p>
  <footer>
    <a href="${other}?lang=${locale}">${otherTitle}</a> ·
    <a href="/">ana-bala.kz</a>
  </footer>
</main>
</body>
</html>`;
}

export function registerLegalPages(app: FastifyInstance): boolean {
  let strings: LegalStrings;
  try {
    strings = loadLegalStrings();
  } catch {
    // Fails soft like the other static pages, and the caller logs it. A
    // missing file must not take the API down — but it MUST be noticed, which
    // is what the return value is for.
    return false;
  }

  for (const doc of ['privacy', 'terms'] as const) {
    app.get(`/${doc}`, async (req, reply) => {
      const locale = pickLocale(req.query, req.headers['accept-language']);
      return reply
        .type('text/html')
        // Cacheable, briefly. These are public documents that change rarely,
        // but a policy update has to be able to reach people the same day.
        .header('cache-control', 'public, max-age=3600')
        .send(legalPageHtml(strings, doc, locale));
    });
  }
  return true;
}
