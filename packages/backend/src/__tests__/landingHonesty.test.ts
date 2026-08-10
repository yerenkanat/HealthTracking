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

  it('the review seed is gone and stays gone', () => {
    // deploy/seed-reviews.json existed to write the three invented quotes into
    // shop_settings, which would have put them back on the page through a route
    // this test does not read.
    expect(existsSync(`${root}../../deploy/seed-reviews.json`),
      'deploy/seed-reviews.json is back — it seeds fabricated testimonials').toBe(false);
  });
});
