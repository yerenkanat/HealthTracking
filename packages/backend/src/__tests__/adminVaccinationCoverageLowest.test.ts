/**
 * Frame 15's «провал по охвату» — the worst-covered injection, over HTTP.
 *
 * The spec's line for this frame is «таблица нацкалендаря с охватом → провал по
 * пневмококку 76 % с объяснением». The table and the per-row column shipped;
 * the callout that names WHICH injection has fallen behind did not, so the one
 * number the frame exists to surface was left for a reader to find by eye
 * across sixteen rows.
 *
 * Everything below goes through the real routes against a real memory
 * repository and reads the answer back. Two properties matter more than the
 * arithmetic:
 *
 *   1. `lowest` is a SELECTION over the same `vaccines[]` array the table is
 *      drawn from, so the callout and the row can never disagree. Each test
 *      asserts both, against each other.
 *   2. an edit made through the editor moves it. The coverage figures are
 *      computed over contract-plus-overrides, so moving a vaccine's age through
 *      PUT /admin/vaccination/schedule changes who is in its denominator — and
 *      if the callout were computed off the shipped contract instead, this is
 *      the test that would catch it.
 *
 * NOTHING HERE IS A CLINICAL FIGURE. Every tick is a row somebody's mother
 * created by tapping a circle in the app; a low share means «не отметили», not
 * «не привили». The route says so in `sourceNote` and `lowestRule`, and the
 * last describe below pins those sentences.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEMO_CHILD, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

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
  expect(res.statusCode, 'the staff account could not sign in').toBe(200);
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

/**
 * The first day of the month `n` months ago.
 *
 * Anchored to the 1st on purpose. Both repositories count COMPLETED months and
 * require the day of the month to have come round, so a child born on the 31st
 * is a month younger than one born on the 1st for two days in most months — and
 * a fixture built by subtracting days would grade differently depending on the
 * date the suite runs, which is the stopwatch mistake in another costume.
 */
function dobMonthsAgo(n: number): string {
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - n, 1));
  return d.toISOString().slice(0, 10);
}

/** Every key whose age AND its one-month catch-up window have gone by at [age]. */
const PASSED_AT_6 = [
  'hepb/1', 'bcg/null',
  'pentavalent/1', 'opv/1', 'pcv/1',
  'pentavalent/2', 'opv/2',
  'pentavalent/3', 'opv/3', 'pcv/2',
];

/**
 * Four six-month-olds and two three-month-olds, with the ticks written through
 * the repository exactly as the app writes them.
 *
 * Denominators come out at 6 for the two injections given at birth (all six
 * children are past month 0 + 1) and at 4 for everything at months 2–4.
 */
/**
 * The demo cohort the memory repository seeds so the «Дети» dashboard has a
 * distribution in dev. Removed first: their birthdays are fixed dates from
 * 2017–2025, so every denominator below would drift by one more child on each
 * of their birthdays and this file would fail on a calendar day nobody chose.
 */
async function clearDemoCohort(): Promise<void> {
  for (const id of [DEMO_CHILD, 'demo-c2', 'demo-c3', 'demo-c4', 'demo-c5', 'demo-c6', 'demo-c7']) {
    await repo.deleteChild(id);
  }
}

async function seedChildren(): Promise<void> {
  await clearDemoCohort();
  const olds = ['a', 'b', 'c', 'd'];
  const babies = ['e', 'f'];
  for (const id of olds) {
    await repo.upsertChild(DEMO_USER, { id, name: id.toUpperCase(), dateOfBirth: dobMonthsAgo(6) });
  }
  for (const id of babies) {
    await repo.upsertChild(DEMO_USER, { id, name: id.toUpperCase(), dateOfBirth: dobMonthsAgo(3) });
  }
  // Everything the six-month-olds are past, ticked by all four...
  for (const id of olds) {
    for (const key of PASSED_AT_6) await repo.setVaccine(id, key, true);
  }
  // ...except the two the fixture is about.
  await repo.setVaccine('c', 'pcv/2', false);   // 2 of 4 → 50 %
  await repo.setVaccine('d', 'pcv/2', false);
  // BCG for everybody, including the babies: 6 of 6.
  for (const id of babies) await repo.setVaccine(id, 'bcg/null', true);
  // Hepatitis B: three of six → also 50 %, but over a bigger denominator.
  await repo.setVaccine('e', 'hepb/1', false);
  await repo.setVaccine('f', 'hepb/1', false);
  await repo.setVaccine('d', 'hepb/1', false);
}

