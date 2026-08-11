/**
 * The consumer half of frames 08 / 08a: what an operator edits in the panel,
 * reaching the app's screen 41 «Магазин».
 *
 * Over HTTP, panel first and storefront second, because that is the whole
 * claim. Migration 033 gave a product a stage, an age band and a Kazakh name,
 * `GET /shop/products` returned id/name/price/kind/variants, and the app
 * hard-coded three products with compile-time prices — so an operator could
 * change the price of the 39 000 ₸ комплект and no customer would ever see a
 * different number. A unit test against a fake repository would not have caught
 * that: both halves worked, the join did not exist.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

let app: FastifyInstance;
let repo: Repository;
let cookie = '';

function makeApp() {
  repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
}

interface WireProduct {
  id: string; name: string; priceMinor: number; kind: string;
  nameKk: string | null; descriptionRu: string | null; descriptionKk: string | null;
  stage: string | null; category: string | null;
  ageMinMonths: number | null; ageMaxMonths: number | null;
  photoUrl: string | null; inStock: boolean;
  variants: Array<{ id: string; stock: number }>;
  parts: Array<{ partId: string; qty: number }>;
}

/** The storefront, as an app on a phone sees it: no cookie, no token. */
async function storefront(): Promise<WireProduct[]> {
  const r = await app.inject({ method: 'GET', url: '/shop/products' });
  expect(r.statusCode).toBe(200);
  return r.json().products as WireProduct[];
}
const find = (ps: WireProduct[], id: string) => ps.find((p) => p.id === id)!;

const patch = (id: string, body: Record<string, unknown>) =>
  app.inject({ method: 'PATCH', url: `/admin/shop/products/${id}`, headers: { cookie }, payload: body });
const setStock = (variantId: string, stock: number) =>
  app.inject({ method: 'PATCH', url: `/admin/shop/variants/${variantId}`, headers: { cookie }, payload: { stock } });

beforeEach(async () => {
  app = makeApp();
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(r.statusCode).toBe(200);
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});

describe('an operator edits, a customer sees', () => {
  it('changes the комплект price in the panel and the storefront answers with it', async () => {
    // The headline claim of this feature, and the one that used to be false.
    expect(find(await storefront(), 'combo').priceMinor).toBe(3900000);

    expect((await patch('combo', { priceMinor: 4450000 })).statusCode).toBe(200);

    expect(find(await storefront(), 'combo').priceMinor).toBe(4450000);
    await app.close();
  });

  it('carries the Kazakh name so the app can render kk without a second read', async () => {
    await patch('tracker', { nameKk: 'Балалар трекері' });
    expect(find(await storefront(), 'tracker').nameKk).toBe('Балалар трекері');
    await app.close();
  });

  it('carries the stage and the age band — «блок персонализации»', async () => {
    await patch('tracker', { stage: 'toddler', ageMinMonths: 18, ageMaxMonths: 84 });
    const t = find(await storefront(), 'tracker');
    expect(t.stage).toBe('toddler');
    expect(t.ageMinMonths).toBe(18);
    expect(t.ageMaxMonths).toBe(84);
    await app.close();
  });

  it('carries both descriptions', async () => {
    await patch('watch', { descriptionRu: 'Давление и пульс', descriptionKk: 'Қысым және пульс' });
    const w = find(await storefront(), 'watch');
    expect(w.descriptionRu).toBe('Давление и пульс');
    expect(w.descriptionKk).toBe('Қысым және пульс');
    await app.close();
  });

  it('reports an unset stage as null rather than as a guess', async () => {
    // Null must survive to the app, because the app falls back to its own
    // heuristic on null. A default of 'any' here would replace a working guess
    // with a wrong fact, and the customer would never know which she was shown.
    const t = find(await storefront(), 'tracker');
    expect(t.stage).toBeNull();
    expect(t.category).toBeNull();
    await app.close();
  });

  it('reports no photo as null, not as a broken URL', async () => {
    // Nothing hosts product images yet. A '' or a placeholder path would give
    // the app something to try to load and fail at.
    for (const p of await storefront()) expect(p.photoUrl).toBeNull();
    await app.close();
  });

  it('withdrawing a product removes it from the storefront', async () => {
    await patch('watch', { active: false });
    expect((await storefront()).map((p) => p.id)).not.toContain('watch');
    await app.close();
  });
});

describe('what the storefront must never leak', () => {
  it('has no cost and no margin on an unauthenticated response', async () => {
    // This route has no session at all. `costMinor` is what a unit costs US.
    await patch('watch', { costMinor: 1200000 });
    const body = (await app.inject({ method: 'GET', url: '/shop/products' })).body;
    expect(body).not.toContain('costMinor');
    expect(body).not.toContain('margin');
    for (const p of await storefront()) {
      expect(Object.keys(p)).not.toContain('costMinor');
    }
    await app.close();
  });

  it('needs no cookie at all', async () => {
    // Customers are not signed in. A 401 here empties the shop screen.
    const r = await app.inject({ method: 'GET', url: '/shop/products' });
    expect(r.statusCode).toBe(200);
    await app.close();
  });
});

describe('«нет в наличии»', () => {
  it('is what a product with every colour at zero says', async () => {
    // Seeded stock is 0 everywhere.
    const w = find(await storefront(), 'watch');
    expect(w.variants.length).toBeGreaterThan(0);
    expect(w.inStock).toBe(false);
    await app.close();
  });

  it('flips as soon as one colour is stocked', async () => {
    const w = find(await storefront(), 'watch');
    await setStock(w.variants[0].id, 2);
    expect(find(await storefront(), 'watch').inStock).toBe(true);
    await app.close();
  });

  it('derives the bundle from its PARTS, not from its own empty colour list', async () => {
    // The комплект is the only product that carries the Ма!Ма! course and it
    // holds no stock of its own. Reading `some variant has stock` off it marks
    // the 39 000 ₸ set as permanently unavailable — which is the trap this
    // whole derivation exists to avoid.
    const ps = await storefront();
    const combo = find(ps, 'combo');
    expect(combo.kind).toBe('bundle');
    expect(combo.variants).toEqual([]);
    expect(combo.inStock).toBe(false); // parts are at 0

    await setStock(find(ps, 'watch').variants[0].id, 1);
    // One part stocked is not a set.
    expect(find(await storefront(), 'combo').inStock).toBe(false);

    await setStock(find(ps, 'tracker').variants[0].id, 1);
    expect(find(await storefront(), 'combo').inStock).toBe(true);
    await app.close();
  });

  it('goes out of stock again when a part is withdrawn from sale', async () => {
    // An inactive part is not on the storefront, so the set cannot be
    // assembled from what a customer can buy.
    const ps = await storefront();
    await setStock(find(ps, 'watch').variants[0].id, 5);
    await setStock(find(ps, 'tracker').variants[0].id, 5);
    expect(find(await storefront(), 'combo').inStock).toBe(true);

    await patch('tracker', { active: false });
    expect(find(await storefront(), 'combo').inStock).toBe(false);
    await app.close();
  });
});
