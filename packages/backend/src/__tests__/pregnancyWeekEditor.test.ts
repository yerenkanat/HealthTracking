/**
 * Frames 14a «40 недель» / 14b «Редактор недели» — the calendar becomes editable.
 *
 * The week-by-week calendar is the only content this product shows to EVERY
 * pregnant user, and it shipped compiled into the server and bundled into the
 * app: a wrong hCG range in week 22 was a backend release and a store rollout.
 *
 * The whole feature is one claim, and these drive it over HTTP against a real
 * memory repository rather than asserting on functions:
 *
 *   editing week 22 in the back office changes what GET /pregnancy/weeks says,
 *   and nothing else moves — the shipped contract is untouched, every other
 *   week still reads exactly as it shipped, and a database that cannot be
 *   reached costs the edits and not the calendar.
 *
 * Plus the two rules that make it survivable: no Kazakh, no publication; and
 * medical text needs a second person.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import type { StaffRole } from '../auth/capabilities';
import { pregnancyCalendar } from '../pregnancy/weeks';
import { gestationalWeekOn, mergeWeeks, utcMidnightOf, weekAsReviewable } from '../pregnancy/overrides';
import { textFingerprint } from '../content/medicalReview';

let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

function appAs(role: StaffRole, r: Repository = repo): FastifyInstance {
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
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: `${role}-1`, role }),
    },
    { logger: false },
  );
}

const WEEK = 22;
const base = () => pregnancyCalendar.weeks.find((w) => w.week === WEEK)!;

const EDIT = {
  lengthCm: '27,8',
  hcg: '4 720 – 80 100',
  ru: {
    baby: 'Малыш слышит ваш голос и различает свет.',
    you: 'Возможна изжога — ешьте небольшими порциями.',
    recommend: 'Запишитесь на второй скрининг, если ещё не были.',
  },
  kk: {
    baby: 'Нәресте дауысыңызды естиді және жарықты ажыратады.',
    you: 'Қыжыл болуы мүмкін — аз-аздан жеңіз.',
    recommend: 'Екінші скринингке жазылыңыз.',
  },
};

/**
 * The database with the overrides table taken away — migration 036 not applied
 * on a freshly deployed panel, or an ordinary connection blip. Everything else
 * about the repository still works, which is the point: one table's failure
 * must not decide what the other forty-nine screens can do.
 */
const TABLE_GONE = 'relation "pregnancy_week_overrides" does not exist';
function withoutOverridesTable(base: Repository): Repository {
  return {
    ...base,
    pregnancyWeekOverrides: async () => { throw new Error(TABLE_GONE); },
  };
}

const put = (app: FastifyInstance, body: unknown, week = WEEK) =>
  app.inject({ method: 'PUT', url: `/admin/pregnancy/weeks/${week}`, payload: body as never });
const approve = (app: FastifyInstance, week = WEEK) =>
  app.inject({ method: 'POST', url: `/admin/pregnancy/weeks/${week}/review` });
const served = async (app: FastifyInstance) =>
  (await app.inject({ method: 'GET', url: '/pregnancy/weeks' })).json() as
    { version: number; weeks: Array<{ week: number; lengthCm: string; hcg: string; ru: { baby: string }; kk: { baby: string } }> };

/** The full ceremony: author saves, clinician signs, author publishes. */
async function publishEdit(week = WEEK, edit = EDIT) {
  await put(appAs('content'), { ...edit, draft: true }, week);
  await approve(appAs('clinician'), week);
  return put(appAs('content'), edit, week);
}

// ---------------------------------------------------------------------------

