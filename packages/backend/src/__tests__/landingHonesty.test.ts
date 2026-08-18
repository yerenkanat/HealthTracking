/**
 * Nothing on the public pages may claim something we cannot show is true.
 *
 * Three named, five-star testimonials — «Айгерим, 34 · Алматы», «Мадина, 41 ·
 * Астана», «Динара, 29 · Шымкент» — were live on ana-bala.kz in both languages,
 * above the fold, in the section a mother screenshots for her sister. The
 * repository's own seed README said plainly that nobody had shown these people
 * exist and that the stars were picked by whoever wrote the page. Above them sat
 * «Уже с 12 400 семьями Казахстана», a number no query in this repository
 * derives and nothing ever did.
 *
 * They survived because they lived in an exported artifact nobody diffs and a
 * seed script that described the problem in its own documentation. This test is
 * what makes putting them back a failing build rather than a paste.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO. It cannot tell a real review from an
 * invented one — only a person can. It pins the KNOWN fabrications and the
 * shapes that make one likely, so the next fabricated line has to be a new
 * invention rather than a copy of the old one.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));

/**
 * The retired storefront pages, read from the source of truth rather than
 * listed here — staticPages.ts 302s every one of them to `/`, so nothing on
 * them can reach a member of the public.
 *
 * shop/umay-watch.html still carries a ★★★★★ block and is dead: this test
 * checks what is SERVED, and asserting against a file nobody can load would be
 * a failure nobody could act on except by editing a file that does not matter.
 * If a page is ever un-retired it re-enters this check automatically, because
 * the list is parsed from the code that does the redirecting.
 */
function retiredSlugs(): Set<string> {
  const src = readFileSync(`${root}src/http/staticPages.ts`, 'utf8');
  const m = src.match(/RETIRED_SHOP_PAGES\s*=\s*\[([^\]]*)\]/);
  const out = new Set<string>();
  for (const q of m?.[1].matchAll(/'([^']+)'/g) ?? []) {
    const slug = q[1].replace(/^\/shop\/?/, '');
    if (slug) out.add(`${slug}.html`);
  }
  return out;
}

/** Every page a member of the public can load. */
function publicPages(): Array<{ name: string; html: string }> {
  const out: Array<{ name: string; html: string }> = [];
  const retired = retiredSlugs();
  for (const dir of ['landing', 'shop']) {
    const path = `${root}${dir}`;
    if (!existsSync(path)) continue;
    for (const f of readdirSync(path).filter((n) => n.endsWith('.html'))) {
      if (dir === 'shop' && retired.has(f)) continue;
      out.push({ name: `${dir}/${f}`, html: readFileSync(`${path}/${f}`, 'utf8') });
    }
  }
  return out;
}

