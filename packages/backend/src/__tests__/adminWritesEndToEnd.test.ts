/**
 * Can staff actually change anything?
 *
 * The render audit proved every tab draws. Drawing is half the job: this panel
 * is where a lead is marked as called, an order is marked shipped, stock is
 * corrected and a colleague is given access. A control that renders and writes
 * nothing is indistinguishable from a working one until somebody asks why the
 * lead is still marked new.
 *
 * These go through the real routes and then READ THE VALUE BACK from the
 * repository. Asserting the response was 200 would only prove the server
 * answered, which is the mistake this file exists to avoid.
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
  expect(res.statusCode, 'the audit account could not sign in').toBe(200);
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const send = (method: 'POST' | 'PUT' | 'PATCH' | 'DELETE', url: string, payload?: unknown) =>
  app.inject({ method, url, payload: payload as never, headers: { cookie } });

describe('the shop queue', () => {
  it('marking a lead as called is stored, not just acknowledged', async () => {
    await repo.recordShopLead({
      customerName: 'Мадина', phone: '+7 701 000 00 00',
      package: 'Комплект', locale: 'ru',
    });
    const before = (await repo.adminShopLeads(50))[0];
    expect(before.status).toBe('new');

    const res = await send('PATCH', `/admin/shop/leads/${before.id}`, { status: 'called' });
    expect(res.statusCode).toBe(200);

    const after = (await repo.adminShopLeads(50)).find((l) => l.id === before.id)!;
    expect(after.status, 'the panel said it saved and the row did not change').toBe('called');
  });

  it('refuses a status that is not one of ours', async () => {
    await repo.recordShopLead({ customerName: 'X', phone: '+7 700 000 00 00', package: '', locale: 'ru' });
    const lead = (await repo.adminShopLeads(50))[0];
    const res = await send('PATCH', `/admin/shop/leads/${lead.id}`, { status: 'банан' });
    expect(res.statusCode).toBe(400);
    expect((await repo.adminShopLeads(50))[0].status).toBe('new');
  });
});

describe('storefront settings', () => {
  it('saves what the form sends and reads it back', async () => {
    const res = await send('PUT', '/admin/settings', {
      whatsapp: '77070000000',
      kaspiUrl: 'https://kaspi.kz/shop/x',
      // `rating: '4.8'` and `reviewCount: '37'` used to be here and used to be
      // asserted as stored. Both are withdrawn: /shop/config never published
      // either, because nothing in this schema can produce a rating or a review
      // count, so the only thing saving one ever did was make the panel look
      // like it worked. An old client still sending them is ignored, not
      // refused — the same withdrawal googleMapsApiKey got. See
      // adminSettingsSecrets.test.ts and shopSettings.test.ts.
      rating: '4.8',
    });
    expect(res.statusCode).toBe(200);

    const stored = await repo.getShopSettings();
    expect(stored.whatsapp).toBe('77070000000');
    expect(stored.kaspiUrl).toBe('https://kaspi.kz/shop/x');
    expect(stored.rating, 'an invented rating was stored again').toBeUndefined();
  });

  it('reaches the public storefront config, which is the point of saving it', async () => {
    // The setting exists to change what a visitor sees. A value that saves and
    // never leaves the admin API is the "wired to nothing" failure.
    await send('PUT', '/admin/settings', { whatsapp: '77071112233' });
    const cfg = await app.inject({ method: 'GET', url: '/shop/config' });
    expect(cfg.statusCode).toBe(200);
    expect(cfg.json().whatsapp).toBe('77071112233');
  });

  it('never exposes a secret through the public config', async () => {
    await send('PUT', '/admin/settings', {
      anthropicApiKey: 'sk-ant-should-never-leave',
      telegramBotToken: '123:SECRET',
    });
    const cfg = await app.inject({ method: 'GET', url: '/shop/config' });
    expect(cfg.body).not.toContain('sk-ant-should-never-leave');
    expect(cfg.body).not.toContain('SECRET');
  });
});

/**
 * Taking an order over the phone.
 *
 * The public storefront is retired, so for a while nothing anywhere could
 * create an order: sales came in on WhatsApp and went into a notebook. Stock
 * never moved, revenue was zero on every report, and the комплект could not
 * hand over the course it is sold with, because no order for it existed.
 */
