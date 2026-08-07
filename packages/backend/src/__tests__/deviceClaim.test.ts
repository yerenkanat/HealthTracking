/**
 * Claiming a device by the code on its box.
 *
 * `deviceByActivationCode` was written for this and had NO ROUTE. It was
 * documented as "the fallback path: units already in the wild whose serial
 * nobody captured", it worked, and it was reachable only from its own unit
 * test — the repo's signature defect, on the feature that decides whether a
 * paying customer can use what she bought.
 *
 * It is not a tidiness problem. The pairing gate in crud.ts refuses
 * `device_not_ours` the moment DEVICE_REGISTRY_ENFORCE=1 is set, and the reason
 * that switch is still off is exactly that flipping it would refuse real
 * customers with no way through. This is the way through. Without it the choice
 * was between an unenforced gate and turning away people who paid us.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { MAX_CLAIMS } from '../routes/phoneAuth';

let repo: Repository;
let app: FastifyInstance;

/** The demo profile's number — what a claim binds a unit to. */
const MY_PHONE = '77001112233';

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
      authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
    },
    { logger: false },
  );
  // A unit received at intake, with the code printed on its box.
  await repo.addDeviceSerials([
    { serial: 'AABBCC000001', kind: 'band', activationCode: 'KZ-1234', addedBy: 's1' },
  ]);
});

const claim = (code: string) =>
  app.inject({ method: 'POST', url: '/devices/claim', payload: { code } as never });

describe('the code on the box gets her in', () => {
  it('claims the unit and hands back its serial', async () => {
    // The serial comes back so the app can pair without asking a customer to
    // read a MAC address off a sticker.
    const res = await claim('KZ-1234');
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().serial).toBe('AABBCC000001');
    expect(res.json().kind).toBe('band');
  });

  it('binds it to her number, so it cannot walk onto a second account', async () => {
    await claim('KZ-1234');
    const unit = await repo.deviceRegistryEntry('AABBCC000001');
    expect(unit?.activatedByPhone).toBe(MY_PHONE);
  });

  it('is forgiving about how the code is typed', async () => {
    // It is read off a box and typed by hand, often by somebody who has just
    // been told her new watch does not work.
    for (const typed of ['kz1234', 'KZ 1234', 'kz-1234']) {
      const fresh = createMemoryRepository();
      await fresh.addDeviceSerials([
        { serial: 'AABBCC000009', kind: 'band', activationCode: 'KZ-1234', addedBy: 's1' },
      ]);
      expect(await fresh.deviceByActivationCode(typed), typed).not.toBeNull();
    }
  });

  it('and then pairing works — which is the whole point', async () => {
    // End to end: claim, then pair the serial the claim returned. Before this
    // route existed, that second step is where she was refused.
    const { serial } = (await claim('KZ-1234')).json();
    const paired = await app.inject({
      method: 'POST', url: '/devices',
      payload: { id: serial, name: 'Часы', kind: 'band' } as never,
    });
    expect(paired.statusCode, paired.body).toBe(201);
  });
});

describe('a code is worth exactly one device', () => {
  it('refuses a code somebody else has already used', async () => {
    // Without this, one code posted in a chat group unlocks every unit anybody
    // cares to pair — the code becomes the grey-market product.
    //
    // TWO layers refuse it: the route checks before writing, and
    // markDeviceActivated returns false when the unit is already bound. This
    // asserts the OUTCOME rather than which one fired — disabling either alone
    // leaves the other holding, which is the point of having both.
    await repo.markDeviceActivated('AABBCC000001', '77009998877');
    const res = await claim('KZ-1234');
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('already_claimed');
    // Still theirs. A refused claim must not quietly rebind the unit.
    expect((await repo.deviceRegistryEntry('AABBCC000001'))?.activatedByPhone)
      .toBe('77009998877');
  });

  it('the storage layer refuses it too, not only the route', async () => {
    // The half that survives somebody simplifying the handler. It is also what
    // makes two apps claiming the same code in the same second safe: the check
    // and the write are one operation down there, and two in the route.
    await repo.markDeviceActivated('AABBCC000001', '77009998877');
    expect(await repo.markDeviceActivated('AABBCC000001', MY_PHONE)).toBe(false);
  });

  it('but lets HER re-claim her own after a reinstall', async () => {
    // Idempotent on purpose. Telling a customer the watch in her hand belongs
    // to somebody else is the worst possible answer, and a reinstall is normal.
    expect((await claim('KZ-1234')).statusCode).toBe(200);
    const again = await claim('KZ-1234');
    expect(again.statusCode, again.body).toBe(200);
    expect(again.json().serial).toBe('AABBCC000001');
  });
});

describe('what it refuses', () => {
  it('a code that matches nothing', async () => {
    const res = await claim('NOPE-9999');
    expect(res.statusCode).toBe(404);
    expect(res.json().error).toBe('unknown_code');
  });

  it('a unit we have blocked — stolen, or swapped under warranty', async () => {
    await repo.setDeviceRegistryStatus('AABBCC000001', 'blocked');
    const res = await claim('KZ-1234');
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('device_blocked');
    // And it stays unbound: a blocked unit must not quietly become hers.
    expect((await repo.deviceRegistryEntry('AABBCC000001'))?.activatedByPhone).toBeNull();
  });

  it('an anonymous caller', async () => {
    const anon = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
    const res = await anon.inject({
      method: 'POST', url: '/devices/claim', payload: { code: 'KZ-1234' } as never,
    });
    expect(res.statusCode).toBe(401);
    await anon.close();
  });

  it('a malformed body, rather than treating it as a miss', async () => {
    expect((await app.inject({ method: 'POST', url: '/devices/claim', payload: {} as never }))
      .statusCode).toBe(400);
  });
});

describe('it cannot be used to enumerate our stock', () => {
  it('stops accepting guesses past the hourly ceiling', async () => {
    // These codes are short enough to guess. A claim endpoint with no ceiling
    // is a way to walk the whole registry from one phone.
    let last = 0;
    for (let i = 0; i < MAX_CLAIMS + 2; i++) {
      last = (await claim(`WRONG-${i}`)).statusCode;
    }
    expect(last).toBe(429);
  });

  it('the refusal says when to come back', async () => {
    for (let i = 0; i < MAX_CLAIMS + 1; i++) await claim(`WRONG-${i}`);
    const res = await claim('KZ-1234');
    expect(res.statusCode).toBe(429);
    expect(res.json().retryAfterMinutes).toBeGreaterThan(0);
  });

  it('the ceiling counts wrong guesses, not just successes', async () => {
    // Counting only successful claims would leave brute force uncapped, which
    // is the direction that matters.
    for (let i = 0; i < MAX_CLAIMS + 1; i++) await claim(`WRONG-${i}`);
    expect((await claim('KZ-1234')).statusCode).toBe(429);
  });
});
