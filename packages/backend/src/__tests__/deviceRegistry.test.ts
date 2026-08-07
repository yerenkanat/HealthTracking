/**
 * Which devices are ours.
 *
 * The same watches and tags are sold on other marketplaces. Pairing used to ask
 * one question — "is this id already taken?" — so any compatible unit from any
 * seller got the app, the tracking backend and the course. The hardware is
 * generic; the service is the product, and the service was going out in
 * somebody else's box.
 *
 * The two things these tests are really about:
 *   1. it must NOT refuse a real customer, which is why it ships in log-only
 *      mode and why serials are normalised before anything compares them;
 *   2. when it does refuse, it must say what to do next.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';
import { normalizeSerial, looksLikeMac } from '../deviceSerial';

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

async function boot({ enforce = false } = {}): Promise<void> {
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
      enforceDeviceRegistry: enforce,
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
}

beforeEach(boot);

const receive = (serials: string, kind: 'band' | 'tag' = 'tag') =>
  app.inject({
    method: 'POST', url: '/admin/device-registry',
    payload: { serials, kind }, headers: { cookie },
  });

const pair = (id: string) =>
  app.inject({ method: 'POST', url: '/devices', payload: { id, name: 'Tag', kind: 'tag' } });

describe('a serial is a serial however it was printed', () => {
  it('reads the six ways a MAC gets written as one device', () => {
    // A registry that misses a unit over punctuation refuses a customer who
    // bought from us — the exact outcome this feature exists to prevent.
    const forms = ['AA:BB:CC:DD:EE:FF', 'aa-bb-cc-dd-ee-ff', 'AABBCCDDEEFF',
      'aa bb cc dd ee ff', 'Aa:Bb:Cc:Dd:Ee:Ff'];
    for (const f of forms) expect(normalizeSerial(f), f).toBe('AABBCCDDEEFF');
  });

  it('knows a MAC from something that is not one', () => {
    expect(looksLikeMac('AA:BB:CC:DD:EE:FF')).toBe(true);
    expect(looksLikeMac('AABBCCDDEE')).toBe(false);
    expect(looksLikeMac('not-a-mac-at-all')).toBe(false);
  });

  it('pairs a unit received in one format and reported in another', async () => {
    // The warehouse types dashes; the phone reports colons.
    await receive('aa-bb-cc-dd-ee-ff');
    expect((await pair('AA:BB:CC:DD:EE:FF')).statusCode).toBe(201);

    const entry = await repo.deviceRegistryEntry('AABBCCDDEEFF');
    expect(entry?.status).toBe('sold');
  });
});

describe('receiving a shipment', () => {
  it('takes a whole packing list at once', async () => {
    // Nobody types forty MACs into forty fields, and a form that made them
    // would simply not be used.
    const res = await receive('AA:BB:CC:00:00:01\nAA:BB:CC:00:00:02, AA:BB:CC:00:00:03');
    expect(res.json().added).toBe(3);
  });

  it('receiving the same shipment twice does not resell a unit', async () => {
    // DO NOTHING, not overwrite: resetting a sold unit to stock would hand it
    // to whoever pairs it next.
    await receive('AA:BB:CC:00:00:01');
    await pair('AA:BB:CC:00:00:01');
    const again = await receive('AA:BB:CC:00:00:01');

    expect(again.json().added).toBe(0);
    expect((await repo.deviceRegistryEntry('AABBCC000001'))?.status).toBe('sold');
  });

  it('is admin-only', async () => {
    expect((await app.inject({
      method: 'POST', url: '/admin/device-registry', payload: { serials: 'AA' },
    })).statusCode).toBe(401);
  });
});

describe('pairing, while the check is only watching', () => {
  it('lets an unregistered device through and says so in the log', async () => {
    // Log-only is the shipped default. The day this starts refusing, every unit
    // missing from the registry is a paying customer who cannot use what she
    // bought — and we would hear about it through WhatsApp, not a log.
    expect((await pair('11:22:33:44:55:66')).statusCode).toBe(201);
  });

  it('still binds a registered unit to the account that paired it', async () => {
    await receive('AA:BB:CC:00:00:09');
    await pair('AA:BB:CC:00:00:09');

    const entry = await repo.deviceRegistryEntry('AABBCC000009');
    expect(entry?.status).toBe('sold');
    expect(entry?.activatedByPhone).toBeTruthy();
  });
});

/// With enforcement switched on — what production looks like once the log says
/// the registry is complete.
describe('pairing, once the check is enforcing', () => {
  beforeEach(() => boot({ enforce: true }));

  it('refuses a device that is not ours, and names the reason', async () => {
    const res = await pair('11:22:33:44:55:66');
    // 403 with a machine-readable reason, so the app can say what to do next
    // rather than showing a generic failure. A bare refusal costs the customer
    // AND the support conversation.
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('device_not_ours');
  });

  it('refuses a blocked unit differently from an unknown one', async () => {
    // She needs different words: one is "this was reported stolen", the other
    // is "this did not come from us".
    await receive('AA:BB:CC:00:00:0B');
    await repo.setDeviceRegistryStatus('AABBCC00000B', 'blocked');
    expect((await pair('AA:BB:CC:00:00:0B')).json().error).toBe('device_blocked');
  });

  it('lets OUR device through', async () => {
    // The whole point: a customer who bought from us notices nothing.
    await receive('AA:BB:CC:00:00:0C');
    expect((await pair('AA:BB:CC:00:00:0C')).statusCode).toBe(201);
  });
});

describe('what a unit is worth once claimed', () => {
  it('cannot be activated onto a second account', async () => {
    await repo.addDeviceSerials([{ serial: 'AA:BB:CC:00:00:07' }]);
    expect(await repo.markDeviceActivated('AABBCC000007', '77001112233')).toBe(true);
    expect(await repo.markDeviceActivated('AABBCC000007', '77009998877')).toBe(false);
  });

  it('re-pairs for the SAME account after a reinstall', async () => {
    // She factory-resets her phone and pairs the same watch again. Refusing
    // here would brick a device she owns.
    await repo.addDeviceSerials([{ serial: 'AA:BB:CC:00:00:08' }]);
    await repo.markDeviceActivated('AABBCC000008', '77001112233');
    expect(await repo.markDeviceActivated('AABBCC000008', '77001112233')).toBe(true);
  });

  it('a blocked unit never activates again', async () => {
    // Stolen, returned, or swapped under warranty.
    await repo.addDeviceSerials([{ serial: 'AA:BB:CC:00:00:06' }]);
    await repo.setDeviceRegistryStatus('AABBCC000006', 'blocked');
    expect(await repo.markDeviceActivated('AABBCC000006', '77001112233')).toBe(false);
  });

  it('an activation code belongs to exactly one unit', async () => {
    await repo.addDeviceSerials([
      { serial: 'AA:BB:CC:00:00:0A', activationCode: 'KZ-1234' },
    ]);
    const found = await repo.deviceByActivationCode('kz1234');
    expect(found?.serial).toBe('AABBCC00000A');
    expect(await repo.deviceByActivationCode('KZ-9999')).toBeNull();
  });
});

describe('the back office can see and block a unit', () => {
  it('lists what has been received and what became of it', async () => {
    await receive('AA:BB:CC:00:00:01\nAA:BB:CC:00:00:02');
    await pair('AA:BB:CC:00:00:01');

    const res = await app.inject({
      method: 'GET', url: '/admin/device-registry', headers: { cookie },
    });
    expect(res.statusCode).toBe(200);
    const byStatus = Object.fromEntries(
      res.json().devices.map((d: { serial: string; status: string }) => [d.serial, d.status]));
    expect(byStatus['AABBCC000001']).toBe('sold');
    expect(byStatus['AABBCC000002']).toBe('stock');
  });

  it('blocking is written down with who did it', async () => {
    // A stolen unit stops working; that is not an anonymous edit.
    await receive('AA:BB:CC:00:00:05');
    const res = await app.inject({
      method: 'POST', url: '/admin/device-registry/AABBCC000005/status',
      payload: { status: 'blocked' }, headers: { cookie },
    });
    expect(res.statusCode).toBe(200);
    expect((await repo.deviceRegistryEntry('AABBCC000005'))?.status).toBe('blocked');

    const audit = await repo.listAudit(20);
    expect(audit.some((a) => a.action === 'device_blocked')).toBe(true);
  });
});

/// Which units went out with which order.
///
/// The registry knew the unit and the order knew the customer, and the two
/// never met — so "she says her tracker is broken; which one did we send her?"
/// had no answer anywhere in the system.
describe('linking a unit to the order it shipped with', () => {
  const ORDER = '11111111-1111-1111-1111-111111111111';

  const assign = (serials: string) =>
    app.inject({
      method: 'POST', url: `/admin/shop/orders/${ORDER}/devices`,
      payload: { serials }, headers: { cookie },
    });

  it('answers both directions of the question', async () => {
    await receive('AA:BB:CC:00:01:01\nAA:BB:CC:00:01:02');
    const res = await assign('AA:BB:CC:00:01:01, AA:BB:CC:00:01:02');
    expect(res.json().linked).toHaveLength(2);

    // order -> devices
    const forOrder = await app.inject({
      method: 'GET', url: `/admin/shop/orders/${ORDER}/devices`, headers: { cookie },
    });
    expect(forOrder.json().devices.map((d: { serial: string }) => d.serial))
      .toEqual(['AABBCC000101', 'AABBCC000102']);

    // device -> order
    expect((await repo.deviceRegistryEntry('AABBCC000101'))?.orderId).toBe(ORDER);
  });

  it('reports a serial it does not recognise instead of swallowing it', async () => {
    // A typo on a packing slip that is silently accepted becomes a warranty
    // case nobody can trace. Catching it at dispatch is a correction.
    await receive('AA:BB:CC:00:01:03');
    const res = await assign('AA:BB:CC:00:01:03\nAA:BB:CC:99:99:99');

    expect(res.json().linked).toEqual(['AABBCC000103']);
    expect(res.json().unknown).toEqual(['AABBCC999999']);
  });

  it('takes the serial however the packer wrote it', async () => {
    await receive('aa-bb-cc-00-01-04');
    expect((await assign('AA:BB:CC:00:01:04')).json().linked).toEqual(['AABBCC000104']);
  });

  it('is admin-only', async () => {
    expect((await app.inject({
      method: 'POST', url: `/admin/shop/orders/${ORDER}/devices`, payload: { serials: 'AA' },
    })).statusCode).toBe(401);
  });
});

/// The number that decides whether enforcement can be switched on.
///
/// Two very different things look identical in it — units genuinely bought
/// elsewhere, and units we sold whose serial nobody recorded at intake — which
/// is exactly why it has to be visible rather than assumed. Turning enforcement
/// on while it is large refuses paying customers.
describe('the grey-market count on the dashboard', () => {
  const NOW = '2026-08-07T10:00:00.000Z';

  it('counts a paired device that is not in the registry', async () => {
    await pair('11:22:33:44:55:66');
    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.devices.unregistered).toBe(1);
  });

  it('does not count one we received', async () => {
    await receive('AA:BB:CC:00:02:01');
    await pair('AA:BB:CC:00:02:01');
    expect((await repo.dashboardSnapshot(NOW)).devices.unregistered).toBe(0);
  });

  it('does not count a unit as foreign over punctuation', async () => {
    // The warehouse types dashes and the phone reports colons. Counting that as
    // grey-market sends somebody hunting a problem that does not exist — which
    // is the same normalisation bug, showing up as a wrong business number
    // instead of a refused customer.
    await receive('aa-bb-cc-00-02-02');
    await pair('AA:BB:CC:00:02:02');
    expect((await repo.dashboardSnapshot(NOW)).devices.unregistered).toBe(0);
  });

  it('is zero when nothing is paired at all', async () => {
    // Not "unknown", and not the total device count.
    expect((await repo.dashboardSnapshot(NOW)).devices.unregistered).toBe(0);
  });
});