const coverage = async () => {
  const res = await app.inject({ method: 'GET', url: '/admin/vaccination/coverage', headers: { cookie } });
  expect(res.statusCode, res.body).toBe(200);
  return res.json();
};

describe('GET /admin/vaccination/coverage names the injection that has fallen behind', () => {
  it('reports the lowest share, and the same numbers as its own table row', async () => {
    await seedChildren();
    const body = await coverage();

    expect(body.lowest, 'the callout has nothing to print').toBeTruthy();
    // A tie at 50 %: hepb/1 over six children, pcv/2 over four. The bigger
    // denominator wins — 50 % of two children is noise, 50 % of six is a
    // finding — and it has to be the SAME row the table draws.
    expect(body.lowest.key).toBe('hepb/1');
    expect(body.lowest.pct).toBe(50);
    expect(body.lowest.done).toBe(3);
    expect(body.lowest.due).toBe(6);

    const row = body.vaccines.find((v: { key: string }) => v.key === 'hepb/1');
    expect(body.lowest, 'the callout disagrees with the table').toEqual(row);
  });

  it('counts how many injections have a denominator at all', async () => {
    await seedChildren();
    const body = await coverage();
    // Ten of sixteen: nothing after month 4 has a six-month-old past its window.
    expect(body.measured).toBe(PASSED_AT_6.length);
    expect(body.vaccines.filter((v: { pct: number | null }) => v.pct != null))
      .toHaveLength(body.measured);
    expect(body.measured).toBeLessThan(body.vaccines.length);
  });

  it('picks the smaller percentage over the bigger denominator when they differ', async () => {
    await seedChildren();
    // One more tick on hepatitis B breaks the tie: 4 of 6 is 67 %, and the
    // worst is now the pneumococcal second dose.
    await repo.setVaccine('d', 'hepb/1', true);
    const body = await coverage();
    expect(body.lowest.key).toBe('pcv/2');
    expect(body.lowest.pct).toBe(50);
    expect(body.lowest.due).toBe(4);
  });

  it('is null, not zero, when no child has passed anything yet', async () => {
    // A newborn, and nothing else. Every injection is «предстоит» or «пора», so
    // there is no denominator anywhere — and «худший охват 0 %» would be a
    // claim about the product rather than a measurement of it.
    await clearDemoCohort();
    await repo.upsertChild(DEMO_USER, { id: 'newborn', name: 'Н', dateOfBirth: dobMonthsAgo(0) });
    const body = await coverage();
    expect(body.lowest).toBeNull();
    expect(body.measured).toBe(0);
    expect(body.lowestRule).toContain('«неизвестно», а не ноль');
  });

  it('leaves children with no date of birth out, and says how many', async () => {
    await seedChildren();
    await repo.upsertChild(DEMO_USER, { id: 'nodob', name: 'Без даты', dateOfBirth: null });
    const body = await coverage();
    expect(body.children).toBe(6);
    expect(body.childrenWithoutDob).toBe(1);
    // ...and the extra child changed no denominator.
    expect(body.lowest.due).toBe(6);
  });
});

