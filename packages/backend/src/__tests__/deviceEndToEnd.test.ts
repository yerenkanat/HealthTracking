/**
 * Pairing a tracker, over HTTP, the way the app does it.
 *
 * The hardware is the product: a watch for the mother and a tag for the child.
 * Registering one wrote the id printed on the device — a BLE MAC — into a UUID
 * column, so `POST /devices` answered 500 and a paired tracker never reached
 * the server. Telemetry had the same fault one table over, so readings from a
 * real band failed too.
 *
 * Neither was visible from a unit test, because each function did what it said.
 * So this drives the front door: register, list it back, attach it to a child,
 * send a reading, and check nobody else can see or touch it.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken } from '../http/staffAuth';

let repo: Repository;
let app: FastifyInstance;

/** What is actually printed on a tracker. Not a UUID, and never will be. */
const MAC = 'AA:BB:CC:DD:EE:FF';

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
      authUser: async (req) => {
        const h = String(req.headers.authorization ?? '');
        const token = h.startsWith('Bearer ') ? h.slice(7) : '';
        return token ? repo.userBySessionToken(hashToken(token)) : null;
      },
      authAdmin: async () => null,
    },
    { logger: false },
  );
});

async function signIn(phone: string): Promise<string> {
  const res = await app.inject({ method: 'POST', url: '/auth/phone', payload: { phone } });
  expect(res.statusCode).toBe(200);
  return res.json().token as string;
}

const as = (token: string) => ({
  get: (url: string) => app.inject({ method: 'GET', url, headers: { authorization: `Bearer ${token}` } }),
  post: (url: string, payload: unknown) =>
    app.inject({ method: 'POST', url, payload: payload as never, headers: { authorization: `Bearer ${token}` } }),
  patch: (url: string, payload: unknown) =>
    app.inject({ method: 'PATCH', url, payload: payload as never, headers: { authorization: `Bearer ${token}` } }),
});

/** Register a child and return its id, the way the app does. */
async function addChild(token: string, name: string): Promise<string> {
  const id = crypto.randomUUID();
  const res = await as(token).post('/children', { id, name });
  expect(res.statusCode, 'the child was refused').toBe(201);
  return id;
}

describe('pairing a tracker', () => {
  it('accepts the identifier printed on the device', async () => {
    const token = await signIn('+77015551122');

    const res = await as(token).post('/devices', { id: MAC, name: 'Часы', kind: 'band' });
    expect(res.statusCode, 'a MAC is what the app sends, and it must not 500').toBe(201);

    // And it comes back under the SAME id, or the app does not recognise its
    // own device and registers a duplicate on the next sync.
    const listed = (await as(token).get('/devices')).json().devices;
    expect(listed).toHaveLength(1);
    expect(listed[0].id).toBe(MAC);
    expect(listed[0].kind).toBe('band');
  });

  it('registering the same tracker twice is still one tracker', async () => {
    const token = await signIn('+77015551122');
    await as(token).post('/devices', { id: MAC, name: 'Часы', kind: 'band' });
    await as(token).post('/devices', { id: MAC, name: 'Часы', kind: 'band' });

    expect((await as(token).get('/devices')).json().devices).toHaveLength(1);
  });

  it('a tag can be attached to a child and moved to another', async () => {
    const token = await signIn('+77015551122');
    const first = await addChild(token, 'Сұлтан');
    const second = await addChild(token, 'Аружан');

    expect((await as(token).post('/devices', {
      id: MAC, name: 'Трекер', kind: 'tag', childId: first,
    })).statusCode).toBe(201);

    // Reassignment addresses the device by the id the app holds.
    expect((await as(token).patch(`/devices/${encodeURIComponent(MAC)}`, { childId: second })).statusCode)
      .toBe(200);

    const listed = (await as(token).get('/devices')).json().devices;
    expect(listed[0].childId).toBe(second);
  });
});

describe('a device belongs to one family', () => {
  it('is not listed to anybody else', async () => {
    const mine = await signIn('+77015551122');
    const stranger = await signIn('+77029998877');
    await as(mine).post('/devices', { id: MAC, name: 'Часы', kind: 'band' });

    expect((await as(stranger).get('/devices')).json().devices,
      'another account saw a tracker that is not hers').toEqual([]);
  });

  it('cannot be reassigned by somebody who does not own it', async () => {
    const mine = await signIn('+77015551122');
    const stranger = await signIn('+77029998877');
    const myChild = await addChild(mine, 'Сұлтан');
    const theirChild = await addChild(stranger, 'Басқа');
    await as(mine).post('/devices', { id: MAC, name: 'Трекер', kind: 'tag', childId: myChild });

    // Pointing my tracker at their child, or commandeering it outright, are
    // the same attack from opposite ends.
    const res = await as(stranger).patch(`/devices/${encodeURIComponent(MAC)}`, { childId: theirChild });
    expect(res.statusCode).toBe(403);
  });

  it('cannot be registered against another family\'s child', async () => {
    const mine = await signIn('+77015551122');
    const stranger = await signIn('+77029998877');
    const theirChild = await addChild(stranger, 'Басқа');

    const res = await as(mine).post('/devices', {
      id: MAC, name: 'Трекер', kind: 'tag', childId: theirChild,
    });
    expect(res.statusCode, 'a tracker was wired to a stranger\'s child').toBe(403);
  });
});
