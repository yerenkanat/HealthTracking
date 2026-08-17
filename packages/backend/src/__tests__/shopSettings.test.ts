/**
 * The settings round trip: admin panel → shop_settings → the public landing.
 *
 * Nothing covered this route, and it is the one the storefront's WhatsApp
 * number, Kaspi link and testimonials all travel down. It is also the route
 * that holds the Anthropic and Google Maps API keys, right next to the values
 * that are deliberately public — one careless addition to the /shop/config
 * whitelist publishes a secret to every visitor.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

type StaffRole = 'admin' | 'clinician' | 'support';

/** The repository behind the app under test, so a test can look at what was
 *  really stored rather than at what the API chose to show. Since GET
 *  /admin/settings redacts every secret, "it came back" is no longer proof that
 *  "it was kept". */
let repo: ReturnType<typeof createMemoryRepository>;

function makeApp(role: StaffRole | null) {
  repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => (role ? { staffId: 's1', role } : null),
    },
    { logger: false },
  );
}

let app: FastifyInstance;
const save = (payload: Record<string, string>) =>
  app.inject({ method: 'PUT', url: '/admin/settings', payload });
const config = async () => (await app.inject({ method: 'GET', url: '/shop/config' })).json();

/** deploy/seed-reviews.json's shape, trimmed to one entry. */
const REVIEWS = JSON.stringify([
  {
    name: 'Айгерим, 34',
    city: 'Алматы',
    city_kz: 'Алматы, екі бала',
    text: 'Русский текст.',
    text_kz: 'Қазақша мәтін.',
    stars: 5,
  },
]);

describe('shop settings reach the landing', () => {
  beforeEach(() => {
    app = makeApp('admin');
  });

  it('serves what an admin saved', async () => {
    expect((await save({ whatsapp: '+7 (707) 345-22-44', reviews: REVIEWS, rating: '4.9' })).statusCode).toBe(200);

    const cfg = await config();
    // Normalised to digits on the way in, because wa.me links cannot carry the
    // brackets and spaces a human types.
    expect(cfg.whatsapp).toBe('77073452244');
    // A saved `rating` is accepted by the write (the column still exists and
    // nothing is silently destroyed) and is NOT published. It used to come back
    // here as '4.9' and go onto a live commercial page — a figure no query in
    // this repository can derive, because there is no ratings table, no reviews
    // table and no order feedback. See landingHonesty.test.ts.
    expect(cfg.rating, 'a rating reached the public config again').toBeUndefined();
    // Handed over verbatim as a string; the landing parses it.
    expect(JSON.parse(cfg.reviews)[0].text_kz).toBe('Қазақша мәтін.');
  });

  it('never publishes the API keys stored next door to them', async () => {
    await save({ anthropicApiKey: 'sk-ant-SECRET-VALUE', googleMapsApiKey: 'AIza-SECRET-VALUE' });
    const res = await app.inject({ method: 'GET', url: '/shop/config' });
    // Assert on the raw body, not field by field: a key leaked under an
    // unexpected name would still pass a field-by-field check.
    expect(res.body).not.toContain('SECRET-VALUE');
    // `rating` and `reviewCount` are deliberately absent — the two fields that
    // let somebody type invented social proof onto a live page.
    expect(Object.keys(res.json()).sort()).toEqual(['kaspiUrl', 'reviews', 'whatsapp']);
  });

  it('refuses a Google Maps key rather than pretending to store one usefully', async () => {
    // The app's map key is baked into the Android manifest at BUILD time, so
    // nothing on this side can ever act on one saved here. The panel used to
    // offer the field next to the Anthropic key, which does work — so an owner
    // could paste a real key, save, restart, and watch the map stay blank with
    // nothing saying why.
    //
    // zod strips unknown keys rather than rejecting, so the assertion is that
    // it never reaches storage.
    await save({ googleMapsApiKey: 'AIza-REAL-KEY' } as unknown as Record<string, string>);
    // Asserted against storage, not against the response: the response redacts
    // every secret key now, so an absent field there would prove nothing.
    expect((await repo.getShopSettings()).googleMapsApiKey).toBeUndefined();
  });

  it('leaves untouched keys alone when saving one field', async () => {
    // The panel sends only the boxes it rendered. An implementation that
    // replaced the whole row would wipe the API keys every time someone edited
    // the WhatsApp number, and nothing would say so until the AI features
    // stopped working.
    await save({ anthropicApiKey: 'sk-ant-SECRET-VALUE', reviews: REVIEWS });
    await save({ whatsapp: '77015550101' });

    expect((await repo.getShopSettings()).anthropicApiKey).toBe('sk-ant-SECRET-VALUE');
    const all = (await app.inject({ method: 'GET', url: '/admin/settings' })).json();
    expect(all.settings.reviews).toBe(REVIEWS);
  });

  it('stops publishing a rating even if one is somehow still in the table', async () => {
    // PUT no longer accepts `rating`, but a row saved before the field was
    // withdrawn is still there — nothing was destroyed. It must stay off the
    // public surface regardless.
    await repo.setShopSettings({ rating: '4.9', reviewCount: '1240' });
    const cfg = await config();
    expect(cfg.rating).toBeUndefined();
    expect(cfg.reviewCount).toBeUndefined();
    // …and the admin API still shows them, so the panel can say what became of
    // them instead of leaving an owner hunting for a box he used to fill in.
    const all = (await app.inject({ method: 'GET', url: '/admin/settings' })).json();
    expect(all.settings.rating).toBe('4.9');
    expect(all.settings.reviewCount).toBe('1240');
  });

  it('refuses to store a rating sent by an old client, and does not error', async () => {
    // The same withdrawal `googleMapsApiKey` got: zod strips the unknown key, so
    // a stale tab still posting one is ignored rather than refused — and the
    // number never reaches a place somebody could mistake for a fact.
    expect((await save({ rating: '4.9', reviewCount: '1240' })).statusCode).toBe(200);
    const stored = await repo.getShopSettings();
    expect(stored.rating, 'an invented rating was stored again').toBeUndefined();
    expect(stored.reviewCount).toBeUndefined();
  });

  it('refuses a member of staff who is not an admin', async () => {
    app = makeApp('support');
    await app.inject({ method: 'PUT', url: '/admin/settings', payload: { whatsapp: '77000000000' } });
    expect((await config()).whatsapp).not.toBe('77000000000');
  });

  it('accepts three bilingual reviews without hitting the length cap', async () => {
    // This read deploy/seed-reviews.json, which held three FABRICATED
    // testimonials and was deleted with them. The size check it was really
    // making still matters: the field caps at 6000 characters and three
    // bilingual reviews are not far off it, so a fourth would be refused in
    // production while the panel reported a successful save.
    const three = [1, 2, 3].map((n) => ({
      name: `Клиент ${n}`,
      city: 'Алматы',
      city_kz: 'Алматы',
      text: 'x'.repeat(300),
      text_kz: 'y'.repeat(300),
      stars: 5,
    }));
    const payload = JSON.stringify(three);
    expect(payload.length).toBeLessThan(6000);

    expect((await save({ reviews: payload })).statusCode).toBe(200);
    const parsed = JSON.parse((await config()).reviews);
    expect(parsed).toHaveLength(3);
    // Every one carries Kazakh text, or a Kazakh visitor reads Russian.
    expect(parsed.every((r: { text_kz?: string }) => r.text_kz)).toBe(true);
  });
});
