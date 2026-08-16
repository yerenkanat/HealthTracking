/**
 * «Не обработано: N» — the number that decides who gets rung back.
 *
 * The panel counted `status === 'new'` over ONE page of `/admin/shop/leads`
 * (limit 100) and printed it as a total, while «Сводка» printed «50 из 140»
 * from a real count(*). The page is ordered newest first, so what falls off it
 * are the OLDEST uncalled leads — the women who have waited longest.
 *
 * `Repository.shopLeadCounts()` now answers that count(*) — on BOTH
 * implementations — so this route serves a real total to everyone holding
 * `orders`. That matters more than it sounds: the true figure used to exist
 * only on /admin/dashboard, which requires `finance`, and seller, operator and
 * support — the three roles that actually ring people back — do not hold it.
 *
 * `counts.shown` stays beside `counts.total`: «сколько в таблице» and «сколько
 * всего» are different questions, and collapsing them is what started this.
 * Written over HTTP against a real memory repository, leads posted through the
 * public landing route.
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
    // The count came from the table rather than from the page — the panel may
    // print it without a hedge.
    expect(after.exact).toBe(true);
    expect(after.counts.total).toBe(after.counts.shown);
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

  /**
   * The case the whole item existed for: a page that does not hold the table.
   *
   * It used to answer `exact: false` and leave the panel printing «не менее 2»,
   * because the route could only count what it had returned. It now returns one
   * row AND the true two, so the queue is worked from the number of women
   * waiting rather than from the number that fitted on the screen.
   */
  it('counts the whole table even when the page holds one row of it', async () => {
    await leave('Айгерім');
    await leave('Сәуле');
    const page = (await leads('?limit=1')).json();
    expect(page.leads).toHaveLength(1);
    expect(page.counts.shown).toBe(1);
    expect(page.counts.total).toBe(2);
    expect(page.counts.uncalled).toBe(2);
    expect(page.exact).toBe(true);
    expect(page.limit).toBe(1);
  });

  it('counts a lead that has been rung out of «не обработано» but not out of the total', async () => {
    await leave('Айгерім');
    await leave('Сәуле');
    const one = (await leads('?limit=1')).json().leads[0];
    await app.inject({
      method: 'PATCH', url: `/admin/shop/leads/${one.id}`,
      headers: { cookie }, payload: { status: 'called' },
    });
    const page = (await leads('?limit=1')).json();
    expect(page.counts.total).toBe(2);
    expect(page.counts.uncalled).toBe(1);
  });

  /**
   * A count that failed must not become a total.
   *
   * The rows are what somebody rings from, so a broken counter may not blank
   * the queue — but printing the page size as the total is the failure this
   * whole route was rewritten to stop.
   */
  it('serves the rows with total = null when the count itself fails', async () => {
    await leave('Айгерім');
    repo.shopLeadCounts = async () => { throw new Error('count(*) exploded'); };
    const page = (await leads()).json();
    expect(page.leads.length).toBeGreaterThan(0);
    expect(page.counts.total).toBeNull();
    expect(page.exact).toBe(false);
    // The floor is still served, and `exact: false` is what tells the panel to
    // call it a floor.
    expect(page.counts.uncalled).toBeGreaterThan(0);
  });

  it('still hands the rows over under the old key, so nothing that read it breaks', async () => {
    const body = (await leads()).json();
    expect(Array.isArray(body.leads)).toBe(true);
  });
});
