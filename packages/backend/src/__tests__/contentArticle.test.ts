/**
 * Admin frame 16a — «Новая статья»: a guide that has TEXT.
 *
 * A published guide was a heading, a one-line summary and an external `url`.
 * Tapping one threw a woman into a browser; with the url empty it rendered as
 * «Скоро» and did nothing. There was no way to write an article and no way to
 * read one. These tests drive the whole chain that changed: the panel's PUT,
 * the two publication gates, and the app's own `GET /content`.
 *
 * Four failures are being nailed down, and each of them is silent:
 *
 *   1. z.object STRIPS unlisted keys. A field the schema does not name is not
 *      "not supported" — it is ERASED, by every subsequent save, from text
 *      somebody spent an hour writing.
 *   2. Text outside the review fingerprint is an approved headline sitting over
 *      unreviewed medical advice.
 *   3. …and the mirror image: the fingerprint must not CHANGE for the 364 items
 *      that carry no article, or every approved card in the database goes
 *      `stale` on deploy and comes off the app at once.
 *   4. A half-translated article is the silent Russian fallback, one paragraph
 *      at a time instead of one line.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import type { StaffRole } from '../auth/capabilities';
import { textFingerprint } from '../content/medicalReview';

const DEMO_USER = 'u-article';

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

const BODY_RU = 'Первый абзац про кровотечение.\n\nВторой абзац: что делать до приезда.';
const BODY_KK = 'Қан кету туралы бірінші абзац.\n\nЕкінші абзац: не істеу керек.';

const ARTICLE = {
  id: 'w23-bleeding',
  kind: 'lesson' as const,
  title: { ru: 'Кровотечение', kk: 'Қан кету' },
  summary: { ru: 'Когда звонить врачу', kk: 'Дәрігерге қашан қоңырау шалу' },
  body: { ru: BODY_RU, kk: BODY_KK },
  redFlags: {
    ru: 'Кровь заливает прокладку за час — звоните 103.',
    kk: 'Бір сағатта прокладка толып кетсе — 103-ке қоңырау шалыңыз.',
  },
};

/** The shape the whole published catalogue is in: no article at all. */
const HEADLINE_ONLY = {
  id: 'w23-nursery',
  kind: 'lesson' as const,
  title: { ru: 'Комната малыша', kk: 'Бөбек бөлмесі' },
  summary: { ru: 'Что подготовить', kk: 'Нені дайындау' },
};

const save = (app: FastifyInstance, items: unknown[]) =>
  app.inject({ method: 'PUT', url: '/admin/content/w23', payload: { items } as never });
const review = (app: FastifyInstance, id: string) =>
  app.inject({ method: 'POST', url: `/admin/content/w23/${id}/review` });
const stored = async () => (await repo.contentCatalog()).w23 ?? [];

beforeEach(() => { repo = createMemoryRepository(); });

describe('an article survives the round trip', () => {
  it('is stored, and comes back to the panel as it was written', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [ARTICLE]);
    expect(res.statusCode, res.body).toBe(200);

    const rows = await stored();
    expect(rows.length).toBe(1);
    expect(rows[0].body).toEqual(ARTICLE.body);
    expect(rows[0].redFlags).toEqual(ARTICLE.redFlags);
    await editor.close();
  });

  it('a SECOND save of what the panel read back does not erase it', async () => {
    // The defect this exists for: z.object strips what it does not name, so an
    // unlisted field is not merely unsupported — it is deleted by the next
    // save of the same card, from whichever screen. The panel re-sends exactly
    // what GET handed it, so that is what this re-sends.
    const editor = makeApp('content');
    await save(editor, [ARTICLE]);

    const panelSees = await editor.inject({ method: 'GET', url: '/admin/content' });
    const asRead = panelSees.json().stages.w23;
    expect(asRead[0].body.ru).toBe(BODY_RU);

    expect((await save(editor, asRead)).statusCode).toBe(200);
    expect((await stored())[0].body).toEqual(ARTICLE.body);
    await editor.close();
  });

  it('reaches the phone, with the staff signature stripped', async () => {
    const editor = makeApp('content');
    await save(editor, [ARTICLE]);

    const app = makeApp('content');
    const res = await app.inject({ method: 'GET', url: '/content' });
    expect(res.statusCode, res.body).toBe(200);
    const item = res.json().stages.w23[0];
    expect(item.body.ru).toBe(BODY_RU);
    expect(item.body.kk).toBe(BODY_KK);
    expect(item.redFlags.kk).toContain('103');
    expect(item.review).toBeUndefined();
    await editor.close();
    await app.close();
  });

  it('a draft article never reaches the phone', async () => {
    const editor = makeApp('content');
    await save(editor, [{ ...ARTICLE, draft: true }]);
    const app = makeApp('content');
    const res = await app.inject({ method: 'GET', url: '/content' });
    expect(res.json().stages.w23 ?? []).toEqual([]);
    await editor.close();
    await app.close();
  });

  it('newlines are preserved — they are the paragraph breaks', async () => {
    const editor = makeApp('content');
    await save(editor, [ARTICLE]);
    const app = makeApp('content');
    const item = (await app.inject({ method: 'GET', url: '/content' })).json().stages.w23[0];
    expect(item.body.ru.split('\n').filter((s: string) => s.trim()).length).toBe(2);
    await editor.close();
    await app.close();
  });
});

