/**
 * The postpartum screening, over HTTP: PUT /epds → GET /epds → the mother's card.
 *
 * The arithmetic lives on the handset (app/tool/verify_epds.dart pins the seven
 * reverse-scored items). What can only be checked here is the CHAIN — that a
 * result pushed from a phone comes back on the next one, and reaches the
 * clinician view — and the CEILING: that the ten answers cannot get in, however
 * a client tries to send them.
 *
 * That second half is not paranoia about a hypothetical client. Item 10 of the
 * scale asks about thoughts of self-harm, zod strips unknown keys silently, and
 * "silently" is exactly how a field ends up in a database nobody meant to put
 * it in. So it is asserted, at the edge and at the repository.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let app: FastifyInstance;
let repo: Repository;

const ID = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const ID2 = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';

function makeApp(admin = false) {
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
      authAdmin: async () => (admin ? { staffId: 's1', role: 'admin' } : null),
    },
    { logger: false },
  );
}

const screening = (extra: Record<string, unknown> = {}) => ({
  id: ID, takenAt: '2026-08-12T09:30:00.000Z', score: 15, band: 'high', ...extra,
});

// `Record<string, unknown>` rather than `unknown`: Fastify's `inject` is
// overloaded, and an `unknown` payload does not match `InjectPayload`, so
// TypeScript resolves to the callback overload and hands back a `Chain` instead
// of a `Promise<Response>` — at which point every `.statusCode` below is a type
// error and the whole file stops compiling. Every call site passes an object.
const put = (payload: Record<string, unknown>) =>
  app.inject({ method: 'PUT', url: '/epds', payload });
const list = () => app.inject({ method: 'GET', url: '/epds' });

beforeEach(() => { app = makeApp(); });

describe('PUT /epds', () => {
  it('stores a screening and gives it back', async () => {
    expect((await put(screening())).statusCode).toBe(200);
    const rows = (await list()).json().results;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ id: ID, score: 15, band: 'high' });
  });

  it('upserts on the id — a first sync re-pushing her history does not duplicate it', async () => {
    // The app pushes every stored result on sign-in, every sign-in.
    await put(screening());
    await put(screening());
    await put(screening({ score: 16, band: 'high' }));
    const rows = (await list()).json().results;
    expect(rows).toHaveLength(1);
    expect(rows[0].score).toBe(16);
  });

  it('returns her screenings newest first', async () => {
    await put(screening({ id: ID, takenAt: '2026-07-01T09:00:00.000Z', score: 4, band: 'low' }));
    await put(screening({ id: ID2, takenAt: '2026-08-12T09:00:00.000Z', score: 15, band: 'high' }));
    const rows = (await list()).json().results;
    expect(rows.map((r: { score: number }) => r.score)).toEqual([15, 4]);
  });

  it('refuses a score outside the scale rather than storing an impossible number', async () => {
    // 0–30 is the instrument's range. A 31 printed on a clinician's screen as
    // «31 из 30» is a number nobody can act on.
    expect((await put(screening({ score: 31 }))).statusCode).toBe(400);
    expect((await put(screening({ score: -1 }))).statusCode).toBe(400);
    expect((await put(screening({ score: 12.5 }))).statusCode).toBe(400);
    expect((await list()).json().results).toEqual([]);
  });

  it('refuses an unknown band, a bad id and a bad date', async () => {
    expect((await put(screening({ band: 'depressed' }))).statusCode).toBe(400);
    expect((await put(screening({ id: 'epds-1' }))).statusCode).toBe(400);
    expect((await put(screening({ takenAt: '12 августа' }))).statusCode).toBe(400);
  });

  it('NEVER stores the ten answers, even when a client sends them', async () => {
    // The failure being prevented: a future client attaches `answers` "for
    // completeness", zod says nothing, and item 10 — thoughts of self-harm —
    // is now in a database several staff can open.
    const res = await put(screening({
      answers: [1, 2, 1, 0, 0, 2, 3, 1, 2, 3],
      item10: 2,
      notes: 'дописала от руки',
    }));
    expect(res.statusCode).toBe(200);

    const rows = (await list()).json().results;
    expect(Object.keys(rows[0]).sort()).toEqual(['band', 'id', 'score', 'takenAt']);
    expect(JSON.stringify(rows)).not.toContain('answers');
    expect(JSON.stringify(rows)).not.toContain('item10');
    expect(JSON.stringify(rows)).not.toContain('дописала');

    // And not merely absent from the response — absent from the row itself.
    const stored = await repo.listEpds(DEMO_USER, 10);
    expect(Object.keys(stored[0]).sort()).toEqual(['band', 'id', 'score', 'takenAt']);
  });
});

describe('the clinician view', () => {
  it('carries her screenings in the audited wellness payload', async () => {
    app = makeApp(true);
    await put(screening());
    const res = await app.inject({
      method: 'GET',
      url: `/admin/users/${DEMO_USER}/wellness?reason=${encodeURIComponent('звонок пациентки')}`,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    // Rendered by the panel beside «Дневник» — see packages/admin/index.html.
    expect(body.epds).toHaveLength(1);
    expect(body.epds[0]).toMatchObject({ score: 15, band: 'high' });
    expect(JSON.stringify(body.epds)).not.toContain('answers');
  });

  it('is refused without a reason, like every other read of her record', async () => {
    app = makeApp(true);
    await put(screening());
    const res = await app.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/wellness` });
    expect(res.statusCode).toBe(400);
  });

  /**
   * Rule 5, as a route inventory rather than a promise in a comment.
   *
   * A screening result is per-person clinical context. The moment it can be
   * listed, counted or filtered on, it becomes a segment — «мамы с 13+» — and
   * that is a list nobody in this product may build. There is deliberately no
   * repository method for it either (no `epdsStats`, no cross-user list), so
   * this checks the seam it would have to come through.
   */
  it('cannot be listed, filtered or segmented across people', async () => {
    app = makeApp(true);
    await put(screening());
    for (const url of ['/admin/epds', '/admin/epds/stats', '/epds/stats']) {
      expect((await app.inject({ method: 'GET', url })).statusCode).toBe(404);
    }
    // And the user list does not carry a score to sort by.
    const users = await app.inject({ method: 'GET', url: '/admin/users' });
    expect(JSON.stringify(users.json())).not.toContain('epds');
    // Nor does the repository offer a cross-user read.
    expect(Object.keys(repo).filter((k) => k.toLowerCase().includes('epds')).sort())
      .toEqual(['listEpds', 'upsertEpds']);
  });
});

describe('erasure', () => {
  it('deletes her screenings with the account', async () => {
    await put(screening());
    expect(await repo.deleteAccount(DEMO_USER)).toBe(true);
    expect(await repo.listEpds(DEMO_USER, 10)).toEqual([]);
  });
});