describe('the public pages', () => {
  it('there are pages to check', () => {
    // Guards the guard: an empty list would make everything below pass while
    // proving nothing, which is how this class of test quietly stops working.
    expect(publicPages().length).toBeGreaterThan(0);
  });

  it('carries none of the fabricated testimonials', () => {
    const invented = ['Айгерим, 34', 'Мадина, 41', 'Динара, 29'];
    for (const { name, html } of publicPages()) {
      for (const person of invented) {
        expect(html, `${name} still quotes «${person}», who nobody has shown exists`)
          .not.toContain(person);
      }
    }
  });

  it('claims no customer count that no query produces', () => {
    // «12 400» was written into the artifact and derived from nothing. If a real
    // figure is ever shown it must come from a query, and this test should then
    // be pointed at that endpoint instead of deleted.
    for (const { name, html } of publicPages()) {
      expect(html, `${name} still claims a hardcoded customer count`)
        .not.toMatch(/12[\s  ]?400/);
    }
  });

  it('does not ship a five-star rating block with a name beside it', () => {
    // The SHAPE of the fabrication, not just its text: five filled stars
    // immediately followed by a person's name and city is a testimonial, and a
    // testimonial in a static artifact cannot have consented to anything. Real
    // reviews belong in shop_settings.reviews, edited in the panel, where they
    // arrive with a person attached.
    for (const { name, html } of publicPages()) {
      expect(html, `${name} has a hardcoded ★★★★★ testimonial — real ones belong in shop_settings`)
        .not.toMatch(/★{5}/);
    }
  });

  it('/shop/config cannot publish a rating or a review count', async () => {
    // Two free-text boxes in the back office — «Рейтинг (напр. 4.9)» and
    // «Кол-во отзывов», placeholdered 4.9 and 1240 — wrote straight onto a live
    // commercial page through this route. Nothing in the schema can produce
    // either figure: there is no ratings table, no reviews table, no order
    // feedback. So any value there is invented by definition, and it is read as
    // fact by somebody deciding whether to trust a product that tracks their
    // child.
    //
    // Asserted on the ROUTE rather than on the panel's markup, because the
    // panel is one 500 KB file that several people edit and an input is two
    // keystrokes to restore. The publish path is the chokepoint.
    const mod = await import('../routes/crud');
    const src = readFileSync(
      fileURLToPath(new URL('../routes/crud.ts', import.meta.url)), 'utf8');
    expect(mod, 'crud routes failed to load').toBeTruthy();

    const handler = src.slice(src.indexOf("app.get('/shop/config'"));
    const body = handler.slice(0, handler.indexOf('});'));
    // Comments explain WHY these are absent, so strip them before asserting.
    const code = body.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');
    expect(code, 'GET /shop/config publishes `rating` again').not.toMatch(/\brating\b/);
    expect(code, 'GET /shop/config publishes `reviewCount` again').not.toMatch(/\breviewCount\b/);
  });

  it('the three invented mothers cannot come back through the panel', () => {
    // Айгерим/Мадина/Динара were removed from the exported landing artifact by
    // the tests above — and the copies in `shop_settings.reviews` were NOT,
    // because they live in the database, not in a file. On 2026-08-13 all three
    // were still being served publicly by GET /shop/config, months after the
    // page that displayed them was cleaned.
    //
    // A test cannot delete a production row. What it can do is refuse to let
    // these three specific strings back into any file in this repository —
    // seed, fixture, migration or default — so that clearing them is permanent
    // rather than something the next deploy quietly undoes.
    const NAMES = ['Айгерим, 34', 'Мадина, 41', 'Динара, 29'];
    // ../landing is the page itself and ../../docs holds the exported artifact
    // it was unpacked from. Both were missing, and the artifact is exactly what
    // this test's own header blames: «they lived in an exported artifact nobody
    // diffs». It was still carrying every fabricated name.
    const dirs = ['db', 'src', '../admin', '../landing', '../../deploy', '../../legal', '../../docs'];
    const offenders: string[] = [];
    const walk = (dir: string) => {
      let entries;
      try { entries = readdirSync(`${root}${dir}`, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        if (e.name === 'node_modules' || e.name === '__tests__') continue;
        // The one file that SHOULD name them: the note recording that these
        // three people were invented. Deleting the record of a mistake is how
        // the mistake gets made again.
        if (e.name === 'seed-reviews.README.md') continue;
        const p = `${dir}/${e.name}`;
        if (e.isDirectory()) { walk(p); continue; }
        if (!/\.(ts|mjs|js|json|sql|html|sh|md)$/.test(e.name)) continue;
        let text;
        try { text = readFileSync(`${root}${p}`, 'utf8'); } catch { continue; }
        for (const n of NAMES) if (text.includes(n)) offenders.push(`${p}: ${n}`);
      }
    };
    for (const d of dirs) walk(d);
    expect(offenders,
      'the invented testimonials are back in the repository — they were live on ' +
      '/shop/config until 2026-08-13 and must not be re-seeded').toEqual([]);
  });

  it('the review seed is gone and stays gone', () => {
    // deploy/seed-reviews.json existed to write the three invented quotes into
    // shop_settings, which would have put them back on the page through a route
    // this test does not read.
    expect(existsSync(`${root}../../deploy/seed-reviews.json`),
      'deploy/seed-reviews.json is back — it seeds fabricated testimonials').toBe(false);
  });

  it('both lead forms link the policy where the data is actually taken', () => {
    // The two forms take a name and a phone number under a one-line consent.
    // Until 2026-08-18 neither line linked anywhere. The footer carried
    // /privacy, but a consent whose document is reachable only by scrolling
    // past the button is not much of one — and the policy those lines pointed
    // at, had they pointed anywhere, said «данные хранятся на вашем телефоне»,
    // which was false across the whole schema.
    //
    // Both halves had to be true before this test could exist: a real document,
    // and a link to it at the point of collection.
    const html = readFileSync(`${root}landing/index.html`, 'utf8');

    expect(html, 'the Russian consent line no longer links to the policy')
      .toMatch(/соглашаетесь с <a href="\/privacy"[^>]*>обработкой персональных данных<\/a>/);
    expect(html, 'the Kazakh consent line no longer links to the policy')
      .toMatch(/<a href="\/privacy\?lang=kk"[^>]*>дербес деректерді өңдеуге<\/a> келісім бересіз/);

    // Neither language may lose its consent line altogether, which is the
    // failure this would otherwise be blind to: a form with no line at all
    // trivially satisfies "every line links".
    expect((html.match(/<form /g) ?? []).length,
      'a lead form was added or removed — check it carries a linked consent line too').toBe(2);
  });
});