describe('publication is blocked without the Kazakh version', () => {
  it('names the ARTICLE, not just "the card"', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [{ ...ARTICLE, body: { ru: BODY_RU } }]);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
    expect(res.json().problems).toEqual([
      { id: ARTICLE.id, field: 'body', missing: ['kk'] },
    ]);
    expect(res.json().message).toContain('текста статьи');
    expect(res.json().message).toContain('казахской');
    expect(await stored(), 'nothing may be written on a refused save').toEqual([]);
    await editor.close();
  });

  it('and the red-flag block by its own name', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [{ ...ARTICLE, redFlags: { ru: 'Кровь.' } }]);
    expect(res.statusCode).toBe(400);
    expect(res.json().problems).toEqual([
      { id: ARTICLE.id, field: 'redFlags', missing: ['kk'] },
    ]);
    expect(res.json().message).toContain('Красный флаг');
    await editor.close();
  });

  it('reports the article AND the headline together, not one per round trip', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [
      { ...ARTICLE, summary: { ru: 'Только по-русски' }, body: { ru: BODY_RU } },
    ]);
    expect(res.json().problems.map((p: { field: string }) => p.field)).toEqual(['summary', 'body']);
    await editor.close();
  });

  it('an item with NO article at all still publishes', async () => {
    // The whole published catalogue is this shape. Treating an unwritten
    // article as a missing translation would refuse every save of every
    // existing stage — the bilingual rule would read as "the CMS is broken",
    // and the way round a broken CMS is to stop using the new field.
    const editor = makeApp('content');
    expect((await save(editor, [HEADLINE_ONLY])).statusCode).toBe(200);
    expect((await stored()).length).toBe(1);
    await editor.close();
  });

  it('an article in Kazakh only is refused too — the rule is both ways', async () => {
    const editor = makeApp('content');
    const res = await save(editor, [{ ...ARTICLE, body: { kk: BODY_KK } }]);
    expect(res.statusCode).toBe(400);
    expect(res.json().problems).toEqual([
      { id: ARTICLE.id, field: 'body', missing: ['ru'] },
    ]);
    await editor.close();
  });
});

describe('a doctor signs off the ARTICLE, not the headline', () => {
  const MEDICAL = { ...ARTICLE, medical: true };

  async function approved(item: Record<string, unknown> = MEDICAL) {
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...item, draft: true }]);
    const signed = await review(doctor, String(item.id));
    expect(signed.statusCode, signed.body).toBe(200);
    expect((await save(editor, [item])).statusCode, 'approved text must publish').toBe(200);
    return { editor, doctor };
  }

  it('editing the body takes the approval away', async () => {
    // Approve-then-rewrite, in prose. The headline still says «Кровотечение»
    // and the paragraphs underneath it now say something nobody has read.
    const { editor, doctor } = await approved();
    const res = await save(editor, [
      { ...MEDICAL, body: { ...MEDICAL.body, ru: 'Совершенно другой совет.' } },
    ]);
    expect(res.statusCode).toBe(409);
    expect(res.json().error).toBe('review_required');
    expect(res.json().problems).toEqual([{ id: MEDICAL.id, reason: 'stale' }]);
    await editor.close();
    await doctor.close();
  });

  it('editing the red-flag block takes it away too', async () => {
    const { editor, doctor } = await approved();
    const res = await save(editor, [
      { ...MEDICAL, redFlags: { ...MEDICAL.redFlags, ru: 'Ничего страшного, подождите утра.' } },
    ]);
    expect(res.statusCode).toBe(409);
    expect(res.json().problems).toEqual([{ id: MEDICAL.id, reason: 'stale' }]);
    await editor.close();
    await doctor.close();
  });

  it('ADDING an article to an approved headline takes it away', async () => {
    // The nastiest ordering: the card was approved when it was a headline and
    // a link. Text appearing under it afterwards has been read by nobody.
    const bare = { ...HEADLINE_ONLY, medical: true };
    const { editor, doctor } = await approved(bare);
    const res = await save(editor, [{ ...bare, body: { ru: BODY_RU, kk: BODY_KK } }]);
    expect(res.statusCode).toBe(409);
    expect(res.json().problems).toEqual([{ id: bare.id, reason: 'stale' }]);
    await editor.close();
    await doctor.close();
  });

  it('re-saving the same article keeps the approval', async () => {
    const { editor, doctor } = await approved();
    expect((await save(editor, [MEDICAL])).statusCode).toBe(200);
    expect((await stored())[0].review?.by).toBe('clinician-1');
    await editor.close();
    await doctor.close();
  });
});

