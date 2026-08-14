/**
 * «Не обработано: N» — the number that decides who gets rung back.
 *
 * The panel counted `status === 'new'` over ONE page of `/admin/shop/leads`
 * (limit 100) and printed it as a total, while «Сводка» printed «50 из 140»
 * from a real count(*). The page is ordered newest first, so what falls off it
 * are the OLDEST uncalled leads — the women who have waited longest.
 *
 * There is no count(*) for leads on the repository, so the route says what it
 * can stand behind: the count is over the rows returned, and `exact` is true
 * only when the page held the whole table. Written over HTTP against a real
 * memory repository, leads posted through the public landing route.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
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
  cookie = r.headers['set-cookie']!.toString().split(';')[0];
});
afterEach(async () => { await app.close(); });

const leave = (name: string) => app.inject({
  method: 'POST', url: '/shop/leads',
  payload: { customerName: name, phone: '+7 700 000 00 01' },
});
const leads = (qs = '') =>
  app.inject({ method: 'GET', url: `/admin/shop/leads${qs}`, headers: { cookie } });

describe('the callback queue counts itself', () => {
  it('returns the uncalled count beside the rows, and says it is the whole table', async () => {
    const before = (await leads()).json();
    const wasUncalled = before.counts.uncalled;

    await leave('Айгерім');
    await leave('Сәуле');

    const after = (await leads()).json();
    expect(after.counts.shown).toBe(before.counts.shown + 2);
    expect(after.counts.uncalled).toBe(wasUncalled + 2);
    // The page held everything, so this count IS the total — the panel may
    // print it without a hedge.
    expect(after.exact).toBe(true);
  });

  it('drops a lead out of «не обработано» once somebody has rung her', async () => {
    await leave('Айгерім');
    const list = (await leads()).json();
    const fresh = list.leads.find((l: { status: string }) => l.status === 'new');

    const w = await app.inject({
      method: 'PATCH', url: `/admin/shop/leads/${fresh.id}`,
      headers: { cookie }, payload: { status: 'called' },
    });
    expect(w.statusCode).toBe(200);

    const after = (await leads()).json();
    expect(after.counts.uncalled).toBe(list.counts.uncalled - 1);
    expect(after.counts.shown).toBe(list.counts.shown);
  });

  it('admits when the page did NOT hold the whole table', async () => {
    await leave('Айгерім');
    await leave('Сәуле');
    // One row is all this page fits; there are more, and the count over it is
    // a floor rather than a total. The panel says «не менее» on this.
    const page = (await leads('?limit=1')).json();
    expect(page.leads).toHaveLength(1);
    expect(page.counts.shown).toBe(1);
    expect(page.exact).toBe(false);
    expect(page.limit).toBe(1);
  });

  it('still hands the rows over under the old key, so nothing that read it breaks', async () => {
    const body = (await leads()).json();
    expect(Array.isArray(body.leads)).toBe(true);
  });
});
