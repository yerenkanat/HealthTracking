/**
 * Frame 07 · Остатки — the two things the warehouse screen could not answer.
 *
 *   1. WHICH PICTURE. Per-colour photo upload exists and the storefront shows
 *      the result; the warehouse drew a coloured dot. The shelf response now
 *      carries the photo it already holds, so the panel can draw the picture a
 *      customer sees instead of guessing — and can tell "no photo yet" from
 *      "broken image" without firing a request that 404s.
 *   2. WHAT MOVED TODAY. The ledger could only be read as "the last N rows",
 *      which is a period nobody can name and therefore a total nobody can add
 *      up. `since` bounds it to the operator's day.
 *
 * Driven over HTTP against the real memory repository, because the value is in
 * the join: an index computed in a route nothing reads, or a `since` the
 * repository quietly ignores, is this repository's commonest defect.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let app: FastifyInstance;
let repo: Repository;
let cookie = '';

/** The smallest thing that is genuinely a PNG, so nothing has to be invented. */
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

beforeEach(async () => {
  repo = createMemoryRepository();
  app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => ({ staffId: 's1', role: 'admin' }),
    },
    { logger: false },
  );
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});

interface ShelfVariant { id: string; color: string; stock: number; photoUrl?: string; photoUpdatedAt?: string }
/**
 * `photoUrl` on the PRODUCT is older than the upload feature: it is the
 * «Ссылка на фото» column, which holds a link somebody pasted or null. An
 * uploaded photo takes precedence over it — the same precedence the storefront
 * already applies — so the two screens cannot show different pictures of the
 * same product.
 */
interface ShelfProduct { id: string; name: string; kind: string; variants: ShelfVariant[]; photoUrl?: string | null }

const shelf = async (): Promise<ShelfProduct[]> =>
  (await app.inject({ method: 'GET', url: '/admin/inventory', headers: { cookie } })).json().products;

/** A product that actually has colours, so a per-colour photo has a target. */
async function firstWithColours(): Promise<ShelfProduct> {
  const p = (await shelf()).find((x) => x.kind !== 'bundle' && x.variants.length > 0);
  expect(p, 'the seeded catalogue has no colours — nothing to photograph').toBeTruthy();
  return p!;
}