describe('the fingerprint of a card with no article is unchanged', () => {
  // Not a nicety. Every approved item in the live database carries a
  // fingerprint computed before articles existed; if this shape moved, all of
  // them would read `stale` on the deploy that shipped this and come off the
  // app at once, waiting on a clinician to re-read text nobody had touched.
  const base = {
    id: 'c', title: { ru: 'Т', kk: 'Т' }, summary: { ru: 'С', kk: 'С' },
    url: 'https://x/y',
  };

  it('matches what the old four-part fingerprint produced', async () => {
    const dict = (d: Record<string, string>) =>
      Object.keys(d).sort().map((k) => `${k}=${d[k]}`).join('');
    const legacy = [dict(base.title), dict(base.summary), base.url, ''].join('');
    expect(textFingerprint(base)).toBe(legacy);
  });

  it('an empty article is the same as no article', async () => {
    // A textarea typed into and cleared leaves `{}` or `{ru: ''}` behind. That
    // is not an edit, and treating it as one would revoke a real signature.
    expect(textFingerprint({ ...base, body: {} })).toBe(textFingerprint(base));
    expect(textFingerprint({ ...base, body: { ru: '   ' } })).toBe(textFingerprint(base));
    expect(textFingerprint({ ...base, redFlags: {} })).toBe(textFingerprint(base));
  });

  it('but a written article changes it', async () => {
    expect(textFingerprint({ ...base, body: { ru: 'a' } })).not.toBe(textFingerprint(base));
    expect(textFingerprint({ ...base, redFlags: { ru: 'a' } })).not.toBe(textFingerprint(base));
    // …and the two are not interchangeable: moving the red flags into the body
    // is a real edit, and an unlabelled concatenation would call it identical.
    expect(textFingerprint({ ...base, body: { ru: 'a' } }))
      .not.toBe(textFingerprint({ ...base, redFlags: { ru: 'a' } }));
  });

  it('the language order it was saved in does not matter', async () => {
    const a = textFingerprint({ ...base, body: { ru: 'x', kk: 'y' } });
    const b = textFingerprint({ ...base, body: { kk: 'y', ru: 'x' } });
    expect(a).toBe(b);
  });
});

describe('the article the panel sends back carries its own signature', () => {
  it('a re-save of an approved article is not refused by the field cap', async () => {
    // The fingerprint now quotes the whole article, and the panel round-trips
    // the stored review with every save. A cap sized for the old fingerprint
    // would 400 every attempt to re-save a long approved guide — with a zod
    // error naming `review.fingerprint`, which tells an editor nothing.
    const long = 'Абзац. '.repeat(900);
    const item = {
      ...ARTICLE, medical: true,
      body: { ru: long, kk: long },
    };
    const editor = makeApp('content');
    const doctor = makeApp('clinician');
    await save(editor, [{ ...item, draft: true }]);
    await review(doctor, item.id);

    const asRead = (await editor.inject({ method: 'GET', url: '/admin/content' }))
      .json().stages.w23;
    expect(asRead[0].review.fingerprint.length).toBeGreaterThan(12000);
    const res = await save(editor, asRead);
    expect(res.statusCode, res.body).toBe(200);
    await editor.close();
    await doctor.close();
  });
});
