/**
 * Кадр 17c «Детектор плача» — точность, порог, и то, чего про плач узнать нельзя.
 *
 * The feature is two claims, and these drive both over HTTP against a real
 * memory repository rather than asserting on functions:
 *
 *   1. the threshold changed in the back office reaches a phone with no
 *      release — `PUT /admin/cry/threshold` moves what `GET /protocols/cry`
 *      answers, and an empty settings table answers the shipped default;
 *   2. «точность» is computed ONLY over analyses a mother rated. There is no
 *      other ground truth in this product: nothing reads a clinic and the clip
 *      is never stored, so the model's own confidence is not evidence about
 *      itself. Before a single verdict exists the route answers `accuracy:
 *      null` — not 0, which is the opposite statement.
 *
 * Plus the three ways the verdict could quietly rot: a verdict about somebody
 * else's analysis, a verdict about no analysis at all, and — the one that costs
 * the most and shows the least — the app re-pushing its history on sign-in and
 * wiping the answers with it.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { CRY_MIN_CONFIDENCE_DEFAULT } from '../cry/settings';

let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

/** The server, answering as [userId] on the app routes and as a content editor. */
function app(userId: string = DEMO_USER, r: Repository = repo): FastifyInstance {
  return buildServer(
    {
      repo: r,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId }),
      authAdmin: async () => ({ staffId: 'content-1', role: 'content' }),
    },
    { logger: false },
  );
}

const AT = '2026-08-10T21:14:00.000Z';

async function analyse(a: FastifyInstance, at: string, reason: string, confidence: number) {
  return a.inject({ method: 'POST', url: '/cry/results', payload: { at, reason, confidence } });
}

async function rate(a: FastifyInstance, at: string, verdict: string, actualReason?: string) {
  return a.inject({
    method: 'POST',
    url: `/cry/results/${encodeURIComponent(at)}/verdict`,
    payload: actualReason === undefined ? { verdict } : { verdict, actualReason },
  });
}

describe('the threshold reaches a phone without a release', () => {
  it('an empty settings table serves the shipped default, marked as such', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/protocols/cry' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({
      minConfidence: CRY_MIN_CONFIDENCE_DEFAULT,
      defaultMinConfidence: CRY_MIN_CONFIDENCE_DEFAULT,
      source: 'default',
      updatedAt: null,
      // The rule travels with the number, so the app cannot apply the threshold
      // and forget what falling below it is supposed to do.
      belowThreshold: 'name_no_reason',
    });
  });

  it('the panel changes it and the public route changes with it', async () => {
    const a = app();
    const put = await a.inject({
      method: 'PUT', url: '/admin/cry/threshold', payload: { minConfidence: 0.7 },
    });
    expect(put.statusCode).toBe(200);

    const served = (await a.inject({ method: 'GET', url: '/protocols/cry' })).json();
    expect(served.minConfidence).toBe(0.7);
    expect(served.source).toBe('override');
    expect(served.updatedAt).toBeTruthy();
    // The shipped value is still reported, so a reader can see what it was
    // changed FROM rather than having to know.
    expect(served.defaultMinConfidence).toBe(CRY_MIN_CONFIDENCE_DEFAULT);
  });

  it('the public route needs no session — a fresh install has none', async () => {
    const a = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null, // signed out
        authAdmin: async () => null,
      },
      { logger: false },
    );
    expect((await a.inject({ method: 'GET', url: '/protocols/cry' })).statusCode).toBe(200);
  });

  it('a threshold nothing could ever reach is refused', async () => {
    // 0.99 would turn the screen into a permanent «не уверены». One mistyped
    // digit must not be able to switch the feature off for everybody.
    const a = app();
    expect((await a.inject({
      method: 'PUT', url: '/admin/cry/threshold', payload: { minConfidence: 0.99 },
    })).statusCode).toBe(400);
    expect((await a.inject({
      method: 'PUT', url: '/admin/cry/threshold', payload: { minConfidence: -0.1 },
    })).statusCode).toBe(400);
    // …and nothing was stored by the refused attempts.
    expect((await a.inject({ method: 'GET', url: '/protocols/cry' })).json().source).toBe('default');
  });

  it('changing it is written to the audit log', async () => {
    const a = app();
    await a.inject({ method: 'PUT', url: '/admin/cry/threshold', payload: { minConfidence: 0.6 } });
    const rows = await repo.listAudit(50);
    const row = rows.find((x) => x.action === 'edit_cry_threshold');
    expect(row, '«кто поднял порог» has no answer').toBeTruthy();
    expect(row!.target).toContain('0.6');
  });
});