describe('an order taken by hand', () => {
  /** Stock the first colour of a product and return that variant id. */
  async function stocked(productId: string, qty = 5): Promise<string> {
    const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
    const v = p.variants[0].id;
    await repo.moveStock({ variantId: v, delta: qty, reason: 'receipt' });
    return v;
  }
  const customer = {
    customerName: 'Мадина', phone: '+7 (701) 555-11-22',
    city: 'Астана', address: 'пр. Кабанбай батыра 5, кв 12',
  };

  it('reaches the order list and takes the stock with it', async () => {
    const v = await stocked('watch');

    const res = await send('POST', '/admin/shop/orders', {
      ...customer, items: [{ variantId: v, qty: 1 }], note: 'звонок с WhatsApp',
    });
    expect(res.statusCode).toBe(201);

    const orders = await repo.adminShopOrders(50);
    expect(orders, 'the panel said "заказ создан" and nothing was written').toHaveLength(1);
    expect(orders[0].city).toBe('Астана');
    // Read the shelf back, not the response: an order that does not move stock
    // is a number in a list.
    expect((await repo.adminShopVariants()).find((x) => x.id === v)!.stock).toBe(4);
  });

  it('sells the комплект at its own price and opens the course when it ships', async () => {
    const w = await stocked('watch');
    const t = await stocked('tracker');

    const res = await send('POST', '/admin/shop/orders', {
      ...customer, items: [{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }], bundleId: 'combo',
    });
    expect(res.statusCode).toBe(201);
    expect(res.json().totalMinor, 'the комплект is 39 000, not the parts sum').toBe(3900000);

    const order = (await repo.adminShopOrders(50))[0];
    expect(await repo.hasEntitlement('77015551122', 'mama_course')).toBe(false);

    const patched = await send('PATCH', `/admin/shop/orders/${order.id}`, { status: 'shipped' });
    expect(patched.statusCode).toBe(200);

    expect(await repo.hasEntitlement('77015551122', 'mama_course'),
      'the course was sold with the комплект and never handed over').toBe(true);
  });

  it('refuses to call it a комплект when the parts are not in it', async () => {
    const t = await stocked('tracker');
    const res = await send('POST', '/admin/shop/orders', {
      ...customer, items: [{ variantId: t, qty: 1 }], bundleId: 'combo',
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('incomplete_bundle');
    expect(await repo.adminShopOrders(50)).toHaveLength(0);
  });

  it('answers 409, not 400, when the shelf is short — staff can act on that', async () => {
    const p = (await repo.adminProducts()).find((x) => x.id === 'watch')!;
    const res = await send('POST', '/admin/shop/orders', {
      ...customer, items: [{ variantId: p.variants[0].id, qty: 1 }],
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('out_of_stock');
  });

  it('is not something a viewer can do', async () => {
    // Creating an order moves stock and can grant a paid course.
    const v = await stocked('watch');
    const res = await app.inject({
      method: 'POST', url: '/admin/shop/orders',
      payload: { ...customer, items: [{ variantId: v, qty: 1 }] },
    });
    expect(res.statusCode).toBe(401);
    expect(await repo.adminShopOrders(50)).toHaveLength(0);
  });
});

describe('staff management', () => {
  it('adding a colleague creates an account that can sign in', async () => {
    const res = await send('POST', '/admin/staff', {
      phone: '+7 702 333 44 55', displayName: 'Айгерім',
      role: 'support', password: 'a-real-password',
    });
    expect(res.statusCode).toBe(200);

    const login = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: '77023334455', password: 'a-real-password' },
    });
    expect(login.statusCode, 'the account was created but cannot be used').toBe(200);
  });
});

describe('every write is refused without a session', () => {
  it.each([
    ['PUT', '/admin/settings', { whatsapp: '7' }],
    ['POST', '/admin/staff', { phone: '77020000000', displayName: 'X', role: 'admin', password: 'password123' }],
  ] as const)('%s %s', async (method, url, payload) => {
    const res = await app.inject({ method, url, payload: payload as never });
    expect(res.statusCode).toBe(401);
  });

  it('and the settings are untouched afterwards', async () => {
    await send('PUT', '/admin/settings', { whatsapp: '77079999999' });
    await app.inject({ method: 'PUT', url: '/admin/settings', payload: { whatsapp: 'hijacked' } });
    expect((await repo.getShopSettings()).whatsapp).toBe('77079999999');
  });
});
