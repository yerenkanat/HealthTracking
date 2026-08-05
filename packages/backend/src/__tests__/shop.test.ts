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
    const products = r.json().products as Array<{ id: string; kind: string; variants: unknown[]; parts: Array<{ partId: string }> }>;
    // The комплект is in the catalogue too: it is a product a customer buys,
    // and leaving it out is why it could not be ordered from the storefront.
    expect(products.map((p) => p.id).sort()).toEqual(['combo', 'tracker', 'watch']);
    expect(products.find((p) => p.id === 'watch')!.variants.length).toBeGreaterThan(0);

    // A bundle has no colours of its own — it says which products the buyer
    // picks a colour of instead.
    const combo = products.find((p) => p.id === 'combo')!;
    expect(combo.kind).toBe('bundle');
    expect(combo.variants).toEqual([]);
    expect(combo.parts.map((p) => p.partId).sort()).toEqual(['tracker', 'watch']);
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
    expect(placed.json().totalMinor).toBe(2490000); // 24 900 ₸ — the landing's price

    // Stock is now 2, and the order is visible to admin with its address.
    const variants = (await a.inject({ method: 'GET', url: '/admin/shop/variants' })).json().variants;
    expect(variants.find((v: { id: string }) => v.id === variantId).stock).toBe(2);
    const orders = (await a.inject({ method: 'GET', url: '/admin/shop/orders' })).json().orders;
    expect(orders).toHaveLength(1);
    expect(orders[0].address).toBe('ул. Абая 10, кв 5');
    expect(orders[0].items[0].qty).toBe(1);
  });

  it('charges both devices at the landing prices, with no hardware bundle discount', async () => {
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
    // 24 900 + 4 900 = 29 800 ₸ — exactly the landing's à-la-carte sum. The
    // «Комплект «Мама и ребёнок»» at 39 000 ₸ is a different offer: it carries
    // the Ма!Ма! course, which is not a product here, so it cannot be modelled
    // as a discount on these two lines. See BUNDLE_DISCOUNT_MINOR.
    expect(placed.json().totalMinor).toBe(2980000);
    expect(placed.json().discountMinor).toBe(0);

    const orders = (await a.inject({ method: 'GET', url: '/admin/shop/orders' })).json().orders;
    expect(orders[0].totalMinor).toBe(2980000);
    expect(orders[0].discountMinor).toBe(0);
    expect(orders[0].items).toHaveLength(2);
  });

  it('never invents a discount the storefront does not advertise', async () => {
    const a = app();
    const products = (await a.inject({ method: 'GET', url: '/shop/products' })).json().products;
    const watch = products.find((p: { id: string }) => p.id === 'watch').variants[0].id;
    await a.inject({ method: 'PATCH', url: `/admin/shop/variants/${watch}`, payload: { stock: 1 } });
    const placed = await a.inject({
      method: 'POST', url: '/shop/orders',
      payload: { customerName: 'Сауле', phone: '+77006665544', city: 'Алматы', address: 'ул. Сатпаева 3', items: [{ variantId: watch, qty: 1 }] },
    });
    expect(placed.json().totalMinor).toBe(2490000);
    expect(placed.json().discountMinor).toBe(0);
  });

  it('rejects a malformed order (missing address) with 400', async () => {
    const a = app();
    const r = await a.inject({ method: 'POST', url: '/shop/orders', payload: { customerName: 'X', phone: '+77000000000', city: 'Алматы', items: [] } });
    expect(r.statusCode).toBe(400);
  });
});

/**
 * The landing page's "оставьте номер — перезвоним сами" form. Not an order: no
 * address, no variant, no stock. The only thing that matters is that a number
 * typed on the site becomes a row staff can work through — the form used to
 * paint a confirmation and send nothing.
 */
describe('landing callback requests', () => {
  const LEAD = {
    customerName: 'Айгерім',
    phone: '+7 707 345 22 44',
    package: 'Комплект «Мама и ребёнок» — 39 000 ₸',
    locale: 'kz' as const,
  };

  it('records a lead from the public landing without auth', async () => {
    const a = app();
    const r = await a.inject({ method: 'POST', url: '/shop/leads', payload: LEAD });
    expect(r.statusCode).toBe(201);
    expect(r.json().id).toBeTruthy();
  });

  it('shows the lead to staff with everything needed to call back', async () => {
    const a = app();
    await a.inject({ method: 'POST', url: '/shop/leads', payload: LEAD });

    const leads = (await a.inject({ method: 'GET', url: '/admin/shop/leads' })).json().leads;
    expect(leads).toHaveLength(1);
    expect(leads[0].customerName).toBe('Айгерім');
    expect(leads[0].phone).toBe('+7 707 345 22 44');
    // Which bundle they picked, and which language to call them in.
    expect(leads[0].package).toContain('39 000');
    expect(leads[0].locale).toBe('kz');
    expect(leads[0].status).toBe('new');
  });

  it('tracks what came of the call', async () => {
    const a = app();
    const id = (await a.inject({ method: 'POST', url: '/shop/leads', payload: LEAD })).json().id;

    const patched = await a.inject({ method: 'PATCH', url: `/admin/shop/leads/${id}`, payload: { status: 'called' } });
    expect(patched.statusCode).toBe(200);
    expect((await a.inject({ method: 'GET', url: '/admin/shop/leads' })).json().leads[0].status).toBe('called');

    // A status outside the lead vocabulary is refused rather than stored.
    const bad = await a.inject({ method: 'PATCH', url: `/admin/shop/leads/${id}`, payload: { status: 'shipped' } });
    expect(bad.statusCode).toBe(400);
  });

  it('defaults the package and language when the visitor left them alone', async () => {
    const a = app();
    await a.inject({ method: 'POST', url: '/shop/leads', payload: { customerName: 'Сауле', phone: '+77006665544' } });
    const lead = (await a.inject({ method: 'GET', url: '/admin/shop/leads' })).json().leads[0];
    expect(lead.package).toBe('');
    expect(lead.locale).toBe('ru');
  });

  it('refuses a lead with no phone to call — 400, not a half-row', async () => {
    const a = app();
    const r = await a.inject({ method: 'POST', url: '/shop/leads', payload: { customerName: 'X', phone: '' } });
    expect(r.statusCode).toBe(400);
  });
});
