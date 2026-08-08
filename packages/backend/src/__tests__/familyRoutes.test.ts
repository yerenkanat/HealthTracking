/**
 * Screen 40 over HTTP — two accounts, one child, one link.
 *
 * familyAccess.test.ts proves the model. This drives the whole thing: the
 * mother creates a link, the father accepts it, and then he can see where the
 * child is and still cannot see anything of hers. The last part is the reason
 * this file exists — a green banner is worth nothing unless something fails
 * when it stops being true.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEMO_CHILD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const MOTHER = DEMO_USER;
const FATHER = '22222222-2222-2222-2222-222222222222';
const AUNT = '33333333-3333-3333-3333-333333333333';

let repo: Repository;
/** Whose request the next inject is. Swapped between calls. */
let caller = MOTHER;

function makeApp() {
  repo = createMemoryRepository();
  caller = MOTHER;
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
      // Per-REQUEST identity: a header when one is given, else the ambient
      // `caller`. Two concurrent injects can then be two different people —
      // which a single shared variable cannot express, and the race below
      // needs it. (An earlier version of that test used `caller` for both and
      // passed for the wrong reason: both requests were the same person, so
      // checkInvite caught the second and the atomic claim was never exercised.)
      authUser: async (req) => ({
        userId: (req.headers['x-test-user'] as string) || caller,
      }),
      authAdmin: async () => null,
    },
    { logger: false },
  );
}

let app: FastifyInstance;
beforeEach(() => { app = makeApp(); });

/** Mother invites, father accepts. Returns the token. */
async function share(level: 'viewer' | 'guardian' = 'viewer', who = FATHER) {
  caller = MOTHER;
  const made = await app.inject({
    method: 'POST', url: '/family/invites',
    payload: { level, label: 'Папа' },
  });
  const token = made.json().token as string;
  caller = who;
  const accepted = await app.inject({
    method: 'POST', url: '/family/invites/accept', payload: { token },
  });
  return { token, accepted };
}

