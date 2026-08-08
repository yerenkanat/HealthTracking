/**
 * `/privacy` and `/terms`.
 *
 * A store listing will not accept an app handling a child's geolocation and a
 * woman's reproductive history without a publicly reachable policy, and Kazakh
 * personal-data law wants one too. These lived only inside the app, where
 * nobody can read them before installing and no reviewer can link to them.
 *
 * The risk this file guards is not a broken page — it is TWO policies. Whichever
 * one a customer read, the other is the one we would be held to.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import {
  LEGAL_LOCALES, PRIVACY_SECTIONS, TERMS_SECTIONS,
  legalPageHtml, loadLegalStrings, pickLocale, registerLegalPages,
} from '../http/legalPages';

let app: FastifyInstance;

beforeAll(async () => {
  app = Fastify({ logger: false });
  expect(registerLegalPages(app), 'legal/legal.json did not load').toBe(true);
  await app.ready();
});
afterAll(async () => { await app.close(); });

describe('the source file', () => {
  it('has every section of both documents, in all three languages', () => {
    // The page falls back to Russian for a missing string, so a gap would show
    // up as a page that silently switches language mid-document rather than as
    // an error. This is what catches it.
    const s = loadLegalStrings();
    const needed = [
      ...PRIVACY_SECTIONS.flat(),
      ...TERMS_SECTIONS.flat(),
      'legal_privacy_title', 'legal_terms_title', 'legal_draft_note',
    ];
    const gaps: string[] = [];
    for (const key of needed) {
      for (const loc of LEGAL_LOCALES) {
        if (!s[key]?.[loc]?.trim()) gaps.push(`${key}.${loc}`);
      }
    }
    expect(gaps, `untranslated: ${gaps.join(', ')}`).toEqual([]);
  });

  it('still says it is a draft', () => {
    // The wording is honest about what the app does and has NOT been through a
    // lawyer. A page that quietly stops saying so is making a claim this
    // repository cannot support.
    const s = loadLegalStrings();
    expect(s.legal_draft_note.ru.toLowerCase()).toContain('черновик');
  });
});

describe('the pages', () => {
  it('are served, in Russian by default', async () => {
    for (const path of ['/privacy', '/terms']) {
      const r = await app.inject({ method: 'GET', url: path });
      expect(r.statusCode, path).toBe(200);
      expect(r.headers['content-type']).toContain('text/html');
      expect(r.body).toContain('lang="ru"');
    }
  });

  it('carry every section of their own document and none of the other\'s', async () => {
    const s = loadLegalStrings();
    const privacy = (await app.inject({ method: 'GET', url: '/privacy' })).body;
    for (const [h] of PRIVACY_SECTIONS) expect(privacy).toContain(s[h].ru);
    // The terms' first heading must not appear on the privacy page — one
    // document rendering both is how a reviewer is told the wrong thing.
    expect(privacy).not.toContain(s[TERMS_SECTIONS[0][0]].ru);
  });

  it('are readable in Kazakh and English', async () => {
    const s = loadLegalStrings();
    for (const loc of ['kk', 'en'] as const) {
      const body = (await app.inject({ method: 'GET', url: `/privacy?lang=${loc}` })).body;
      expect(body).toContain(`lang="${loc}"`);
      expect(body).toContain(s.legal_priv_collect_h[loc]);
    }
  });

  it('keep the draft banner', async () => {
    const s = loadLegalStrings();
    expect((await app.inject({ method: 'GET', url: '/privacy' })).body)
      .toContain(s.legal_draft_note.ru);
  });

  it('link to each other, so a reviewer finds both from either', async () => {
    expect((await app.inject({ method: 'GET', url: '/privacy' })).body)
      .toContain('/terms');
    expect((await app.inject({ method: 'GET', url: '/terms' })).body)
      .toContain('/privacy');
  });

  it('escape what they print', () => {
    const html = legalPageHtml(
      { legal_privacy_title: { ru: '<script>x</script>', kk: 'a', en: 'a' } } as never,
      'privacy', 'ru',
    );
    expect(html).not.toContain('<script>x</script>');
    expect(html).toContain('&lt;script&gt;');
  });
});

describe('choosing a language', () => {
  it('honours ?lang= above anything else', () => {
    expect(pickLocale({ lang: 'kk' }, 'en-GB')).toBe('kk');
  });

  it('falls back to the browser, Kazakh before English', () => {
    // Matching in declaration order would never reach kk, and a browser set to
    // Kazakh is far more likely here than one set to English.
    expect(pickLocale({}, 'kk-KZ,kk;q=0.9')).toBe('kk');
    expect(pickLocale({}, 'en-US')).toBe('en');
  });

  it('is Russian when nothing says otherwise', () => {
    expect(pickLocale({}, undefined)).toBe('ru');
    expect(pickLocale({ lang: 'klingon' }, undefined)).toBe('ru');
  });
});
