/**
 * A photo an operator UPLOADS, driven over HTTP.
 *
 * The product card offered «Ссылка на фото» — paste a URL. That asks a person
 * selling watches to first host an image somewhere and then know its address,
 * and it puts the storefront's pictures on a server nobody here controls,
 * where they rot, hotlink-block, or quietly become something else. Nothing in
 * this product had ever uploaded an image; the only pictures it has shown are
 * seven watch JPEGs committed to the repository by hand.
 *
 * Driven end to end rather than per-unit, because the value is in the JOIN: a
 * route that stores bytes nothing serves, or a storefront payload that names a
 * URL that 404s, is the defect this repository produces most.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let app: FastifyInstance;
let repo: Repository;
let cookie = '';
/** Varied per test so the capability guard is exercised, not stubbed away. */
let ROLE: 'admin' | 'warehouse' = 'admin';

/** The smallest thing that is genuinely a PNG, so nothing has to be invented. */
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

beforeEach(async () => {
  ROLE = 'admin';
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
      authAdmin: async () => ({ staffId: 's1', role: ROLE }),
    },
    { logger: false },
  );
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});

/** Whatever the seeded catalogue calls its first product. */
async function anyProductId(): Promise<string> {
  const { products } = (await app.inject({ method: 'GET', url: '/shop/products' })).json();
  expect(products.length, 'the seeded catalogue is empty — nothing to photograph').toBeGreaterThan(0);
  return products[0].id;
}

const upload = (id: string, bytes: Buffer, mime = 'image/png', color?: string) =>
  app.inject({
    method: 'POST',
    url: `/admin/shop/products/${id}/photo${color ? `?color=${encodeURIComponent(color)}` : ''}`,
    headers: { cookie, 'content-type': mime },
    payload: bytes,
  });

describe('uploading a product photo', () => {
  it('stores it and serves it back publicly', async () => {
    const id = await anyProductId();
    expect((await upload(id, PNG)).statusCode).toBe(201);

    // Public: the storefront and the app are public, so the photo must be.
    const got = await app.inject({ method: 'GET', url: `/shop/products/${id}/photo` });
    expect(got.statusCode).toBe(200);
    expect(got.headers['content-type']).toContain('image/png');
    expect(Buffer.from(got.rawPayload).equals(PNG), 'the bytes came back changed').toBe(true);
  });

  it('tells the catalogue which products have one', async () => {
    const id = await anyProductId();
    const before = (await app.inject({ method: 'GET', url: '/shop/products' })).json();
    // Falsy, not absent: the legacy `photo_url` column still rides along as
    // null. What matters is that a client asking «is there a photo» gets no
    // for a product without one, whichever field it reads.
    expect(before.products.find((p: { id: string }) => p.id === id).photoUrl).toBeFalsy();

    await upload(id, PNG);

    const after = (await app.inject({ method: 'GET', url: '/shop/products' })).json();
    const p = after.products.find((x: { id: string }) => x.id === id);
    // Absent before, present after — so a client testing `if (photoUrl)` and one
    // testing `'photoUrl' in p` agree with each other.
    expect(p.photoUrl).toBe(`/shop/products/${id}/photo`);
    // And the URL it names actually answers, which is the half that usually rots.
    expect((await app.inject({ method: 'GET', url: p.photoUrl })).statusCode).toBe(200);
  });

  it('keeps a colour photo separate from the product photo', async () => {
    const id = await anyProductId();
    const OTHER = Buffer.concat([PNG, Buffer.from([0])]);
    await upload(id, PNG);
    await upload(id, OTHER, 'image/png', 'Розовое золото');

    const plain = await app.inject({ method: 'GET', url: `/shop/products/${id}/photo` });
    const gold = await app.inject({ method: 'GET', url: `/shop/products/${id}/photo?color=${encodeURIComponent('Розовое золото')}` });
    expect(Buffer.from(plain.rawPayload).equals(PNG)).toBe(true);
    expect(Buffer.from(gold.rawPayload).equals(OTHER)).toBe(true);

    const { products } = (await app.inject({ method: 'GET', url: '/shop/products' })).json();
    expect(products.find((p: { id: string }) => p.id === id).photoColors).toEqual(['Розовое золото']);
  });

  it('replaces rather than accumulates', async () => {
    const id = await anyProductId();
    const SECOND = Buffer.concat([PNG, Buffer.from([1, 2, 3])]);
    await upload(id, PNG);
    await upload(id, SECOND);
    const got = await app.inject({ method: 'GET', url: `/shop/products/${id}/photo` });
    expect(Buffer.from(got.rawPayload).equals(SECOND), 'the old photo survived a replacement').toBe(true);
  });

  it('can be removed, and then says there is none', async () => {
    const id = await anyProductId();
    await upload(id, PNG);
    expect((await app.inject({ method: 'DELETE', url: `/admin/shop/products/${id}/photo`, headers: { cookie } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: `/shop/products/${id}/photo` })).statusCode).toBe(404);
  });
});

describe('what it refuses', () => {
  it('refuses a format half the surfaces cannot render, and names what to use', async () => {
    const id = await anyProductId();
    const r = await upload(id, PNG, 'image/heic');
    expect(r.statusCode).toBe(415);
    // An operator who just picked a HEIC off an iPhone needs to be told which
    // formats work, not that something was "wrong".
    expect(r.json().allowed).toContain('image/jpeg');
  });

  it('refuses a photo too large to load on a mobile connection', async () => {
    const id = await anyProductId();
    const huge = Buffer.alloc(3 * 1024 * 1024 + 1, 7);
    const r = await upload(id, huge);
    expect(r.statusCode).toBe(413);
    expect(r.json().maxBytes).toBe(3 * 1024 * 1024);
  });

  it('refuses an empty body rather than storing zero bytes', async () => {
    const id = await anyProductId();
    expect((await upload(id, Buffer.alloc(0))).statusCode).toBe(400);
  });

  it('refuses a product that does not exist', async () => {
    // A typo in the id would otherwise create a photo nothing shows and nobody
    // can find.
    expect((await upload('no-such-product', PNG)).statusCode).toBe(404);
  });

  it('refuses a role without the content capability', async () => {
    // The shelf's appearance is `content` — the same capability that gates the
    // product copy it sits beside. A warehouse hand counts boxes; she does not
    // choose what the storefront looks like.
    const id = await anyProductId();
    ROLE = 'warehouse';
    expect((await upload(id, PNG)).statusCode).toBe(403);
  });

  it('records who changed the shelf', async () => {
    const id = await anyProductId();
    await upload(id, PNG);
    const { audit } = (await app.inject({ method: 'GET', url: '/admin/audit', headers: { cookie } })).json();
    expect(audit.some((e: { action: string }) => e.action === 'product_photo_upload'),
      'nobody recorded who changed the shelf').toBe(true);
  });
});
