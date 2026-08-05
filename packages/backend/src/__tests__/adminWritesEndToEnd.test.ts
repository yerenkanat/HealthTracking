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
      rating: '4.8',
      reviewCount: '37',
    });
    expect(res.statusCode).toBe(200);

    const stored = await repo.getShopSettings();
    expect(stored.whatsapp).toBe('77070000000');
    expect(stored.rating).toBe('4.8');
    expect(stored.reviewCount).toBe('37');
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
