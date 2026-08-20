/**
 * The callback form, and the address it is counted against.
 *
 * `POST /shop/leads` is the only unauthenticated write on the public internet.
 * It had no limiter of its own and no `rate_limit` at the edge, so the leads
 * queue and the Telegram channel staff read could be filled by anyone.
 *
 * The half that makes a per-source limit possible at all is `trustProxy`.
 * Without it `req.ip` is 127.0.0.1 for every request that has ever reached this
 * server — Caddy is the peer, not the caller — so a "per-IP" limit is one
 * global bucket, and one script would have made this endpoint answer 429 to
 * every real customer. That is worse than no limit, so both halves are asserted
 * here together.
 *
 * The other reason this file exists: `trustProxy: true` would be a DIFFERENT
 * bug. It trusts the whole X-Forwarded-For chain and takes its leftmost entry,
 * which the caller writes — so anyone could mint a fresh bucket per request and
 * forge any address they liked into the access log. The last test is the one
 * that tells the two settings apart.
 */

import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { RateLimiter } from '../http/rateLimit';

const LEAD = { customerName: 'Айгерім', phone: '+7 700 111 22 33' };

/** @param limit leads permitted per address per window — tiny, so it is reached. */
function makeApp(limit = 2): FastifyInstance {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: 'u1' }),
      authAdmin: async () => null,
      leadLimiter: new RateLimiter({ limit, windowMs: 60_000 }),
    },
    { logger: false },
  );
}

/** A lead as it arrives through Caddy: the proxy writes the caller's address. */
const from = (app: FastifyInstance, forwardedFor: string) =>
  app.inject({
    method: 'POST',
    url: '/shop/leads',
    headers: { 'x-forwarded-for': forwardedFor },
    payload: LEAD,
  });

describe('the lead form is bounded per source', () => {
  it('takes the leads, then refuses the flood with a retry-after', async () => {
    const app = makeApp(2);
    // Non-vacuity first: the endpoint must actually work, or every 429 below
    // could be a 429 for some other reason entirely.
    const first = await from(app, '203.0.113.10');
    expect(first.statusCode).toBe(201);
    expect(first.json().id, 'the lead was not recorded').toBeTruthy();
    expect((await from(app, '203.0.113.10')).statusCode).toBe(201);

    const over = await from(app, '203.0.113.10');
    expect(over.statusCode).toBe(429);
    expect(over.json().error).toBe('rate_limited');
    // Without this a client has nothing to wait on and retries immediately,
    // which turns a limit into a busy loop.
    expect(over.headers['retry-after']).toBeTruthy();
    await app.close();
  });

  it('does not make one flooder answer 429 to everyone else', async () => {
    // THE failure being prevented. One bucket for the whole internet meant one
    // script could close the landing page's only conversion path.
    const app = makeApp(2);
    await from(app, '203.0.113.10');
    await from(app, '203.0.113.10');
    expect((await from(app, '203.0.113.10')).statusCode).toBe(429);

    const someoneElse = await from(app, '198.51.100.4');
    expect(someoneElse.statusCode, 'a stranger is being throttled for the flooder').toBe(201);
    await app.close();
  });

  it('counts the socket peer when there is no proxy header at all', async () => {
    // Dev, and any deployment where the app is reached directly.
    const app = makeApp(1);
    const one = await app.inject({ method: 'POST', url: '/shop/leads', payload: LEAD, remoteAddress: '192.0.2.7' });
    expect(one.statusCode).toBe(201);
    expect((await app.inject({ method: 'POST', url: '/shop/leads', payload: LEAD, remoteAddress: '192.0.2.7' })).statusCode)
      .toBe(429);
    expect((await app.inject({ method: 'POST', url: '/shop/leads', payload: LEAD, remoteAddress: '192.0.2.8' })).statusCode)
      .toBe(201);
    await app.close();
  });

  it('leaves other writes alone', async () => {
    const app = makeApp(1);
    await from(app, '203.0.113.11');
    expect((await from(app, '203.0.113.11')).statusCode).toBe(429);
    // The lead ceiling is not a ceiling on the app. A woman syncing her weight
    // from a phone on the same office Wi-Fi must not be caught by it.
    const write = await app.inject({
      method: 'POST', url: '/weight',
      headers: { 'x-forwarded-for': '203.0.113.11' },
      payload: { date: '2026-08-20', kg: 61 },
    });
    expect(write.statusCode).toBe(201);
    await app.close();
  });
});

describe('the forwarded chain is trusted exactly one hop deep', () => {
  it('a caller cannot mint a new bucket by writing its own X-Forwarded-For', async () => {
    // Caddy is configured to REPLACE this header (deploy/landing-takeover.sh,
    // the (backend) snippet), and Fastify is set to `trustProxy: 1`, so the
    // entry that counts is the LAST one — the one the proxy appended.
    //
    // Under `trustProxy: true` the leftmost entry wins and all three of these
    // are different callers, so every one of them would be 201 and this test
    // is what tells the two configurations apart.
    const app = makeApp(2);
    expect((await from(app, '9.9.9.9, 203.0.113.20')).statusCode).toBe(201);
    expect((await from(app, '8.8.8.8, 203.0.113.20')).statusCode).toBe(201);
    const third = await from(app, '1.1.1.1, 203.0.113.20');
    expect(third.statusCode, 'a forged left-hand entry bought a fresh bucket').toBe(429);
    await app.close();
  });

  it('and cannot pin the blame on someone else', async () => {
    // The same property from the logging side: whatever a caller writes into
    // the header, the address the server acts on is the one Caddy accepted the
    // connection from. Two callers behind different proxies claiming the same
    // left-hand address stay two callers.
    const app = makeApp(1);
    expect((await from(app, '203.0.113.30, 198.51.100.9')).statusCode).toBe(201);
    expect((await from(app, '203.0.113.30, 198.51.100.10')).statusCode).toBe(201);
    await app.close();
  });
});
