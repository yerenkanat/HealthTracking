/**
 * Frames 08 / 08a / 08b — «Товары», «Карточка товара», «Категории и этапы».
 *
 * Over HTTP against a real repository, so a write can be read back.
 *
 * The stage column is the point of this feature. app/lib/domain/shop_stage.dart
 * says it in its own header: «There is no stage field on a product and
 * inventing one would be fabrication, so the recommendation is DERIVED from
 * what the app already knows». So the shop's «Для вашего этапа» has been a
 * heuristic over her pregnancy flag and her children's ages, uncorrectable
 * without editing Dart. These tests cover the column that replaces it.
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

async function signIn() {
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(r.statusCode).toBe(200);
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
}

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
      // Real session resolution from the cookie. Returning null here made every
      // request 401 and would have tested nothing but the gate.
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
}

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const patch = (id: string, body: Record<string, unknown>) =>
  app.inject({ method: 'PATCH', url: `/admin/shop/products/${id}`, headers: { cookie }, payload: body });

beforeEach(async () => { app = makeApp(); await signIn(); });

describe('GET /admin/shop/products', () => {
  it('returns products, categories and the stage vocabulary', async () => {
    const b = (await get('/admin/shop/products')).json();
    expect(b.products.length).toBeGreaterThan(0);
    expect(b.categories.map((c: { id: string }) => c.id)).toContain('watch');
    // The panel builds its «этап» dropdown from this rather than hardcoding a
    // list that can drift from the CHECK constraint.
    expect(b.stages).toContain('pregnancy');
    await app.close();
  });

  it('shows an uncategorised product as uncategorised, not as a guess', async () => {
    const b = (await get('/admin/shop/products')).json();
    const tracker = b.products.find((p: { id: string }) => p.id === 'tracker');
    // Null, not 'other'. A default would hide the work still to do.
    expect(tracker.category).toBeNull();
    expect(tracker.stage).toBeNull();
    await app.close();
  });

  it('carries the stock the inventory screen already computes', async () => {
    // One product read, not two. A second catalogue-only query would drift from
    // this one the first time either gained a filter.
    const b = (await get('/admin/shop/products')).json();
    for (const p of b.products) expect(typeof p.stock).toBe('number');
    await app.close();
  });
});

describe('PATCH /admin/shop/products/:id', () => {
  it('sets the stage, and the read shows it', async () => {
    expect((await patch('tracker', { stage: 'toddler' })).statusCode).toBe(200);
    const b = (await get('/admin/shop/products')).json();
    expect(b.products.find((p: { id: string }) => p.id === 'tracker').stage).toBe('toddler');
    await app.close();
  });

  it('leaves untouched fields ALONE', async () => {
    // The product card saves one tab at a time. If an absent key cleared its
    // column, saving SEO would wipe персонализация — silently, and only
    // noticed by whoever authored the age band a week later.
    await patch('tracker', { seoTitle: 'Детский трекер' });
    const t = (await get('/admin/shop/products')).json()
      .products.find((p: { id: string }) => p.id === 'tracker');
    expect(t.seoTitle).toBe('Детский трекер');
    expect(t.ageMinMonths).toBe(24); // seeded, and not sent in that PATCH
    expect(t.ageMaxMonths).toBe(120);
    await app.close();
  });

  it('clears a field when explicitly sent null', async () => {
    // Distinct from absent. «Не указан» is a real edit.
    await patch('watch', { stage: null });
    const w = (await get('/admin/shop/products')).json()
      .products.find((p: { id: string }) => p.id === 'watch');
    expect(w.stage).toBeNull();
    await app.close();
  });

  it('refuses a stage outside the vocabulary', async () => {
    const r = await patch('tracker', { stage: 'menopause' });
    expect(r.statusCode).toBe(400);
    await app.close();
  });

  it('refuses an age band that ends before it starts', async () => {
    // The DB has the same CHECK; this is a 400 naming the field rather than a
    // 500 from a constraint violation on a screen where two numbers were typed.
    const r = await patch('tracker', { ageMinMonths: 36, ageMaxMonths: 12 });
    expect(r.statusCode).toBe(400);
    await app.close();
  });

  it('refuses a field it does not know', async () => {
    // .strict(): a typo in the panel must not be accepted and silently dropped.
    const r = await patch('tracker', { stagee: 'toddler' });
    expect(r.statusCode).toBe(400);
    await app.close();
  });
});

describe('«Двуязычность блокирует публикацию»', () => {
  it('refuses to activate a product with no Kazakh name', async () => {
    // tracker is seeded without one. The same rule the content editor already
    // applies to a lesson.
    const r = await patch('tracker', { active: true });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('kk_required');
    await app.close();
  });

  it('checks the row as it WILL be, not only what was sent', async () => {
    // Name and activation in one request must pass: refusing this would make
    // the rule impossible to satisfy in a single save.
    const r = await patch('tracker', { nameKk: 'Балалар трекері', active: true });
    expect(r.statusCode).toBe(200);
    await app.close();
  });

  it('allows deactivating a product that has no Kazakh name', async () => {
    // The rule blocks PUBLISHING, not withdrawing. Blocking both would strand
    // an incomplete product on the storefront.
    expect((await patch('tracker', { active: false })).statusCode).toBe(200);
    await app.close();
  });
});

describe('categories (frame 08b)', () => {
  it('creates one and lists it', async () => {
    const r = await app.inject({
      method: 'PUT', url: '/admin/shop/categories/gifts', headers: { cookie },
      payload: { nameRu: 'Подарки', nameKk: 'Сыйлықтар', sort: 40 },
    });
    expect(r.statusCode).toBe(200);
    const b = (await get('/admin/shop/products')).json();
    expect(b.categories.find((c: { id: string }) => c.id === 'gifts').nameRu).toBe('Подарки');
    await app.close();
  });

  it('refuses an id that is not a slug', async () => {
    const r = await app.inject({
      method: 'PUT', url: '/admin/shop/categories/Подарки!', headers: { cookie },
      payload: { nameRu: 'Подарки' },
    });
    expect(r.statusCode).toBe(400);
    await app.close();
  });

  it('will not delete a category that still has products', async () => {
    // The FK is ON DELETE SET NULL, so this would otherwise succeed and quietly
    // uncategorise a shelf. 409, not 404: it exists, it is in use.
    await patch('tracker', { category: 'tracker' });
    const r = await app.inject({
      method: 'DELETE', url: '/admin/shop/categories/tracker', headers: { cookie },
    });
    expect(r.statusCode).toBe(409);
    await app.close();
  });

  it('deletes an empty one', async () => {
    await app.inject({
      method: 'PUT', url: '/admin/shop/categories/gifts', headers: { cookie },
      payload: { nameRu: 'Подарки' },
    });
    const r = await app.inject({
      method: 'DELETE', url: '/admin/shop/categories/gifts', headers: { cookie },
    });
    expect(r.statusCode).toBe(200);
    // Read back: a 200 over a category still in the rail is the failure this
    // route exists to prevent, and «удалено» over an unchanged storefront is
    // exactly what nobody would notice.
    const after = (await get('/admin/shop/products')).json();
    expect(after.categories.some((c: { id: string }) => c.id === 'gifts')).toBe(false);
    await app.close();
  });
});

describe('who may edit the catalogue', () => {
  it('refuses an anonymous write', async () => {
    const r = await app.inject({
      method: 'PATCH', url: '/admin/shop/products/tracker', payload: { stage: 'toddler' },
    });
    expect([401, 403]).toContain(r.statusCode);
    await app.close();
  });

  it('records the edit in the audit log', async () => {
    // «каждый просмотр в журнале» — and every change, with the fields touched,
    // so «кто поменял этап» has an answer.
    await patch('tracker', { stage: 'toddler' });
    const entries = (await repo.listAudit(50)).entries;
    const row = entries.find((e) => e.action === 'product_update');
    expect(row).toBeTruthy();
    expect(row!.target).toBe('tracker');
    expect(row!.reason).toContain('stage');
    await app.close();
  });
});
