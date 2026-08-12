/**
 * What each role can actually REACH, driven over HTTP.
 *
 * capabilities.test.ts checks the matrix; a matrix is only a claim about data.
 * This checks the wiring — that a guard is on the route and that it is the one
 * the job needs. The two failures worth catching are opposite in shape and both
 * were live before this file:
 *
 *   - too open: every signed-in member of staff, a warehouse hand included,
 *     could open any customer's health record, her children and their last
 *     known locations, because the only check was "are you signed in";
 *   - too closed: everything that mattered was `role === 'admin'`, so a seller
 *     or a warehouse hand could be given an account and then not do their job
 *     from it.
 *
 * The pairs below are the spec's own sentences: «без маржи и без детей» for a
 * seller, «склад» and nothing else for the warehouse.
 */

import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { STAFF_ROLES, type StaffRole } from '../auth/capabilities';

function makeApp(role: StaffRole | null): FastifyInstance {
  const repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => (role ? { staffId: 's1', role } : null),
    },
    { logger: false },
  );
}

/** Status of a GET as [role]. Closes the server so this cannot leak handles. */
async function statusAs(role: StaffRole | null, url: string): Promise<number> {
  const app = makeApp(role);
  try {
    return (await app.inject({ method: 'GET', url })).statusCode;
  } finally {
    await app.close();
  }
}

/// The route that most obviously belongs to each capability. Deliberately a
/// READ each time: a 403 on a read is unambiguous, where a write could be
/// refused for a dozen unrelated reasons and still look like a passing guard.
const GUARDED: Array<{ url: string; allow: StaffRole[]; what: string }> = [
  { url: '/admin/users/1/health', allow: ['owner', 'admin', 'clinician'], what: 'a health record' },
  { url: '/admin/users/1/detail', allow: ['owner', 'admin', 'clinician'], what: 'a family, assembled' },
  { url: '/admin/children/stats', allow: ['owner', 'admin', 'clinician'], what: 'children' },
  { url: '/admin/safety', allow: ['owner', 'admin', 'clinician'], what: 'the safety feed' },
  { url: '/admin/devices', allow: ['owner', 'admin', 'clinician'], what: 'the fleet, with child names on it' },
  { url: '/admin/dashboard', allow: ['owner', 'admin'], what: 'revenue and margin' },
  { url: '/admin/audit', allow: ['owner', 'admin'], what: 'the audit log' },
  { url: '/admin/settings', allow: ['owner', 'admin'], what: 'the stored API keys' },
  { url: '/admin/staff', allow: ['owner', 'admin'], what: 'the staff roster' },
  { url: '/admin/inventory', allow: ['owner', 'admin', 'seller', 'warehouse'], what: 'the warehouse' },
  { url: '/admin/device-registry', allow: ['owner', 'admin', 'seller', 'warehouse'], what: 'the device registry' },
  { url: '/admin/shop/orders', allow: ['owner', 'admin', 'operator', 'seller', 'support'], what: 'orders' },
  { url: '/admin/shop/leads', allow: ['owner', 'admin', 'operator', 'seller', 'support'], what: 'leads' },
  { url: '/admin/users', allow: ['owner', 'admin', 'operator', 'seller', 'support', 'clinician'], what: 'the customer list' },
  { url: '/admin/emergencies', allow: ['owner', 'admin', 'operator', 'support', 'clinician'], what: 'the emergency feed' },
  { url: '/admin/course/lessons', allow: ['owner', 'admin', 'content'], what: 'the course' },
  // The money screens. These were absent from this table while a case named
  // «a seller sees no margin and no children» sat green two screens below —
  // it checked /admin/dashboard and never /admin/finance, which asked for
  // `stock` and so admitted both of the roles the spec keeps margin from. A
  // warehouse hand could open Финансы and download the margin CSV.
  //
  // A route that returns cost or margin belongs HERE, not only in a sentence
  // about a seller. Adding the neighbours at the same time, because the same
  // gap admitted them: /admin/owner is the same figures on a different screen,
  // and /admin/entitlements is who paid for what.
  { url: '/admin/finance', allow: ['owner', 'admin'], what: 'cost, margin and the revenue CSV' },
  { url: '/admin/owner', allow: ['owner', 'admin'], what: 'the owner dashboard — the same money, another screen' },
  { url: '/admin/entitlements', allow: ['owner', 'admin', 'seller', 'operator', 'support'], what: 'who paid for the course' },
  { url: '/admin/security', allow: ['owner', 'admin'], what: 'who read which health record' },
];

describe('what a role can reach', () => {
  for (const { url, allow, what } of GUARDED) {
    const denied = STAFF_ROLES.filter((r) => !allow.includes(r));

    it(`${url} — ${what}`, async () => {
      for (const role of allow) {
        const code = await statusAs(role, url);
        expect(code, `${role} must be able to open ${url}`).not.toBe(403);
        expect(code, `${role} must be able to open ${url}`).not.toBe(401);
      }
      for (const role of denied) {
        expect(await statusAs(role, url), `${role} must NOT reach ${url}`).toBe(403);
      }
    });
  }

  it('signed out is 401, not 403 — the panel shows a sign-in, not a refusal', async () => {
    for (const url of ['/admin/users/1/health', '/admin/dashboard', '/admin/shop/orders']) {
      expect(await statusAs(null, url)).toBe(401);
    }
  });

  it('a refusal names the capability, so the panel can say what is missing', async () => {
    const app = makeApp('warehouse');
    const res = await app.inject({ method: 'GET', url: '/admin/users/1/health' });
    await app.close();
    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ error: 'forbidden', need: 'health' });
  });
});

describe('the two sentences the spec is explicit about', () => {
  it('a seller sees no margin and no children', async () => {
    // «заказы, витрина, остатки, контакты — без маржи и без детей»
    for (const url of [
      '/admin/dashboard', // margin, revenue, stock value
      '/admin/children/stats',
      '/admin/users/1/health',
      '/admin/users/1/wellness',
      '/admin/safety',
    ]) {
      expect(await statusAs('seller', url), url).toBe(403);
    }
    // …and can still do the job she was hired for.
    for (const url of ['/admin/shop/orders', '/admin/inventory', '/admin/users']) {
      expect(await statusAs('seller', url), url).not.toBe(403);
    }
  });

  it('a warehouse hand has stock and nothing else', async () => {
    expect(await statusAs('warehouse', '/admin/inventory')).not.toBe(403);
    for (const url of ['/admin/users', '/admin/shop/orders', '/admin/users/1/health', '/admin/dashboard']) {
      expect(await statusAs('warehouse', url), url).toBe(403);
    }
  });

  it('a content editor reaches the course and no customer', async () => {
    expect(await statusAs('content', '/admin/course/lessons')).not.toBe(403);
    for (const url of ['/admin/users', '/admin/settings', '/admin/shop/orders']) {
      expect(await statusAs('content', url), url).toBe(403);
    }
  });

  it('an owner reaches everything that is guarded at all', async () => {
    for (const { url } of GUARDED) {
      expect(await statusAs('owner', url), url).not.toBe(403);
    }
  });
});