describe('accuracy exists only where a mother said so', () => {
  it('with analyses and no verdicts, accuracy is null and the panel is told why', async () => {
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    await analyse(a, '2026-08-10T22:00:00.000Z', 'tired', 0.31);

    const d = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.analyses).toBe(2);
    expect(d.rated).toBe(0);
    // null, never 0. «нет данных» and «0 % правильных» are opposite claims.
    expect(d.accuracy).toBeNull();
    expect(d.unrated).toBe(2);
    expect(d.source).toBe('mother_verdicts');
    // The one sentence that stops the average confidence being read as accuracy.
    expect(d.sourceNote).toMatch(/мнение о себе/);
    // And the spec's «послушать запись» is answered honestly rather than drawn
    // as a button that cannot work.
    expect(d.audioNote).toMatch(/не хранятся/);
  });

  it('a verdict from the app turns up in the back office', async () => {
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    expect((await rate(a, AT, 'correct')).statusCode).toBe(200);

    const d = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.rated).toBe(1);
    expect(d.correct).toBe(1);
    expect(d.accuracy).toBe(1);
    expect(d.unrated).toBe(0);
    const hungry = d.byReason.find((r: { reason: string }) => r.reason === 'hungry');
    expect(hungry).toMatchObject({ count: 1, correct: 1, wrong: 0 });
  });

  it('accuracy is over rated rows only — unrated ones do not count against it', async () => {
    const a = app();
    await analyse(a, '2026-08-10T10:00:00.000Z', 'hungry', 0.9);
    await analyse(a, '2026-08-10T11:00:00.000Z', 'hungry', 0.9);
    await analyse(a, '2026-08-10T12:00:00.000Z', 'hungry', 0.9);
    await rate(a, '2026-08-10T10:00:00.000Z', 'correct');
    await rate(a, '2026-08-10T11:00:00.000Z', 'wrong', 'belly_pain');

    const d = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.analyses).toBe(3);
    expect(d.rated).toBe(2);
    expect(d.unrated).toBe(1);
    // 1 of 2 rated — NOT 1 of 3 analysed.
    expect(d.accuracy).toBe(0.5);
  });

  it('«ниже порога» is counted against the threshold actually in force', async () => {
    const a = app();
    await analyse(a, '2026-08-10T10:00:00.000Z', 'tired', 0.4); // under 0.45
    await analyse(a, '2026-08-10T11:00:00.000Z', 'tired', 0.6); // over it

    const before = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(before.byReason[0].belowThreshold).toBe(1);
    expect(before.minConfidence).toBe(CRY_MIN_CONFIDENCE_DEFAULT);

    await a.inject({ method: 'PUT', url: '/admin/cry/threshold', payload: { minConfidence: 0.7 } });
    const after = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    // Both are now suppressed on the phone, and the panel says so rather than
    // reporting the count against the number it used to be.
    expect(after.byReason[0].belowThreshold).toBe(2);
    expect(after.rule).toContain('70 %');
  });

  it('no per-mother row reaches the panel — aggregates only', async () => {
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    await analyse(a, '2026-08-10T22:00:00.000Z', 'tired', 0.31);
    const res = await a.inject({ method: 'GET', url: '/admin/cry' });
    const d = res.json();

    // Rule 5: health data is never listed per person in the back office. No id
    // of any user or child may appear anywhere in the response.
    expect(res.body).not.toContain(DEMO_USER);
    // The only array is the GROUP BY, one entry per reason, and every field on
    // it is a count or a mean. A list as long as the number of analyses would
    // be a feed of individual families' nights whatever it was called.
    const arrays = Object.entries(d).filter(([, v]) => Array.isArray(v));
    expect(arrays.map(([k]) => k)).toEqual(['byReason']);
    expect(d.byReason.length).toBeLessThan(d.analyses + 1);
    for (const r of d.byReason) {
      expect(Object.keys(r).sort()).toEqual(
        ['avgConfidence', 'belowThreshold', 'correct', 'count', 'reason', 'wrong'],
      );
    }
    // `firstAt` / `lastAt` are the window's edges over EVERY user — the same
    // category as «тревог сегодня», and what «собираем с …» is printed from.
    expect(d.firstAt).toBe(AT);
  });
});

