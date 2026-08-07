/**
 * The cry recording is not kept.
 *
 * The app now says so in two places — on the recording screen above the
 * microphone button, and in the privacy policy — so it has to be true, and it
 * has to stay true. A claim about what happens to audio recorded inside
 * somebody's home, of their baby, is the last claim in this product that should
 * rest on somebody remembering.
 *
 * docs/CLAUDE-app-design.md asks for something stronger: «Плач разбирается на
 * телефоне, записи не уходят на сервер.» That is an on-device inference build,
 * not a guard, and until it exists the honest position is the one the app now
 * states: it is uploaded, analysed, and never written down. This file is what
 * makes the second half checkable.
 */

import { describe, it, expect, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const AUDIO = Buffer.from('fake m4a bytes, but bytes all the same');

/**
 * A repository that records every method anybody calls on it.
 *
 * The point is not to assert against a list of known writers — a route that
 * persists audio would use a method this test has never heard of, and a
 * whitelist would sail past it. It watches for the BYTES instead: whatever is
 * called, the audio must not be among the arguments.
 */
function watchedRepo(): { repo: Repository; calls: Array<{ name: string; args: unknown[] }> } {
  const inner = createMemoryRepository();
  const calls: Array<{ name: string; args: unknown[] }> = [];
  const repo = new Proxy(inner, {
    get(target, prop: string) {
      const value = (target as unknown as Record<string, unknown>)[prop];
      if (typeof value !== 'function') return value;
      return (...args: unknown[]) => {
        calls.push({ name: prop, args });
        return (value as (...a: unknown[]) => unknown).apply(target, args);
      };
    },
  }) as Repository;
  return { repo, calls };
}

/** Does this value contain the audio anywhere inside it? */
function carriesAudio(value: unknown, depth = 0): boolean {
  if (depth > 4 || value == null) return false;
  if (Buffer.isBuffer(value)) return value.equals(AUDIO);
  if (value instanceof Uint8Array) return Buffer.from(value).equals(AUDIO);
  if (typeof value === 'string') return value.includes(AUDIO.toString('utf8'));
  if (Array.isArray(value)) return value.some((v) => carriesAudio(v, depth + 1));
  if (typeof value === 'object') {
    return Object.values(value as Record<string, unknown>).some((v) => carriesAudio(v, depth + 1));
  }
  return false;
}

function makeApp(repo: Repository, cryAnalyze: FastifyInstance extends never ? never : (a: Buffer, ct: string) => Promise<unknown>) {
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
      authAdmin: async () => null,
      cryAnalyze,
    },
    { logger: false },
  );
}

const post = (app: FastifyInstance) =>
  app.inject({
    method: 'POST', url: '/cry/analyze',
    headers: { 'content-type': 'audio/m4a' },
    payload: AUDIO,
  });

describe('POST /cry/analyze keeps nothing', () => {
  it('answers, and writes the audio to no repository method', async () => {
    const { repo, calls } = watchedRepo();
    const app = makeApp(repo, async () => ({ reason: 'hungry', confidence: 0.8 }));

    const res = await post(app);
    expect(res.statusCode, res.body).toBe(200);
    expect(res.json().reason).toBe('hungry');

    const leaks = calls.filter((c) => c.args.some((a) => carriesAudio(a)));
    expect(
      leaks.map((c) => c.name),
      'the recording was handed to the storage layer',
    ).toEqual([]);
    await app.close();
  });

  it('does not echo the audio back in its own response', async () => {
    // A debug field carrying the clip back would put it in every log and proxy
    // between here and the phone.
    const { repo } = watchedRepo();
    const app = makeApp(repo, async () => ({ reason: 'tired', confidence: 0.6 }));
    const res = await post(app);
    expect(carriesAudio(res.body)).toBe(false);
    await app.close();
  });

  it('keeps nothing when the classifier fails either', async () => {
    // The failure path is where "we will save it and retry later" gets added,
    // and a retry queue is a store of recordings by another name.
    const { repo, calls } = watchedRepo();
    const app = makeApp(repo, async () => { throw new Error('upstream down'); });

    const res = await post(app);
    expect(res.statusCode).toBe(502);
    expect(calls.filter((c) => c.args.some((a) => carriesAudio(a)))).toEqual([]);
    await app.close();
  });

  it('hands the classifier exactly what arrived, and holds no copy after', async () => {
    // The proxy's whole job. If it buffered clips to disk to smooth out a slow
    // upstream, this is where that would show up.
    const seen: Buffer[] = [];
    const { repo } = watchedRepo();
    const app = makeApp(repo, async (audio) => {
      seen.push(audio);
      return { reason: 'hungry', confidence: 0.9 };
    });
    await post(app);
    expect(seen).toHaveLength(1);
    expect(seen[0].equals(AUDIO)).toBe(true);
    await app.close();
  });

  it('refuses an empty body rather than calling the classifier', async () => {
    const analyze = vi.fn(async () => ({ reason: 'hungry', confidence: 0.5 }));
    const { repo } = watchedRepo();
    const app = makeApp(repo, analyze);
    const res = await app.inject({
      method: 'POST', url: '/cry/analyze',
      headers: { 'content-type': 'audio/m4a' },
      payload: Buffer.alloc(0),
    });
    expect(res.statusCode).toBe(400);
    expect(analyze).not.toHaveBeenCalled();
    await app.close();
  });

  it('a signed-out caller cannot upload at all', async () => {
    const anon = buildServer(
      {
        repo: createMemoryRepository(),
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
        cryAnalyze: async () => ({ reason: 'hungry', confidence: 0.5 }),
      },
      { logger: false },
    );
    expect((await post(anon)).statusCode).toBe(401);
    await anon.close();
  });
});
