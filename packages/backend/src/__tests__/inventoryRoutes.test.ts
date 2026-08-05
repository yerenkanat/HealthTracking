/**
 * The back office's edge onto the stock ledger.
 *
 * A stock movement is a financial record: it changes what the business believes
 * it owns, and unlike a lead status it cannot be undone by setting it back. So
 * these are admin-only, and a refusal has to be told apart from a mistake.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

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
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const send = (method: 'POST' | 'PUT', url: string, payload: unknown) =>
  app.inject({ method, url, payload: payload as never, headers: { cookie } });

const firstVariant = async () => {
  const products = (await get('/admin/inventory')).json().products;
  return products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
};

describe('the warehouse view', () => {
  it('lists every product with its price, stock and composition', async () => {
    const res = await get('/admin/inventory');
    expect(res.statusCode).toBe(200);
    const { products } = res.json();

    const watch = products.find((p: { id: string }) => p.id === 'watch');
    expect(watch.priceMinor).toBeGreaterThan(0);
    expect(watch.variants.length).toBeGreaterThan(0);

    // The combo has to appear here even though it is not on the storefront —
    // this is the screen where its price and availability are managed.
    const combo = products.find((p: { id: string }) => p.id === 'combo');
    expect(combo, 'the bundle is invisible in the back office').toBeTruthy();
    expect(combo.kind).toBe('bundle');
    expect(combo.parts.map((x: { partId: string }) => x.partId).sort()).toEqual(['tracker', 'watch']);
  });

  it('flags what is running out', async () => {
    const { lowStock } = (await get('/admin/inventory')).json();
    expect(lowStock, 'nothing in stock and nothing flagged').toContain('watch');
  });
});

describe('moving stock', () => {
  it('records a receipt against the person who entered it', async () => {
    const v = await firstVariant();
    const res = await send('POST', '/admin/inventory/moves', {
      variantId: v, delta: 40, reason: 'receipt', note: 'накладная 118',
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().stock).toBe(40);

    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves[0].reason).toBe('receipt');
    expect(moves[0].staffId, 'a movement nobody is accountable for').toBeTruthy();
  });

  it('refuses to write off more than exists, and says which kind of refusal', async () => {
    // 409, not 400: the request was well formed and the world refused it. "You
    // cannot write off five of a thing you have two of" is not a malformed body.
    const v = await firstVariant();
    await send('POST', '/admin/inventory/moves', { variantId: v, delta: 2, reason: 'receipt' });

    const res = await send('POST', '/admin/inventory/moves', { variantId: v, delta: -5, reason: 'writeoff' });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('insufficient_stock');

    const { moves } = (await get(`/admin/inventory/moves?variantId=${v}`)).json();
    expect(moves, 'a refused move was recorded as if it happened').toHaveLength(1);
  });

  it('refuses a zero movement — that is not an event', async () => {
    const v = await firstVariant();
    expect((await send('POST', '/admin/inventory/moves', { variantId: v, delta: 0, reason: 'correction' })).statusCode).toBe(400);
  });
});

describe('products', () => {
  it('can be created and priced', async () => {
    const res = await send('PUT', '/admin/inventory/products', {
      id: 'strap', name: 'Ремешок', priceMinor: 350000, costMinor: 120000, lowStockThreshold: 5,
    });
    expect(res.statusCode).toBe(200);

    const { products } = (await get('/admin/inventory')).json();
    const strap = products.find((p: { id: string }) => p.id === 'strap');
    expect(strap.priceMinor).toBe(350000);
    expect(strap.costMinor).toBe(120000);
  });

  it('refuses an id that would not survive a URL', async () => {
    const res = await send('PUT', '/admin/inventory/products', {
      id: 'Ремешок 2!', name: 'x', priceMinor: 1,
    });
    expect(res.statusCode).toBe(400);
  });

  it('refuses a bundle that contains itself', async () => {
    // Its available stock would be defined in terms of itself.
    const res = await send('PUT', '/admin/inventory/products/combo/parts', {
      parts: [{ partId: 'combo', qty: 1 }],
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bundle_contains_itself');
  });
});

describe('who may touch stock', () => {
  it('nobody, without a session', async () => {
    expect((await app.inject({ method: 'GET', url: '/admin/inventory' })).statusCode).toBe(401);
    expect((await app.inject({
      method: 'POST', url: '/admin/inventory/moves',
      payload: { variantId: 'x', delta: 1, reason: 'receipt' },
    })).statusCode).toBe(401);
  });

  it('and not a support account', async () => {
    await send('POST', '/admin/staff', {
      phone: '77011112233', displayName: 'Айгерім', role: 'support', password: 'nurse-password',
    });
    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: '77011112233', password: 'nurse-password' },
    });
    const theirs = String(login.headers['set-cookie'] ?? '').split(';')[0];

    const res = await app.inject({
      method: 'POST', url: '/admin/inventory/moves',
      payload: { variantId: await firstVariant(), delta: -1, reason: 'writeoff' },
      headers: { cookie: theirs },
    });
    expect(res.statusCode, 'support can write off stock').toBe(403);
  });
});