describe('editing a week reaches the app', () => {
  it('GET /pregnancy/weeks serves the shipped contract when nothing is edited', async () => {
    const app = appAs('admin');
    const cal = await served(app);
    expect(cal.version).toBe(pregnancyCalendar.version);
    expect(cal.weeks).toHaveLength(pregnancyCalendar.weeks.length);
    expect(cal.weeks.find((w) => w.week === WEEK)!.ru.baby).toBe(base().ru.baby);
  });

  it('a published edit to week 22 is what the app then receives', async () => {
    const res = await publishEdit();
    expect(res.statusCode).toBe(200);

    const cal = await served(appAs('admin'));
    const w = cal.weeks.find((x) => x.week === WEEK)!;
    expect(w.ru.baby).toBe(EDIT.ru.baby);
    expect(w.kk.baby).toBe(EDIT.kk.baby);
    expect(w.lengthCm).toBe('27,8');
    // ...and the single-week route agrees, because a screen that reads one week
    // and a screen that reads forty must not disagree about week 22.
    const one = await appAs('admin').inject({ method: 'GET', url: `/pregnancy/weeks/${WEEK}` });
    expect(one.json().ru.baby).toBe(EDIT.ru.baby);
  });

  it('changes nothing else: every other week still reads as it shipped', async () => {
    await publishEdit();
    const cal = await served(appAs('admin'));
    for (const shipped of pregnancyCalendar.weeks) {
      if (shipped.week === WEEK) continue;
      const now = cal.weeks.find((x) => x.week === shipped.week)!;
      expect(now.ru.baby, `week ${shipped.week}`).toBe(shipped.ru.baby);
      expect(now.kk.baby, `week ${shipped.week}`).toBe(shipped.kk.baby);
    }
  });

  it('leaves the shipped contract itself untouched in memory', async () => {
    // The app bundles this exact file and verify_pregnancy_weeks_contract.dart
    // asserts they are identical. A merge that mutated the loaded contract
    // would poison every later request in the process and break that check.
    const before = JSON.stringify(pregnancyCalendar);
    await publishEdit();
    await served(appAs('admin'));
    expect(JSON.stringify(pregnancyCalendar)).toBe(before);
  });

  it('bumps the version on every save, so a caching client notices', async () => {
    const v0 = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const v1 = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const v2 = (await served(appAs('admin'))).version;
    expect(v1).toBeGreaterThan(v0);
    expect(v2).toBeGreaterThan(v1);
  });

  it('a draft is stored but NOT served — the reader keeps the shipped text', async () => {
    const res = await put(appAs('content'), { ...EDIT, draft: true });
    expect(res.statusCode).toBe(200);
    expect(res.json().draft).toBe(true);

    const w = (await served(appAs('admin'))).weeks.find((x) => x.week === WEEK)!;
    expect(w.ru.baby).toBe(base().ru.baby);

    // ...and the editor still sees her own draft, or an afternoon's work is
    // retyped every time the tab is reopened.
    const admin = await appAs('content').inject({ method: 'GET', url: '/admin/pregnancy/weeks' });
    const row = admin.json().weeks.find((x: { week: number }) => x.week === WEEK);
    expect(row.ru.baby).toBe(EDIT.ru.baby);
    expect(row.draft).toBe(true);
    expect(row.live).toBe(false);
  });

  it('«вернуть базовый текст» is a draft, not a delete — the contract shows through again', async () => {
    await publishEdit();
    expect((await served(appAs('admin'))).weeks.find((w) => w.week === WEEK)!.ru.baby).toBe(EDIT.ru.baby);

    const v = (await served(appAs('admin'))).version;
    await put(appAs('content'), { ...EDIT, draft: true });
    const after = await served(appAs('admin'));
    expect(after.weeks.find((w) => w.week === WEEK)!.ru.baby).toBe(base().ru.baby);
    // The version still goes UP. A client that cached the edited week has to be
    // told the text moved back, and a version going backwards is the one thing
    // it cannot survive.
    expect(after.version).toBeGreaterThan(v);
  });

  it('keeps the contract\'s numbers when the edit leaves them blank', async () => {
    // Rewriting the prose is not a claim that the baby is no longer 27 cm long.
    await put(appAs('content'), { ...EDIT, lengthCm: null, hcg: null, draft: true });
    await approve(appAs('clinician'));
    await put(appAs('content'), { ...EDIT, lengthCm: null, hcg: null });
    const w = (await served(appAs('admin'))).weeks.find((x) => x.week === WEEK)!;
    expect(w.lengthCm).toBe(base().lengthCm);
    expect(w.hcg).toBe(base().hcg);
    expect(w.ru.baby).toBe(EDIT.ru.baby);
  });

  it('a week saved with the numeric boxes empty can still be published FROM THE PANEL', async () => {
    // The loop that made a week permanently unpublishable. The panel never
    // re-sends null: it reads GET /admin/pregnancy/weeks, which hands back the
    // MERGED number ('27,8', the contract's), puts it in the box and posts that
    // back. If the clinician's signature was taken over the raw stored null,
    // the two can never agree — publish is 409 «stale», re-approving recomputes
    // the same unreachable fingerprint, and it never ends.
    await put(appAs('content'), { ...EDIT, lengthCm: null, hcg: null, draft: true });
    expect((await approve(appAs('clinician'))).statusCode).toBe(200);

    // Read the week back exactly as the editor's screen does...
    const seen = (await appAs('content').inject({ method: 'GET', url: '/admin/pregnancy/weeks' }))
      .json().weeks.find((x: { week: number }) => x.week === WEEK);
    expect(seen.lengthCm).toBe(base().lengthCm); // what the box is filled with
    // ...and the card must not claim a signature it also treats as stale.
    expect(seen.review.by).toBe('clinician-1');
    expect(seen.reviewCurrent).toBe(true);

    // ...then press «Опубликовать» without typing, which posts the merged
    // numbers straight back.
    const res = await put(appAs('content'), {
      ...EDIT, lengthCm: seen.lengthCm, hcg: seen.hcg, draft: false,
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
    const live = (await served(appAs('admin'))).weeks.find((x) => x.week === WEEK)!;
    expect(live.ru.baby).toBe(EDIT.ru.baby);
    expect(live.lengthCm).toBe(base().lengthCm);
  });

  it('...and changing that number for real still takes the approval away', async () => {
    // The fallback must not turn into "the numbers stopped counting". It is the
    // contract's own value that is a no-op, not any value.
    await put(appAs('content'), { ...EDIT, lengthCm: null, hcg: null, draft: true });
    await approve(appAs('clinician'));
    const res = await put(appAs('content'), { ...EDIT, lengthCm: '99,9', hcg: base().hcg });
    expect(res.statusCode).toBe(409);
    expect(res.json().problems[0].reason).toBe('stale');
  });
});

describe('when the overrides table cannot be read', () => {
  // Frame 14a is a READ of forty weeks of medical content and it worked before
  // this table existed. One unreadable table must not blank it.
  it('the staff calendar still answers, from the contract, and says the edit state is unknown', async () => {
    const broken = withoutOverridesTable(repo);
    const res = await appAs('admin', broken).inject({ method: 'GET', url: '/admin/pregnancy/weeks' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.editsKnown).toBe(false);
    expect(body.weeks).toHaveLength(pregnancyCalendar.weeks.length);
    expect(body.weeks.find((w: { week: number }) => w.week === WEEK).ru.baby).toBe(base().ru.baby);
    // And the mothers' own calendar is unaffected, as it already was.
    const app = appAs('admin', broken);
    expect((await app.inject({ method: 'GET', url: '/pregnancy/weeks' })).statusCode).toBe(200);
  });

  it('says so honestly rather than reporting forty untouched weeks', async () => {
    // `editsKnown: true` here would be the lie: it would let the panel draw an
    // editor over a week whose draft and sign-off it cannot see.
    await publishEdit();
    const ok = (await appAs('admin').inject({ method: 'GET', url: '/admin/pregnancy/weeks' })).json();
    expect(ok.editsKnown).toBe(true);
    expect(ok.weeks.find((w: { week: number }) => w.week === WEEK).edited).toBe(true);
  });

  it('refuses the SAVE instead of quietly dropping the clinician\'s sign-off', async () => {
    // A draft is exempt from the review gate, so nothing else would stop this
    // write — and carryReview with no prior row stores `review: null`.
    await publishEdit();
    const signed = (await repo.pregnancyWeekOverrides()).find((o) => o.week === WEEK)!;
    expect(signed.review!.by).toBe('clinician-1');

    const res = await put(appAs('content', withoutOverridesTable(repo)), { ...EDIT, draft: true });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('overrides_unavailable');
    // Named in words an editor can act on, not a bare 503.
    expect(res.json().message).toContain('проверка врача');

    const after = (await repo.pregnancyWeekOverrides()).find((o) => o.week === WEEK)!;
    expect(after.review).toEqual(signed.review);
    expect(after.rev).toBe(signed.rev); // nothing was written at all
  });
});

describe('both languages, or it does not go live', () => {
  it('refuses a save with no Kazakh, naming the field', async () => {
    const res = await put(appAs('content'), {
      ...EDIT,
      kk: { baby: '', you: '', recommend: '' },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.error).toBe('translation_required');
    // Named, not "validation failed": a content editor must be able to act on
    // it without asking a developer what a 400 is.
    expect(body.message).toContain('казахской');
    expect(body.message).toContain('О малыше');
    expect(body.problems).toHaveLength(3); // baby, you, recommend
  });

  it('refuses a DRAFT with no Kazakh too', async () => {
    // A draft is exempt from the clinician rule and not from this one: a
    // translation that is never started is a translation that never happens.
    const res = await put(appAs('content'), {
      ...EDIT, draft: true, kk: { baby: 'бар', you: '', recommend: '' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
  });

  it('whitespace is not a translation', async () => {
    const res = await put(appAs('content'), {
      ...EDIT, kk: { baby: '   ', you: '  ', recommend: ' ' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
  });

  it('nothing was written when a save is refused', async () => {
    await put(appAs('content'), { ...EDIT, kk: { baby: '', you: '', recommend: '' } });
    expect(await repo.pregnancyWeekOverrides()).toEqual([]);
  });
});

describe('medical text needs a second person', () => {
  it('refuses to publish an unreviewed week with 409 review_required', async () => {
    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('review_required');
    expect(res.json().message).toContain('черновик');
  });

  it('the author cannot approve her own text — approving needs `health`', async () => {
    await put(appAs('content'), { ...EDIT, draft: true });
    // `content` is the authoring role and holds no `health`.
    expect((await approve(appAs('content'))).statusCode).toBe(403);
    // ...and a clinician, who holds `health` and no `content`, cannot author.
    expect((await put(appAs('clinician'), { ...EDIT, draft: true })).statusCode).toBe(403);
  });

  it('publishes once a clinician has signed the same text', async () => {
    await put(appAs('content'), { ...EDIT, draft: true });
    const signed = await approve(appAs('clinician'));
    expect(signed.statusCode).toBe(200);
    expect(signed.json().review.by).toBe('clinician-1');
    // Approving does NOT publish: two decisions, two people.
    expect(signed.json().draft).toBe(true);

    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
  });

  it('editing approved text takes the approval away', async () => {
    // Approve-then-rewrite is the obvious way round the rule and the one that
    // happens by accident — fixing a typo does not feel like republishing
    // medical advice.
    await publishEdit();
    const rewritten = { ...EDIT, ru: { ...EDIT.ru, recommend: 'Совсем другая рекомендация.' } };
    const res = await put(appAs('content'), rewritten);
    expect(res.statusCode).toBe(409);
    expect(res.json().problems[0].reason).toBe('stale');
  });

  it('editing the hCG range alone also takes the approval away', async () => {
    // The numbers are the other half of the advice. A reviewed page whose hCG
    // range moved afterwards is unreviewed advice under a reviewed headline.
    await publishEdit();
    const res = await put(appAs('content'), { ...EDIT, hcg: '1 – 999999' });
    expect(res.statusCode).toBe(409);
    expect(res.json().problems[0].reason).toBe('stale');
  });

  it('re-saving the identical text keeps the approval', async () => {
    // A rule that fires on every save is a rule everybody works around.
    await publishEdit();
    const res = await put(appAs('content'), EDIT);
    expect(res.statusCode).toBe(200);
    expect(res.json().reviewed).toBe(true);
  });

  it('a review cannot be self-granted through the request body', async () => {
    const forged = {
      ...EDIT,
      review: { by: 'content-1', at: '2026-01-01T00:00:00Z', fingerprint: textFingerprint(weekAsReviewable(WEEK, { ...EDIT, draft: false })) },
    };
    expect((await put(appAs('content'), forged)).statusCode).toBe(409);
  });

  it('there is nothing to review on a week nobody has edited', async () => {
    // The shipped contract came through its own release; asking a clinician to
    // re-approve forty untouched weeks would turn the queue into noise.
    const res = await approve(appAs('clinician'), 7);
    expect(res.statusCode).toBe(404);
    expect(res.json().error).toBe('not_edited');
  });
});

describe('the journal', () => {
  it('records the edit and the sign-off as separate, named actions', async () => {
    await publishEdit();
    const log = await repo.listAudit(50);
    const actions = log.map((e) => e.action);
    expect(actions).toContain('edit_pregnancy_week_draft');
    expect(actions).toContain('pregnancy_week_review');
    expect(actions).toContain('edit_pregnancy_week');
    const signed = log.find((e) => e.action === 'pregnancy_week_review')!;
    expect(signed.staffId).toBe('clinician-1');
    expect(signed.target).toBe('week-22');
  });
});

describe('the week the editor is standing on', () => {
  it('refuses a week the calendar does not cover, rather than storing a row nothing merges', async () => {
    const res = await put(appAs('content'), EDIT, 55);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('unknown_week');
    expect(await repo.pregnancyWeekOverrides()).toEqual([]);
  });

  it('counts mothers off due dates only, and says zero when it is zero', async () => {
    // «312 мам» is exactly the number this screen must never invent.
    const empty = await appAs('admin').inject({ method: 'GET', url: '/admin/pregnancy/weeks' });
    expect(empty.json().mothersKnown).toBe(true);
    expect(empty.json().mothersTotal).toBe(0);
    expect(empty.json().weeks.every((w: { mothers: number }) => w.mothers === 0)).toBe(true);

    // Give the demo profile a due date twenty weeks out → week 20.
    //
    // Counted from TODAY'S local calendar date at UTC midnight, which is what
    // the repository compares against. `Date.now() + 140 days` is a timestamp,
    // and west of UTC its ISO date is a day out — the test then asserts week 21
    // and looks like a bug in the arithmetic rather than in itself.
    const due = new Date(utcMidnightOf(new Date()) + 20 * 7 * 86_400_000)
      .toISOString().slice(0, 10);
    await repo.upsertProfile(DEMO_USER, {
      displayName: 'Aigerim', dueDate: due, locale: 'ru-KZ',
      birthDate: null, city: null, doctorPhone: null,
      avgCycleLength: null, avgPeriodLength: null,
    });

    const now = await appAs('admin').inject({ method: 'GET', url: '/admin/pregnancy/weeks' });
    expect(now.json().mothersTotal).toBe(1);
    const hit = now.json().weeks.filter((w: { mothers: number }) => w.mothers > 0);
    expect(hit).toHaveLength(1);
    expect(hit[0].week).toBe(20);
  });
});

// ---- The merge itself, and the arithmetic behind the head-count ----------

describe('mergeWeeks', () => {
  const contract = { version: 3, weeks: [
    { week: 1, lengthCm: '0,1', hcg: '5', ru: { baby: 'a', you: 'b', recommend: 'c' }, kk: { baby: 'ä', you: 'b̆', recommend: 'ç' } },
    { week: 2, lengthCm: '0,2', hcg: '50', ru: { baby: 'd', you: 'e', recommend: 'f' }, kk: { baby: 'd̆', you: 'ĕ', recommend: 'f̆' } },
  ] };
  const row = {
    week: 1, lengthCm: null, hcg: null,
    ru: { baby: 'NEW', you: 'b', recommend: 'c' },
    kk: { baby: 'ЖАҢА', you: 'b̆', recommend: 'ç' },
    draft: false, review: null, rev: 2, updatedAt: '2026-08-10T00:00:00Z', updatedBy: 's1',
  };

  it('never drops a week the contract covers', () => {
    expect(mergeWeeks(contract, []).weeks.map((w) => w.week)).toEqual([1, 2]);
    expect(mergeWeeks(contract, [row]).weeks.map((w) => w.week)).toEqual([1, 2]);
  });

  it('an override for a week the contract does not have is ignored, not appended', () => {
    // The app clamps into the contract's range and the panel draws chips from
    // it; a week 99 in the middle of the list would be a chip nothing opens.
    const stray = { ...row, week: 99 };
    expect(mergeWeeks(contract, [stray]).weeks.map((w) => w.week)).toEqual([1, 2]);
  });

  it('a draft leaves the contract text in place but still moves the version', () => {
    const drafted = mergeWeeks(contract, [{ ...row, draft: true }]);
    expect(drafted.weeks[0].ru.baby).toBe('a');
    expect(drafted.version).toBe(3 + 2);
  });
});

describe('gestationalWeekOn', () => {
  const today = Date.UTC(2026, 7, 10);
  it('counts whole days on both sides', () => {
    // A due date exactly ten weeks out is week 30 — not 29 and a bit, floored.
    expect(gestationalWeekOn('2026-10-19', today)).toBe(30);
  });
  it('clamps into the calendar', () => {
    expect(gestationalWeekOn('2027-05-20', today)).toBe(1);
    expect(gestationalWeekOn('2026-08-10', today)).toBe(40);
  });
  it('does not count a due date that has passed', () => {
    // She is overdue, not in week 40; folding her in would inflate the number
    // the editor is asked to trust.
    expect(gestationalWeekOn('2026-08-09', today)).toBeNull();
  });
});