describe('a verdict is about her own analysis, and it survives', () => {
  it('a verdict about an analysis that does not exist is 404, not silence', async () => {
    const a = app();
    expect((await rate(a, AT, 'correct')).statusCode).toBe(404);
  });

  it('another account cannot rate her analysis', async () => {
    const mine = app(DEMO_USER);
    await analyse(mine, AT, 'hungry', 0.82);
    // Any account that is not hers. NOT DEMO_USER — that IS her, and a test
    // that used it would prove the guard works by never crossing a boundary.
    const hers = app('22222222-2222-2222-2222-222222222222');
    expect((await rate(hers, AT, 'wrong', 'tired')).statusCode).toBe(404);

    // …and the analysis is still unrated, rather than rated by a stranger.
    const d = (await mine.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.rated).toBe(0);
  });

  it('re-pushing the history on sign-in does not erase the verdict', async () => {
    // The app pushes its whole cry history whenever it signs in. An upsert that
    // overwrote the row wholesale would delete the only ground truth this
    // product has, on every reinstall, with nothing failing anywhere.
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    await rate(a, AT, 'wrong', 'belly_pain');
    await analyse(a, AT, 'hungry', 0.82); // the re-push

    const d = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.rated).toBe(1);
    expect(d.byReason[0].wrong).toBe(1);
  });

  it('the verdict comes back with her history on a new device', async () => {
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    await rate(a, AT, 'wrong', 'belly_pain');
    const results = (await a.inject({ method: 'GET', url: '/cry/results' })).json().results;
    expect(results[0]).toMatchObject({ verdict: 'wrong', actualReason: 'belly_pain' });
  });

  it('«верно» carries no actual reason, whatever the client sends', async () => {
    // The stored reason IS the answer when it was right. Accepting a
    // contradicting `actualReason` beside it would produce rows that say two
    // different things about the same cry.
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    await rate(a, AT, 'correct', 'tired');
    const results = (await a.inject({ method: 'GET', url: '/cry/results' })).json().results;
    expect(results[0]).toMatchObject({ verdict: 'correct', actualReason: null });
  });

  it('an unknown verdict word is refused', async () => {
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    expect((await rate(a, AT, 'maybe')).statusCode).toBe(400);
  });

  it('the same instant written two ways is the same analysis', async () => {
    // The app sends `DateTime.toIso8601String()`; a curl by hand sends
    // '…21:14:00Z'. Two rows for one recording would double-count it and let
    // the verdict land on the wrong one.
    const a = app();
    await analyse(a, AT, 'hungry', 0.82);
    expect((await rate(a, '2026-08-10T21:14:00Z', 'correct')).statusCode).toBe(200);
    const d = (await a.inject({ method: 'GET', url: '/admin/cry' })).json();
    expect(d.analyses).toBe(1);
    expect(d.rated).toBe(1);
  });

  it('…and the other way round, which is the one a fake would hide', async () => {
    // Recorded WITHOUT milliseconds, rated with them. Postgres normalises both
    // to one timestamptz; the in-memory repository compares strings, so without
    // the same normalisation on the way IN this 404s in development and works
    // in production — the worst possible split.
    const a = app();
    await analyse(a, '2026-08-10T21:14:00Z', 'hungry', 0.82);
    expect((await rate(a, AT, 'correct')).statusCode).toBe(200);
    const results = (await a.inject({ method: 'GET', url: '/cry/results' })).json().results;
    expect(results).toHaveLength(1);
    expect(results[0].verdict).toBe('correct');
  });

  it('an analysis stamped with something that is not a time is refused', async () => {
    const a = app();
    expect((await analyse(a, 'yesterday evening', 'hungry', 0.82)).statusCode).toBe(400);
  });
});