describe('the callout follows the calendar as it is EDITED, not as it shipped', () => {
  it('moving a vaccine later takes its denominator away, through the real editor', async () => {
    await seedChildren();
    const before = await coverage();
    expect(before.vaccines.find((v: { key: string }) => v.key === 'hepb/1').due).toBe(6);

    // The editor's own route: hepatitis B moved from birth to two years. Every
    // child in the fixture is now younger than the new age, so nobody is past
    // its window and it drops out of the comparison entirely.
    const put = await app.inject({
      method: 'PUT',
      url: '/admin/vaccination/schedule/hepb/1',
      headers: { cookie },
      payload: {
        atMonth: 24,
        dose: 1,
        ru: { name: 'Гепатит B', note: 'Перенесено для проверки' },
        kk: { name: 'В гепатиті', note: 'Тексеру үшін ауыстырылды' },
        draft: true,
      },
    });
    expect(put.statusCode, put.body).toBe(200);

    const after = await coverage();
    // A DRAFT changes nothing a phone sees, so the denominator must not move.
    expect(after.lowest.key, 'a draft leaked into the served calendar').toBe('hepb/1');

    // Published, it moves.
    const publish = await app.inject({
      method: 'PUT',
      url: '/admin/vaccination/schedule/hepb/1',
      headers: { cookie },
      payload: {
        atMonth: 24,
        dose: 1,
        ru: { name: 'Гепатит B', note: 'Перенесено для проверки' },
        kk: { name: 'В гепатиті', note: 'Тексеру үшін ауыстырылды' },
        draft: false,
      },
    });
    // The bilingual rule is satisfied; the medical-review rule is not, and that
    // is the correct answer for a schedule change nobody has signed.
    expect(publish.statusCode, publish.body).toBe(409);
    expect(publish.json().error).toBe('review_required');

    const signed = await app.inject({
      method: 'POST', url: '/admin/vaccination/schedule/hepb/1/review', headers: { cookie },
    });
    expect(signed.statusCode, signed.body).toBe(200);

    const published = await app.inject({
      method: 'PUT',
      url: '/admin/vaccination/schedule/hepb/1',
      headers: { cookie },
      payload: {
        atMonth: 24,
        dose: 1,
        ru: { name: 'Гепатит B', note: 'Перенесено для проверки' },
        kk: { name: 'В гепатиті', note: 'Тексеру үшін ауыстырылды' },
        draft: false,
      },
    });
    expect(published.statusCode, published.body).toBe(200);

    const moved = await coverage();
    expect(moved.vaccines.find((v: { key: string }) => v.key === 'hepb/1').pct).toBeNull();
    expect(moved.measured).toBe(PASSED_AT_6.length - 1);
    expect(moved.lowest.key).toBe('pcv/2');
  });

  it('a wider catch-up window narrows the denominator, and the callout follows', async () => {
    await seedChildren();
    const before = await coverage();
    expect(before.lowest.due, 'the three-month-olds start out in the denominator').toBe(6);

    const wide = await app.inject({
      method: 'PUT', url: '/admin/vaccination/settings', headers: { cookie },
      payload: { dueWindowMonths: 3 },
    });
    expect(wide.statusCode, wide.body).toBe(200);

    const body = await coverage();
    // Three months of catch-up: the three-month-olds are still «пора» even on
    // the birth injections and leave every denominator, and nothing after month
    // 2 is measurable at all. The share moves because the population did — which
    // is exactly why the footer prints the window it was computed with.
    expect(body.dueWindowMonths).toBe(3);
    expect(body.measured).toBe(5);
    expect(body.lowest.key).toBe('hepb/1');
    expect(body.lowest.due).toBe(4);
    expect(body.lowest.pct).toBe(75);
    expect(body.lowestRule).toContain('среди 5 прививок');
  });
});

describe('what the sentence under the number is allowed to say', () => {
  it('attributes a low share to the tick, never to the injection', async () => {
    await seedChildren();
    const body = await coverage();
    expect(body.lowestRule).toContain('Низкая доля не означает, что прививку не сделали');
    expect(body.lowestRule).toContain('не отметили в приложении');
    expect(body.lowestRule).toContain('Данных поликлиник у этой панели нет');
    expect(body.source).toBe('self_reported');
  });

  it('says what the minimum was chosen out of', async () => {
    await seedChildren();
    const body = await coverage();
    expect(body.lowestRule)
      .toContain(`среди ${body.measured} прививок из ${body.vaccines.length}`);
  });

  it('never quotes the spec’s illustrative 76 %', async () => {
    await seedChildren();
    const body = JSON.stringify(await coverage());
    expect(body).not.toContain('76 %');
    expect(body).not.toContain('по РК');
  });
});