describe('the shelf knows which photos exist', () => {
  it('says nothing at all about a photo nobody has uploaded', async () => {
    // Absent, not null: a colour with no picture is a normal state, and the
    // panel must be able to tell it apart WITHOUT asking for the image and
    // being told 404.
    const p = await firstWithColours();
    expect(p.photoUrl ?? null, 'a link nobody pasted').toBeNull();
    for (const v of p.variants) expect(v.photoUrl).toBeUndefined();
  });

  it('a colour photo comes back on that colour, and on no other', async () => {
    const p = await firstWithColours();
    const target = p.variants[0];
    const res = await app.inject({
      method: 'POST',
      url: `/admin/shop/products/${p.id}/photo?color=${encodeURIComponent(target.color)}`,
      headers: { cookie, 'content-type': 'image/png' },
      payload: PNG,
    });
    expect(res.statusCode, res.body).toBe(201);

    const after = (await shelf()).find((x) => x.id === p.id)!;
    const got = after.variants.find((v) => v.id === target.id)!;
    expect(got.photoUrl, 'the colour we photographed has no url').toBeTruthy();
    expect(got.photoUpdatedAt, 'no upload time to bust a day-long cache with').toBeTruthy();
    // The URL the storefront already serves — one photo endpoint, not a second
    // admin-only one to keep in step.
    const served = await app.inject({ method: 'GET', url: got.photoUrl! });
    expect(served.statusCode).toBe(200);
    expect(served.headers['content-type']).toContain('image/png');

    // The other colours are untouched: a picture of the pink one against the
    // blue one would send the wrong box to a customer.
    for (const v of after.variants.filter((v) => v.id !== target.id)) {
      expect(v.photoUrl, `${v.color} borrowed another colour's photo`).toBeUndefined();
    }
    // And the product-level photo is still absent — a colour photo is not it.
    expect(after.photoUrl ?? null).toBeNull();
  });

  it("the product's own photo lands on the product row, not on a colour", async () => {
    const p = await firstWithColours();
    expect((await app.inject({
      method: 'POST', url: `/admin/shop/products/${p.id}/photo`,
      headers: { cookie, 'content-type': 'image/png' }, payload: PNG,
    })).statusCode).toBe(201);

    const after = (await shelf()).find((x) => x.id === p.id)!;
    expect(after.photoUrl).toBe(`/shop/products/${encodeURIComponent(p.id)}/photo`);
    for (const v of after.variants) expect(v.photoUrl).toBeUndefined();
  });

  it('a deleted photo disappears from the shelf too', async () => {
    const p = await firstWithColours();
    const colour = p.variants[0].color;
    const q = `?color=${encodeURIComponent(colour)}`;
    await app.inject({
      method: 'POST', url: `/admin/shop/products/${p.id}/photo${q}`,
      headers: { cookie, 'content-type': 'image/png' }, payload: PNG,
    });
    await app.inject({
      method: 'DELETE', url: `/admin/shop/products/${p.id}/photo${q}`, headers: { cookie },
    });
    const after = (await shelf()).find((x) => x.id === p.id)!;
    expect(after.variants.find((v) => v.color === colour)!.photoUrl).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------

interface Move { delta: number; reason: string; at: string; note: string | null; staffId: string | null }

const movesSince = async (since?: string, limit = 500) => {
  const q = `limit=${limit}${since ? `&since=${encodeURIComponent(since)}` : ''}`;
  return app.inject({ method: 'GET', url: `/admin/inventory/moves?${q}`, headers: { cookie } });
};

/** Move stock the way the panel does — over HTTP, not into the fake. */
async function move(variantId: string, delta: number, reason: string, note = 'test') {
  const res = await app.inject({
    method: 'POST', url: '/admin/inventory/moves',
    headers: { cookie }, payload: { variantId, delta, reason, note },
  });
  expect(res.statusCode, res.body).toBe(200);
}

describe('движения за день', () => {
  it('gives back what moved after the instant asked for, and nothing before it', async () => {
    const p = await firstWithColours();
    const v = p.variants[0].id;
    await move(v, 40, 'receipt');
    // Everything above happened before this instant; everything below, after.
    // The pauses are the clock's resolution, not a race: two moves booked
    // inside the same millisecond genuinely cannot be put on opposite sides of
    // a boundary, and the bound is inclusive by design.
    await new Promise((r) => setTimeout(r, 5));
    const cut = new Date().toISOString();
    await new Promise((r) => setTimeout(r, 5));
    await move(v, -3, 'sale');

    const body = (await movesSince(cut)).json();
    expect(body.moves.map((m: Move) => m.delta), 'the earlier receipt leaked into "today"').toEqual([-3]);
    expect(body.since).toBe(cut);
    // Everything, for comparison: the filter narrowed rather than emptied.
    expect((await movesSince()).json().moves).toHaveLength(2);
  });

  it('keeps the author and the reason the card promises', async () => {
    const p = await firstWithColours();
    // Received first: the ledger refuses to take a variant below zero, which is
    // the shelf every seeded colour starts on.
    await move(p.variants[0].id, 2, 'receipt');
    await move(p.variants[0].id, -1, 'writeoff', 'разбили при приёмке');
    const [m] = (await movesSince(new Date(Date.now() - 60_000).toISOString())).json().moves as Move[];
    expect(m.reason).toBe('writeoff');
    expect(m.staffId, 'a write-off with nobody\'s name on it').toBe('s1');
    expect(m.note).toBe('разбили при приёмке');
  });

  it('says whether the window held the whole period', async () => {
    const p = await firstWithColours();
    const v = p.variants[0].id;
    await move(v, 10, 'receipt');
    await move(v, 10, 'receipt');
    const since = new Date(Date.now() - 60_000).toISOString();

    expect((await movesSince(since, 500)).json().exact, 'two rows in a 500 window is exact').toBe(true);
    // Truncated: the caller asked for a period and got a slice of it. Whoever
    // adds these up must be told the sum is short.
    const cut = (await movesSince(since, 1)).json();
    expect(cut.moves).toHaveLength(1);
    expect(cut.exact).toBe(false);
    expect(cut.limit).toBe(1);
  });

  it('refuses a since it cannot parse instead of answering about all time', async () => {
    // Ignoring it would answer "what happened today" with the whole ledger,
    // and the panel would print somebody's month as their shift.
    const res = await movesSince('позавчера');
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bad_since');
  });

  it('a boundary move belongs to the day that is starting', async () => {
    // Inclusive, and the same way in both repositories.
    const p = await firstWithColours();
    await move(p.variants[0].id, 5, 'receipt');
    const at = ((await movesSince()).json().moves as Move[])[0].at;
    expect((await movesSince(at)).json().moves).toHaveLength(1);
  });
});
