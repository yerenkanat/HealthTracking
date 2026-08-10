/**
 * Frame 12 — «Поддержка», over HTTP against a real repository.
 *
 * support.test.ts proves the queue arithmetic. This proves the chain: a ticket
 * raised, answered, and closed, with the SLA clock stopping where it should.
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

beforeEach(async () => {
  app = makeApp();
  const r = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  expect(r.statusCode).toBe(200);
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const post = (url: string, payload: Record<string, unknown>) =>
  app.inject({ method: 'POST', url, headers: { cookie }, payload });
const patch = (url: string, payload: Record<string, unknown>) =>
  app.inject({ method: 'PATCH', url, headers: { cookie }, payload });

describe('the board', () => {
  it('lists tickets with the queue numbers', async () => {
    const b = (await get('/admin/support')).json();
    expect(Array.isArray(b.items)).toBe(true);
    expect(b.slaHours).toBe(4);
    // The seeded ticket is five hours old and unanswered.
    expect(b.waiting).toBeGreaterThan(0);
    expect(b.overdue).toBeGreaterThan(0);
    await app.close();
  });

  it('carries a WhatsApp link built by the server, not the panel', async () => {
    const b = (await get('/admin/support')).json();
    expect(b.items[0].whatsapp).toContain('wa.me/');
    await app.close();
  });

  it('offers the reply templates', async () => {
    const b = (await get('/admin/support')).json();
    expect(b.templates.length).toBeGreaterThan(0);
    // Bilingual, or an operator sends Russian to a Kazakh speaker.
    expect(b.templates.every((t: { bodyKk?: string }) => t.bodyKk)).toBe(true);
    await app.close();
  });
});

describe('raising a ticket', () => {
  it('creates one an operator took by phone', async () => {
    const r = await post('/admin/support', {
      subject: 'Спрашивает про доставку', phone: '+7 701 000 00 00',
      customerName: 'Мадина', channel: 'phone',
    });
    expect(r.statusCode).toBe(201);
    const b = (await get('/admin/support')).json();
    expect(b.items.some((t: { subject: string }) => t.subject === 'Спрашивает про доставку')).toBe(true);
    await app.close();
  });

  it('refuses one with nobody to answer', async () => {
    // The table's CHECK demands a phone or a user; a 400 naming the field beats
    // a constraint violation reaching the operator as a 500.
    const r = await post('/admin/support', { subject: 'Аноним' });
    expect(r.statusCode).toBe(400);
    await app.close();
  });
});

describe('answering stops the clock', () => {
  it('a staff reply sets answeredAt and takes it off the waiting count', async () => {
    const before = (await get('/admin/support')).json();
    const id = before.items[0].id;
    expect(before.waiting).toBe(1);

    const r = await post(`/admin/support/${id}/reply`, { body: 'Проверяю, вернусь через час.' });
    expect(r.statusCode).toBe(200);

    const after = (await get('/admin/support')).json();
    // This is the assertion the whole SLA rests on: a ticket we answered is not
    // us being slow, however long it then sits.
    expect(after.waiting).toBe(0);
    expect(after.overdue).toBe(0);
    await app.close();
  });

  it('the reply is readable on the ticket afterwards', async () => {
    const id = (await get('/admin/support')).json().items[0].id;
    await post(`/admin/support/${id}/reply`, { body: 'Проверяю.' });
    const one = (await get(`/admin/support/${id}`)).json();
    expect(one.replies).toHaveLength(1);
    expect(one.replies[0].author).toBe('staff');
    expect(one.replies[0].body).toBe('Проверяю.');
    await app.close();
  });

  it('refuses an empty reply', async () => {
    const id = (await get('/admin/support')).json().items[0].id;
    expect((await post(`/admin/support/${id}/reply`, { body: '   ' })).statusCode).toBe(400);
    await app.close();
  });

  it('404s on a ticket that does not exist', async () => {
    expect((await post('/admin/support/nope/reply', { body: 'x' })).statusCode).toBe(404);
    await app.close();
  });
});

describe('closing', () => {
  it('closes without deleting — the ticket stays readable', async () => {
    const id = (await get('/admin/support')).json().items[0].id;
    expect((await patch(`/admin/support/${id}`, { status: 'closed' })).statusCode).toBe(200);

    const one = (await get(`/admin/support/${id}`)).json();
    expect(one.ticket.status).toBe('closed');
    expect(one.ticket.closedAt).toBeTruthy();
    await app.close();
  });

  it('reopening clears the closed timestamp', async () => {
    // Otherwise a reopened ticket still claims it was closed, and the board
    // shows a date for something that is plainly open.
    const id = (await get('/admin/support')).json().items[0].id;
    await patch(`/admin/support/${id}`, { status: 'closed' });
    await patch(`/admin/support/${id}`, { status: 'open' });
    const one = (await get(`/admin/support/${id}`)).json();
    expect(one.ticket.closedAt).toBeNull();
    await app.close();
  });

  it('refuses a status it does not know', async () => {
    const id = (await get('/admin/support')).json().items[0].id;
    expect((await patch(`/admin/support/${id}`, { status: 'resolved' })).statusCode).toBe(400);
    await app.close();
  });
});

describe('who may read support', () => {
  it('refuses an anonymous request', async () => {
    const r = await app.inject({ method: 'GET', url: '/admin/support' });
    expect([401, 403]).toContain(r.statusCode);
    await app.close();
  });

  it('records every read in the audit log', async () => {
    // Every ticket names a person, so reading the board is a read of customer
    // data and «каждый просмотр в журнале» applies.
    await get('/admin/support');
    const entries = await repo.listAudit(50);
    expect(entries.some((e) => e.action === 'view_support')).toBe(true);
    await app.close();
  });
});
