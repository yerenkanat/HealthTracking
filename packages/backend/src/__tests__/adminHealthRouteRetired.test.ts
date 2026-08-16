/**
 * `GET /admin/users/:id/health` is gone, and nothing went with it.
 *
 * docs/BACKLOG.md §3: it was a live, guarded, audited PHI endpoint with no
 * caller anywhere — not the panel, not the app, not a tool, not a deploy
 * script. Its whole body (`latest` + `triage`, from `repo.adminUserHealth`) is
 * inside `GET /admin/users/:id/detail`, which the mother card actually opens
 * and which calls the same repository method. Same capability, same mandatory
 * reason, same audit row: deleting it closed no access and removed no guard.
 *
 * Wiring it instead would have meant a second read of rows already on screen,
 * with a second audit line and a second «зачем» prompt — the reasoning the
 * codebase already applies to `epds`, which rides /wellness rather than getting
 * a route of its own.
 *
 * This file is the record of that decision, and the guard on the half that
 * matters: the data must still be served. A test that only asserted the 404
 * would be satisfied by deleting the mother card too.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let app: FastifyInstance;
let repo: Repository;

const WHY = `?reason=${encodeURIComponent('Разбор жалобы №14')}`;

beforeEach(() => {
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
      authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
    },
    { logger: false },
  );
});
afterEach(async () => { await app.close(); });

const get = (url: string) => app.inject({ method: 'GET', url });

describe('the retired vitals route', () => {
  it('is no longer served', async () => {
    const res = await get(`/admin/users/${DEMO_USER}/health${WHY}`);
    expect(res.statusCode).toBe(404);
  });

  it('and everything it used to return is on the card that IS opened', async () => {
    const detail = (await get(`/admin/users/${DEMO_USER}/detail${WHY}`)).json();
    // The exact two keys `/health` served, from the same adminUserHealth call.
    expect(detail).toHaveProperty('latest');
    expect(detail).toHaveProperty('triage');
    const direct = await repo.adminUserHealth(DEMO_USER);
    expect(detail.latest).toEqual(direct?.latest ?? {});
    expect(detail.triage).toEqual(direct?.triage ?? []);
  });

  it('under the same reason gate it had', async () => {
    // The route that took its place must not be the weaker one.
    const bare = await get(`/admin/users/${DEMO_USER}/detail`);
    expect(bare.statusCode).toBe(400);
    expect(bare.json().error).toBe('reason_required');
  });

  it('and the read is still recorded against the staff member who made it', async () => {
    await get(`/admin/users/${DEMO_USER}/detail${WHY}`);
    const { audit } = (await get('/admin/audit')).json();
    const row = audit.find((a: { action: string }) => a.action === 'view_user_detail');
    expect(row, 'a PHI read went unrecorded').toBeDefined();
    expect(row.reason).toBe('Разбор жалобы №14');
    expect(row.target).toBe(DEMO_USER);
  });
});