describe('inviting somebody in', () => {
  it('hands back a token once, and stores only its hash', async () => {
    caller = MOTHER;
    const r = await app.inject({
      method: 'POST', url: '/family/invites', payload: { level: 'viewer', label: 'Папа' },
    });
    expect(r.statusCode).toBe(201);
    const token = r.json().token as string;
    expect(token.length).toBeGreaterThan(20);

    // The link is never recoverable from the server. Losing it means making a
    // new one, which is also the safer behaviour.
    const list = (await app.inject({ method: 'GET', url: '/family/access' })).json();
    expect(JSON.stringify(list)).not.toContain(token);
    expect(list.invites).toHaveLength(1);
    await app.close();
  });

  it('lets the father in, and the mother sees him on the list', async () => {
    await share();
    caller = MOTHER;
    const list = (await app.inject({ method: 'GET', url: '/family/access' })).json();
    expect(list.members).toHaveLength(1);
    expect(list.members[0].memberUserId).toBe(FATHER);
    expect(list.members[0].label).toBe('Папа');
    // Spent, so it is off the open list.
    expect(list.invites).toEqual([]);
    await app.close();
  });

  it('is one-time — the aunt cannot reuse the father\'s link', async () => {
    // «одноразовая». The link goes to a family group chat; exactly one person
    // gets in.
    const { token } = await share();
    caller = AUNT;
    const second = await app.inject({
      method: 'POST', url: '/family/invites/accept', payload: { token },
    });
    expect(second.statusCode).toBe(409);
    expect(second.json().error).toBe('already_used');

    caller = MOTHER;
    expect((await app.inject({ method: 'GET', url: '/family/access' })).json().members)
      .toHaveLength(1);
    await app.close();
  });

  it('lets exactly one in when two different people race for it', async () => {
    // Two DIFFERENT people, both requests in flight before either is awaited.
    //
    // Note what this does and does not prove. In-process the two handlers do
    // not actually interleave, so checkInvite catches the loser and the
    // conditional write underneath is never what saves us HERE. The atomicity
    // that matters against a real database is proved directly on the
    // repository in the test below; this one is the end-to-end shape.
    caller = MOTHER;
    const token = (await app.inject({
      method: 'POST', url: '/family/invites', payload: { level: 'viewer' },
    })).json().token;

    const results = await Promise.all(
      [FATHER, AUNT].map((who) =>
        app.inject({
          method: 'POST',
          url: '/family/invites/accept',
          headers: { 'x-test-user': who },
          payload: { token },
        })),
    );

    const ok = results.filter((r) => r.statusCode === 200);
    expect(ok, 'exactly one accept must win').toHaveLength(1);

    caller = MOTHER;
    expect((await app.inject({ method: 'GET', url: '/family/access' })).json().members)
      .toHaveLength(1);
    await app.close();
  });

  it('claiming an invitation is a compare-and-set, not a read then a write', async () => {
    // THE property the one-time guarantee actually rests on. Against Postgres
    // two requests really do interleave: both read the row as unused, and the
    // only thing between that and two people sharing one «одноразовая» link is
    // that the UPDATE carries `used_at IS NULL` in its WHERE clause.
    //
    // Tested on the repository because that is where the guarantee lives — the
    // route's own check is reached first and would pass either way.
    const r = createMemoryRepository();
    const now = new Date().toISOString();
    await r.createFamilyInvite({
      ownerUserId: MOTHER, tokenHash: 'h1', level: 'viewer', label: '',
      expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    });

    expect(await r.claimFamilyInvite('h1', FATHER, now)).toBe(true);
    expect(await r.claimFamilyInvite('h1', AUNT, now), 'the second claim must lose')
      .toBe(false);
    // The winner is recorded, so the mother can see who joined.
    expect((await r.familyInviteByHash('h1'))?.usedBy).toBe(FATHER);
    await app.close();
  });

  it('will not claim an expired invitation', async () => {
    // The expiry is enforced in the same conditional write, not only in the
    // route — otherwise a caller that reached the repository another way could
    // spend a dead link.
    const r = createMemoryRepository();
    await r.createFamilyInvite({
      ownerUserId: MOTHER, tokenHash: 'h2', level: 'viewer', label: '',
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    expect(await r.claimFamilyInvite('h2', FATHER, new Date().toISOString())).toBe(false);
    await app.close();
  });

  it('cannot be accepted by the person who sent it', async () => {
    caller = MOTHER;
    const token = (await app.inject({
      method: 'POST', url: '/family/invites', payload: { level: 'viewer' },
    })).json().token;
    const r = await app.inject({
      method: 'POST', url: '/family/invites/accept', payload: { token },
    });
    expect(r.statusCode).toBe(409);
    expect(r.json().error).toBe('own_invite');
    await app.close();
  });

  it('refuses a token nobody issued', async () => {
    caller = FATHER;
    const r = await app.inject({
      method: 'POST', url: '/family/invites/accept', payload: { token: 'x'.repeat(40) },
    });
    expect(r.statusCode).toBe(409);
    expect(r.json().error).toBe('not_found');
    await app.close();
  });

  it('can be called back before anybody uses it', async () => {
    caller = MOTHER;
    await app.inject({ method: 'POST', url: '/family/invites', payload: { level: 'viewer' } });
    const hash = (await app.inject({ method: 'GET', url: '/family/access' }))
      .json().invites[0].tokenHash;
    expect((await app.inject({ method: 'DELETE', url: `/family/invites/${hash}` })).statusCode)
      .toBe(200);
    // A second revoke is a 404, not a cheerful ok — "I revoked it" over a link
    // that is still live is the one wrong answer this route can give.
    expect((await app.inject({ method: 'DELETE', url: `/family/invites/${hash}` })).statusCode)
      .toBe(404);
    await app.close();
  });
});

describe('what a relative can reach', () => {
  it('the child\'s zones and the day\'s trail', async () => {
    await share('viewer');
    caller = FATHER;
    for (const url of [
      `/children/${DEMO_CHILD}/geofences`,
      `/children/${DEMO_CHILD}/day`,
      `/children/${DEMO_CHILD}/events`,
    ]) {
      expect((await app.inject({ method: 'GET', url })).statusCode, url).toBe(200);
    }
    await app.close();
  });

  it('NOTHING of the mother\'s own — the green banner, enforced', async () => {
    // «здоровье и цикл не видит никто». If any of these ever answers with her
    // data, screen 40 is lying to her.
    await share('guardian');
    caller = FATHER;
    for (const url of ['/day-logs?from=2026-01-01&to=2026-12-31', '/weight', '/sleep',
      '/appointments', '/medications', '/profile']) {
      const r = await app.inject({ method: 'GET', url });
      // These are all scoped to the CALLER's own userId, so the father gets
      // his own empty account rather than hers. What must never happen is her
      // rows appearing in his response.
      expect(JSON.stringify(r.json()), url).not.toContain(DEMO_CHILD);
    }
    // And her children are not his children.
    expect((await app.inject({ method: 'GET', url: '/children' })).json().children)
      .toEqual([]);
    await app.close();
  });

  it('where she is NOW — the whole point of the feature', async () => {
    // /children/:id/location lives in server.ts rather than crud.ts, so it did
    // not get the shared guard with the others: a father could read the day's
    // trail and the zones and not the live pin, which is the one thing he
    // opened the app for.
    await share('viewer');
    await repo.insertLocation({
      childId: DEMO_CHILD,
      observedAt: new Date().toISOString(),
      source: 'gps',
      coords: { lat: 43.238, lng: 76.889 },
    });
    caller = FATHER;
    const r = await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/location`,
    });
    expect(r.statusCode).toBe(200);
    expect(r.json().coords.lat).toBeCloseTo(43.238, 3);
    await app.close();
  });

  it('and a stranger still cannot have it', async () => {
    await repo.insertLocation({
      childId: DEMO_CHILD,
      observedAt: new Date().toISOString(),
      source: 'gps',
      coords: { lat: 43.238, lng: 76.889 },
    });
    caller = AUNT;
    expect((await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/location`,
    })).statusCode).toBe(403);
    await app.close();
  });

  it('a viewer may look at a zone and not move it', async () => {
    await share('viewer');
    caller = FATHER;
    const r = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/geofences`,
      payload: {
        id: '44444444-4444-4444-4444-444444444444',
        name: 'Двор', shape: 'circle',
        center: { lat: 43.2, lng: 76.8 }, radiusM: 100,
      },
    });
    expect(r.statusCode).toBe(403);
    await app.close();
  });

  it('a guardian may move it', async () => {
    await share('guardian');
    caller = FATHER;
    const r = await app.inject({
      method: 'POST', url: `/children/${DEMO_CHILD}/geofences`,
      payload: {
        id: '44444444-4444-4444-4444-444444444444',
        name: 'Двор', shape: 'circle',
        center: { lat: 43.2, lng: 76.8 }, radiusM: 100,
      },
    });
    expect(r.statusCode).toBeLessThan(300);
    await app.close();
  });

  it('a stranger reaches none of it', async () => {
    caller = AUNT;
    for (const url of [
      `/children/${DEMO_CHILD}/geofences`,
      `/children/${DEMO_CHILD}/day`,
    ]) {
      expect((await app.inject({ method: 'GET', url })).statusCode, url).toBe(403);
    }
    await app.close();
  });

  it('stops the moment access is taken away', async () => {
    await share('viewer');
    caller = FATHER;
    expect((await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day`,
    })).statusCode).toBe(200);

    caller = MOTHER;
    expect((await app.inject({
      method: 'DELETE', url: `/family/access/${FATHER}`,
    })).statusCode).toBe(200);

    caller = FATHER;
    expect((await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day`,
    })).statusCode).toBe(403);
    await app.close();
  });

  it('tells the father whose children he can see', async () => {
    // Without it his app launches into an empty account and looks broken.
    await share('viewer');
    caller = FATHER;
    const mine = (await app.inject({ method: 'GET', url: '/family/access' })).json();
    expect(mine.memberships).toEqual([{ ownerUserId: MOTHER, level: 'viewer' }]);
    // And he has nobody under him.
    expect(mine.members).toEqual([]);
    await app.close();
  });
});

describe('accepting twice', () => {
  it('re-levels rather than granting twice', async () => {
    // Two rows for one person would mean one revoke leaves the other in place.
    await share('viewer');
    await share('guardian');
    caller = MOTHER;
    const list = (await app.inject({ method: 'GET', url: '/family/access' })).json();
    expect(list.members).toHaveLength(1);
    expect(list.members[0].level).toBe('guardian');

    expect((await app.inject({
      method: 'DELETE', url: `/family/access/${FATHER}`,
    })).statusCode).toBe(200);
    caller = FATHER;
    expect((await app.inject({
      method: 'GET', url: `/children/${DEMO_CHILD}/day`,
    })).statusCode).toBe(403);
    await app.close();
  });
});
