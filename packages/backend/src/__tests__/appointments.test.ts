/**
 * Appointments CRUD — user-scoped, ownership-enforced, idempotent upsert. Drives
 * the REAL server (buildServer) against the real in-memory repository, with two
 * different signed-in users so a cross-account read/delete cannot succeed.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

const OTHER = '99999999-9999-9999-9999-999999999999';

function appFor(userId: string, repo = sharedRepo): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => (userId ? { userId } : null),
      authAdmin: async () => null,
    },
    { logger: false },
  );
}

let sharedRepo = createMemoryRepository();
beforeEach(() => {
  sharedRepo = createMemoryRepository();
});

const appt = (over: Record<string, unknown> = {}) => ({
  id: 'apt-1',
  title: 'Приём у гинеколога',
  at: '2026-08-03T09:30:00.000Z',
  note: 'взять результаты',
  ...over,
});

describe('appointments CRUD', () => {
  it('requires auth', async () => {
    const app = appFor('');
    const res = await app.inject({ method: 'GET', url: '/appointments' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('creates, lists (sorted by time), and deletes', async () => {
    const app = appFor(DEMO_USER);
    expect((await app.inject({ method: 'POST', url: '/appointments', payload: appt() })).statusCode).toBe(201);
    expect((await app.inject({ method: 'POST', url: '/appointments', payload: appt({ id: 'apt-2', title: 'УЗИ', at: '2026-07-20T09:00:00.000Z' }) })).statusCode).toBe(201);

    const list = (await app.inject({ method: 'GET', url: '/appointments' })).json().appointments;
    expect(list.map((a: { id: string }) => a.id)).toEqual(['apt-2', 'apt-1']); // sorted by `at`

    expect((await app.inject({ method: 'DELETE', url: '/appointments/apt-1' })).statusCode).toBe(204);
    const after = (await app.inject({ method: 'GET', url: '/appointments' })).json().appointments;
    expect(after.map((a: { id: string }) => a.id)).toEqual(['apt-2']);
    await app.close();
  });

  it('upsert on the same id updates rather than duplicates (idempotent sync)', async () => {
    const app = appFor(DEMO_USER);
    await app.inject({ method: 'POST', url: '/appointments', payload: appt() });
    await app.inject({ method: 'POST', url: '/appointments', payload: appt({ title: 'Приём — перенесён' }) });
    const list = (await app.inject({ method: 'GET', url: '/appointments' })).json().appointments;
    expect(list).toHaveLength(1);
    expect(list[0].title).toBe('Приём — перенесён');
    await app.close();
  });

  it('rejects a malformed appointment', async () => {
    const app = appFor(DEMO_USER);
    const res = await app.inject({ method: 'POST', url: '/appointments', payload: { id: 'x', title: '', at: 'not-a-date' } });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('one user cannot delete another user’s appointment', async () => {
    const owner = appFor(DEMO_USER);
    await owner.inject({ method: 'POST', url: '/appointments', payload: appt() });
    await owner.close();

    const intruder = appFor(OTHER); // same shared repo, different caller
    const res = await intruder.inject({ method: 'DELETE', url: '/appointments/apt-1' });
    expect([403, 404]).toContain(res.statusCode); // not their appointment
    await intruder.close();

    // Still there for the owner.
    const owner2 = appFor(DEMO_USER);
    const list = (await owner2.inject({ method: 'GET', url: '/appointments' })).json().appointments;
    expect(list).toHaveLength(1);
    await owner2.close();
  });
});
