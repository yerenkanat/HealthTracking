/**
 * «Кто ведёт обращение» — over HTTP, against the memory repository.
 *
 * `assignee_id` was selected on every ticket, patchable through
 * `PATCH /admin/support/:id`, and had NO caller and NO reader: two operators
 * answered the same woman a minute apart and neither could see the other had.
 *
 * A raw uuid on the screen would not have fixed that — nobody recognises a
 * colleague by uuid — so the route resolves it to a display name. These pin
 * both halves: the write reads back, and the name comes with it.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD, DEV_STAFF_ID,
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
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});
afterEach(async () => { await app.close(); });

const get = (url: string) => app.inject({ method: 'GET', url, headers: { cookie } });
const patch = (url: string, payload: Record<string, unknown>) =>
  app.inject({ method: 'PATCH', url, headers: { cookie }, payload });

const firstTicketId = async () => (await get('/admin/support')).json().items[0].id;

describe('taking a ticket', () => {
  it('is a write that reads back, with the colleague NAMED', async () => {
    const id = await firstTicketId();

    const w = await patch(`/admin/support/${id}`, { assigneeId: DEV_STAFF_ID });
    expect(w.statusCode).toBe(200);

    const card = (await get(`/admin/support/${id}`)).json();
    expect(card.ticket.assigneeId).toBe(DEV_STAFF_ID);
    // The point of the whole change: a name, not the uuid that was already
    // there and told nobody anything.
    expect(card.assigneeName).toBe('Разработка');

    const board = (await get('/admin/support')).json();
    const row = board.items.find((t: { id: string }) => t.id === id);
    expect(row.assigneeName).toBe('Разработка');
  });

  it('reports an id nobody holds as unresolved rather than inventing a name', async () => {
    const id = await firstTicketId();
    // A staff account that was deleted, or a repository that could not answer.
    const ghost = '99999999-9999-4999-8999-999999999999';
    expect((await patch(`/admin/support/${id}`, { assigneeId: ghost })).statusCode).toBe(200);

    const card = (await get(`/admin/support/${id}`)).json();
    expect(card.ticket.assigneeId).toBe(ghost);
    // null means "we could not resolve it" — the panel says so in words. It
    // must NOT come back as the id, which would read as a name on screen.
    expect(card.assigneeName).toBeNull();
  });

  it('gives it back, and the board stops naming anyone', async () => {
    const id = await firstTicketId();
    await patch(`/admin/support/${id}`, { assigneeId: DEV_STAFF_ID });
    expect((await patch(`/admin/support/${id}`, { assigneeId: null })).statusCode).toBe(200);

    const card = (await get(`/admin/support/${id}`)).json();
    expect(card.ticket.assigneeId).toBeNull();
    expect(card.assigneeName).toBeNull();
  });

  it('does not leak the roster to a role that may not read it', async () => {
    const id = await firstTicketId();
    await patch(`/admin/support/${id}`, { assigneeId: DEV_STAFF_ID });
    const card = (await get(`/admin/support/${id}`)).json();
    // Support holds `customers`, not `staff`. The name is what the screen
    // needs; the phone number and role of a colleague are not.
    expect(JSON.stringify(card)).not.toContain(DEV_STAFF_PHONE);
  });
});

describe('the ids this repository hands out', () => {
  it('are uuids, so the routes that validate them can be exercised', async () => {
    // The regression this guards: `staff-dev` could never be written into
    // assignee_id, so «взять обращение на себя» was untestable without
    // Postgres and quietly 400'd in memory mode.
    const id = await firstTicketId();
    expect((await patch(`/admin/support/${id}`, { assigneeId: DEV_STAFF_ID })).statusCode).toBe(200);
    const me = (await get('/admin/me')).json();
    expect(me.staffId).toBe(DEV_STAFF_ID);
  });
});

describe('what the ticket already knew and never showed', () => {
  it('carries customerReadAt and closedAt on the card', async () => {
    const id = await firstTicketId();
    const before = (await get(`/admin/support/${id}`)).json();
    // Never opened in the app, and not closed: both null, and the panel is the
    // place that turns null into a sentence rather than a dash.
    expect(before.ticket.customerReadAt).toBeNull();
    expect(before.ticket.closedAt).toBeNull();

    await repo.markSupportTicketRead(id, '2026-08-10T09:00:00.000Z');
    await patch(`/admin/support/${id}`, { status: 'closed' });

    const after = (await get(`/admin/support/${id}`)).json();
    expect(after.ticket.customerReadAt).toBe('2026-08-10T09:00:00.000Z');
    expect(after.ticket.closedAt).toBeTruthy();
  });
});
