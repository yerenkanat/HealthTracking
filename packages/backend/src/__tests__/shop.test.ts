/**
 * The device shop end-to-end over HTTP: a customer reads products, an out-of-stock
 * order is refused (409), admin sets per-colour stock, then the order goes through
 * (201) and lands in the admin order list with its delivery address.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const STAFF = { staffId: 's1', role: 'admin' as const };
let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

function app(): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => STAFF,
    },
    { logger: false },
  );
}

describe('the device shop', () => {
  it('serves products with colour variants (public, no auth)', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/shop/products' });
    expect(r.statusCode).toBe(200);
    const products = r.json().products as Array<{ id: string; variants: unknown[] }>;
    expect(products.map((p) => p.id).sort()).toEqual(['tracker', 'watch']);
    expect(products.find((p) => p.id === 'watch')!.variants.length).toBeGreaterThan(0);
  });

  it('refuses an order when the colour is out of stock, then accepts it once stocked', async () => {
    const a = app();
    const products = (await a.inject({ method: 'GET', url: '/shop/products' })).json().products;
    const variantId = products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
    const order = { customerName: 'Айгерим', phone: '+77001112233', city: 'Алматы', address: 'ул. Абая 10, кв 5', items: [{ variantId, qty: 1 }] };

    // Seeded stock is 0 → the order is refused with 409, nothing is created.
    const refused = await a.inject({ method: 'POST', url: '/shop/orders', payload: order });
    expect(refused.statusCode).toBe(409);
    expect(refused.json().error).toBe('out_of_stock');

    // Admin sets the stock for that colour.
    const set = await a.inject({ method: 'PATCH', url: `/admin/shop/variants/${variantId}`, payload: { stock: 3 } });
    expect(set.statusCode).toBe(200);

    // Now the order goes through.
    const placed = await a.inject({ method: 'POST', url: '/shop/orders', payload: order });
    expect(placed.statusCode).toBe(201);
    expect(placed.json().totalMinor).toBe(2900000); // 29 000 ₸

    // Stock is now 2, and the order is visible to admin with its address.
    const variants = (await a.inject({ method: 'GET', url: '/admin/shop/variants' })).json().variants;
    expect(variants.find((v: { id: string }) => v.id === variantId).stock).toBe(2);
    const orders = (await a.inject({ method: 'GET', url: '/admin/shop/orders' })).json().orders;
    expect(orders).toHaveLength(1);
    expect(orders[0].address).toBe('ул. Абая 10, кв 5');
    expect(orders[0].items[0].qty).toBe(1);
  });

  it('applies the family-bundle discount when a watch and a tracker are bought together', async () => {
    const a = app();
    const products = (await a.inject({ method: 'GET', url: '/shop/products' })).json().products;
    const watch = products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
    const tracker = products.find((p: { id: string }) => p.id === 'tracker').variants[0].id;
    await a.inject({ method: 'PATCH', url: `/admin/shop/variants/${watch}`, payload: { stock: 2 } });
    await a.inject({ method: 'PATCH', url: `/admin/shop/variants/${tracker}`, payload: { stock: 2 } });

    const placed = await a.inject({
      method: 'POST', url: '/shop/orders',
      payload: { customerName: 'Данияр', phone: '+77007778899', city: 'Астана', address: 'пр. Кабанбай 1',
        items: [{ variantId: watch, qty: 1 }, { variantId: tracker, qty: 1 }] },
    });
    expect(placed.statusCode).toBe(201);
    // 29 000 + 9 900 − 2 900 = 36 000 ₸, with 2 900 ₸ recorded as the saving.
    expect(placed.json().totalMinor).toBe(3600000);
    expect(placed.json().discountMinor).toBe(290000);

    const orders = (await a.inject({ method: 'GET', url: '/admin/shop/orders' })).json().orders;
    expect(orders[0].totalMinor).toBe(3600000);
    expect(orders[0].discountMinor).toBe(290000);
    expect(orders[0].items).toHaveLength(2);
  });

  it('does not discount a lone watch — the saving needs both devices', async () => {
    const a = app();
    const products = (await a.inject({ method: 'GET', url: '/shop/products' })).json().products;
    const watch = products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
    await a.inject({ method: 'PATCH', url: `/admin/shop/variants/${watch}`, payload: { stock: 1 } });
    const placed = await a.inject({
      method: 'POST', url: '/shop/orders',
      payload: { customerName: 'Сауле', phone: '+77006665544', city: 'Алматы', address: 'ул. Сатпаева 3', items: [{ variantId: watch, qty: 1 }] },
    });
    expect(placed.json().totalMinor).toBe(2900000);
    expect(placed.json().discountMinor).toBe(0);
  });

  it('rejects a malformed order (missing address) with 400', async () => {
    const a = app();
    const r = await a.inject({ method: 'POST', url: '/shop/orders', payload: { customerName: 'X', phone: '+77000000000', city: 'Алматы', items: [] } });
    expect(r.statusCode).toBe(400);
  });
});
