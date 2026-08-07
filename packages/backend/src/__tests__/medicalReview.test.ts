/**
 * «Медицинский текст — только после проверки врачом.»
 *
 * The catalogue this back office edits tells a pregnant woman what her
 * twenty-third week means, when a movement count is worth worrying about, and
 * which vaccinations are due. It was editable by anybody with the CMS open and
 * went live the moment it was saved, so reviewed guidance and a half-remembered
 * paragraph looked identical to the person reading them.
 *
 * The rule that actually holds is the second one: editing approved text takes
 * the approval away. Rule one — "get a signature" — is trivially defeated by
 * approve-then-rewrite, and that is the version that would happen by accident,
 * because fixing a typo in an approved card does not feel like republishing
 * medical advice.
 *
 * Who may approve is the capability model doing the work: authoring needs
 * `content`, approving needs `health`, and no role but an owner holds both.
 * That is what makes this two people rather than a checkbox.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import type { StaffRole } from '../auth/capabilities';
import { carryReview, textFingerprint, unreviewed } from '../content/medicalReview';

describe('what a signature is over', () => {
  const base = {
    id: 'w23-bleeding',
    medical: true,
    title: { ru: 'Кровотечение', kk: 'Қан кету' },
    summary: { ru: 'Когда звонить врачу', kk: 'Дәрігерге қашан қоңырау шалу керек' },
  };

  it('does not change when the same card is saved again', () => {
    // Re-saving an untouched card must not revoke a real review; a rule that
    // fires on every save is a rule everybody learns to work around.
    expect(textFingerprint(base)).toBe(textFingerprint({ ...base }));
  });

  it('does not change when the languages arrive in a different order', () => {
    const reordered = {
      ...base,
      title: { kk: 'Қан кету', ru: 'Кровотечение' },
    };
    expect(textFingerprint(reordered)).toBe(textFingerprint(base));
  });

  it('changes when any of the words do', () => {
    for (const edit of [
      { title: { ru: 'Кровотечение (обновлено)', kk: 'Қан кету' } },
      { summary: { ru: 'Другой текст', kk: 'Дәрігерге қашан қоңырау шалу керек' } },
    ]) {
      expect(textFingerprint({ ...base, ...edit })).not.toBe(textFingerprint(base));
    }
  });

  it('changes when the video is swapped', () => {
    // The headline stays approved-looking while twenty unreviewed minutes play
    // underneath it. This is the swap the fingerprint exists for.
    const withVideo = { ...base, video: { provider: 'youtube', url: 'https://youtu.be/aaaaaaaaaaa' } };
    const swapped = { ...base, video: { provider: 'youtube', url: 'https://youtu.be/bbbbbbbbbbb' } };
    expect(textFingerprint(swapped)).not.toBe(textFingerprint(withVideo));
  });

  it('a card that is not medical carries no signature at all', () => {
    // Otherwise an unmarked card could bank an approval and spend it the day
    // somebody ticks the medical box.
    const review = { by: 's1', at: '2026-08-07T00:00:00.000Z', fingerprint: 'x' };
    const carried = carryReview({ ...base, medical: false, review }, { ...base, review });
    expect(carried.review).toBeUndefined();
  });

  it('a client cannot supply its own — that would be self-approval by JSON', () => {
    const forged = { by: 'me', at: '2026-08-07T00:00:00.000Z', fingerprint: textFingerprint(base) };
    // No previous stored item, so nothing to carry: the forged one is dropped.
    expect(carryReview({ ...base, review: forged }, undefined).review).toBeUndefined();
  });
});

describe('what needs a review', () => {
  const card = (over: Record<string, unknown> = {}) => ({
    id: 'c', title: { ru: 'Т', kk: 'Т' }, summary: { ru: 'С', kk: 'С' }, ...over,
  });

  it('a draft never does — that is how one gets written', () => {
    expect(unreviewed([card({ medical: true, draft: true })], new Map())).toEqual([]);
  });

  it('a card that is not medical never does', () => {
    expect(unreviewed([card()], new Map())).toEqual([]);
  });

  it('reports a first publication as "never" and an edit as "stale"', () => {
    const item = card({ medical: true });
    expect(unreviewed([item], new Map())).toEqual([{ id: 'c', reason: 'never' }]);

    const approved = { ...item, review: { by: 's9', at: 'x', fingerprint: textFingerprint(item) } };
    const prior = new Map([['c', approved]]);
    expect(unreviewed([item], prior), 'an unchanged approved card').toEqual([]);

    const edited = card({ medical: true, summary: { ru: 'Переписано', kk: 'Қайта жазылған' } });
    expect(unreviewed([edited], prior)).toEqual([{ id: 'c', reason: 'stale' }]);
  });
});

// ---------------------------------------------------------------------------

let repo: Repository;

function makeApp(role: StaffRole): FastifyInstance {
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
      authAdmin: async () => ({ staffId: `${role}-1`, role }),
    },
    { logger: false },
  );
}

const MEDICAL = {
  id: 'w23-bleeding', kind: 'lesson' as const, medical: true,
  title: { ru: 'Кровотечение', kk: 'Қан кету' },
  summary: { ru: 'Когда звонить врачу', kk: 'Дәрігерге қашан қоңырау шалу' },
};

const save = (app: FastifyInstance, items: unknown[]) =>
  app.inject({ method: 'PUT', url: '/admin/content/w23', payload: { items } as never });
const review = (app: FastifyInstance, id = MEDICAL.id) =>
  app.inject({ method: 'POST', url: `/admin/content/w23/${id}/review` });
const stored = async () => (await repo.contentCatalog()).w23 ?? [];

beforeEach(() => { repo = createMemoryRepository(); });

describe('publishing medical guidance takes two people', () => {
  it('the author is refused, and told what to do instead', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [MEDICAL]);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('review_required');
    expect(res.json().problems).toEqual([{ id: MEDICAL.id, reason: 'never' }]);
    expect(res.json().message).toContain('черновик');
    expect(await stored()).toEqual([]);
    await editor.close();
  });

  it('the author can save it as a draft while it is being written', async () => {
    const editor = makeApp('content');
    expect((await save(editor, [{ ...MEDICAL, draft: true }])).statusCode).toBe(200);
    expect((await stored()).length).toBe(1);
    await editor.close();
  });

  it('the author cannot approve their own card', async () => {
    // The whole mechanism: authoring is `content`, approving is `health`.
    const editor = makeApp('content');
    await save(editor, [{ ...MEDICAL, draft: true }]);
    const res = await review(editor);
    expect(res.statusCode).toBe(403);
    expect(res.json().need).toBe('health');
    await editor.close();
  });

  it('a clinician approves it, and then it publishes', async () => {
    const editor = makeApp('content');
    const doctor = makeApp('clinician');

    await save(editor, [{ ...MEDICAL, draft: true }]);
    const signed = await review(doctor);
    expect(signed.statusCode, signed.body).toBe(200);
    expect(signed.json().review.by).toBe('clinician-1');

    const published = await save(editor, [MEDICAL]);
    expect(published.statusCode, published.body).toBe(200);
    await editor.close();
    await doctor.close();
  });

  it('records who took responsibility, as its own action', async () => {
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, draft: true }]);
    await review(doctor);

    const audit = await repo.listAudit(20);
    const row = audit.find((a) => a.action === 'content_review');
    expect(row, 'a sign-off left no trace').toBeDefined();
    expect(row!.staffId).toBe('clinician-1');
    expect(row!.target).toBe(`w23/${MEDICAL.id}`);
    await editor.close();
    await doctor.close();
  });

  it('refuses to sign off a card nobody marked medical', async () => {
    // A signature on a card no rule gates on means nothing, and the person
    // giving it should know rather than believe they have done something.
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, medical: false }]);
    const res = await review(doctor);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('not_medical');
    await editor.close();
    await doctor.close();
  });
});

describe('approve-then-rewrite does not work', () => {
  async function approved() {
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, draft: true }]);
    await review(doctor);
    await save(editor, [MEDICAL]);
    return { editor, doctor };
  }

  it('editing the text of an approved card revokes the approval', async () => {
    const { editor, doctor } = await approved();
    const rewritten = { ...MEDICAL, summary: { ru: 'Совсем другой совет', kk: 'Мүлдем басқа кеңес' } };

    const res = await save(editor, [rewritten]);
    expect(res.statusCode).toBe(409);
    expect(res.json().problems).toEqual([{ id: MEDICAL.id, reason: 'stale' }]);
    expect(res.json().message).toContain('изменён после проверки');
    // The old, approved text is still what is published — the rewrite did not
    // land at all.
    expect((await stored())[0].summary.ru).toBe('Когда звонить врачу');
    await editor.close();
    await doctor.close();
  });

  it('re-saving the SAME text keeps the approval', async () => {
    // The counterpart. A rule that revokes on every save is a rule that gets
    // routed around, and the routing-around is what publishes bad advice.
    const { editor, doctor } = await approved();
    expect((await save(editor, [MEDICAL])).statusCode).toBe(200);
    expect((await stored())[0].review?.by).toBe('clinician-1');
    await editor.close();
    await doctor.close();
  });

  it('a rewrite can be re-approved and then publishes', async () => {
    const { editor, doctor } = await approved();
    const rewritten = { ...MEDICAL, summary: { ru: 'Совсем другой совет', kk: 'Мүлдем басқа кеңес' } };
    await save(editor, [{ ...rewritten, draft: true }]);
    expect((await review(doctor)).statusCode).toBe(200);
    expect((await save(editor, [rewritten])).statusCode).toBe(200);
    await editor.close();
    await doctor.close();
  });

  it('a forged review in the request body changes nothing', async () => {
    const editor = makeApp('content');
    const rewritten = {
      ...MEDICAL,
      review: { by: 'somebody', at: '2026-08-07T00:00:00.000Z', fingerprint: textFingerprint(MEDICAL) },
    };
    expect((await save(editor, [rewritten])).statusCode).toBe(409);
    await editor.close();
  });
});

describe('the bulk import is not a way round it', () => {
  it('a hundred unreviewed medical cards at once are refused', async () => {
    const editor = makeApp('content');
    const res = await editor.inject({
      method: 'PUT', url: '/admin/content',
      payload: { stages: { w10: [{ ...MEDICAL, id: 'a' }], w11: [{ ...MEDICAL, id: 'b' }] } } as never,
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('review_required');
    expect(res.json().problems.map((p: { id: string }) => p.id).sort()).toEqual(['a', 'b']);
    expect(res.json().message).toContain('ничего не записано');
    await editor.close();
  });

  it('non-medical cards import as before', async () => {
    const editor = makeApp('content');
    const res = await editor.inject({
      method: 'PUT', url: '/admin/content',
      payload: { stages: { w10: [{ ...MEDICAL, id: 'a', medical: false }] } } as never,
    });
    expect(res.statusCode, res.body).toBe(200);
    await editor.close();
  });
});

describe('the review queue is how a clinician finds the work', () => {
  it('lists what is waiting, and why', async () => {
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, draft: true }]);

    const { waiting } = (await doctor.inject({ method: 'GET', url: '/admin/content/review-queue' })).json();
    expect(waiting).toEqual([{
      stage: 'w23', id: MEDICAL.id, title: 'Кровотечение', reason: 'never', draft: true,
    }]);
    await editor.close();
    await doctor.close();
  });

  it('puts a LIVE card whose text has moved at the top', async () => {
    // The dangerous kind: it is published, and nobody has checked what it now
    // says. A queue that buries it under new drafts hides the worse problem.
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, draft: true }]);
    await review(doctor);
    await save(editor, [MEDICAL]);
    // A stale card can only be created behind the route's back — the save path
    // refuses it. This is the state a hand-edited row or an older build leaves.
    const rows = await stored();
    await repo.putStageContent('w23', [
      { ...rows[0], summary: { ru: 'Изменено', kk: 'Өзгертілді' } },
      { ...MEDICAL, id: 'w23-new', draft: true },
    ]);

    const { waiting } = (await doctor.inject({ method: 'GET', url: '/admin/content/review-queue' })).json();
    expect(waiting.map((w: { reason: string }) => w.reason)).toEqual(['stale', 'never']);
    await editor.close();
    await doctor.close();
  });

  it('is not open to whoever wrote the content', async () => {
    const editor = makeApp('content');
    const res = await editor.inject({ method: 'GET', url: '/admin/content/review-queue' });
    expect(res.statusCode).toBe(403);
    await editor.close();
  });
});

describe('nothing unreviewed or unfinished reaches a phone', () => {
  it('a draft is not in the app feed', async () => {
    const editor = makeApp('content');
    await save(editor, [{ ...MEDICAL, draft: true }, { ...MEDICAL, id: 'w23-ready', medical: false }]);

    const { stages } = (await editor.inject({ method: 'GET', url: '/content' })).json();
    expect(stages.w23.map((i: { id: string }) => i.id)).toEqual(['w23-ready']);
    await editor.close();
  });

  it("and the reviewer's name is not either", async () => {
    // It is a back-office record of who took responsibility, not a byline, and
    // it is a staff member's id.
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...MEDICAL, draft: true }]);
    await review(doctor);
    await save(editor, [MEDICAL]);

    const { stages } = (await editor.inject({ method: 'GET', url: '/content' })).json();
    expect(stages.w23[0].id).toBe(MEDICAL.id);
    expect(stages.w23[0].review).toBeUndefined();
    // …while the back office still has it.
    expect((await stored())[0].review?.by).toBe('clinician-1');
    await editor.close();
    await doctor.close();
  });
});
