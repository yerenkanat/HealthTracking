/**
 * Nothing goes live in one language.
 *
 * The app resolves a card with `byLocale[locale] ?? byLocale['ru']`, which is
 * the right fallback and a silent one. A mother who set the app to Kazakh gets
 * Russian guidance about her own pregnancy and nothing tells her the
 * translation is missing rather than that the app ignored her — and nobody in
 * the back office could see it either, because a half-translated card looked
 * exactly like a finished one.
 *
 * docs/CLAUDE-admin-design.md: «Двуязычность обязательна: без казахской версии
 * кнопка «Опубликовать» заблокирована.»
 *
 * Two levels here: the pure check, and the refusal over HTTP with a message a
 * content editor can act on without asking a developer.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { bilingualMessage, bilingualProblems, missingLocales } from '../content/bilingual';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

describe('what counts as translated', () => {
  it('needs Russian and Kazakh, and does not care about English', () => {
    expect(missingLocales({ ru: 'Урок', kk: 'Сабақ' })).toEqual([]);
    expect(missingLocales({ ru: 'Урок', kk: 'Сабақ', en: 'Lesson' })).toEqual([]);
    // Nothing is sold in English — the landing, the box and the support line
    // are Russian and Kazakh — so English is welcome and never required.
    expect(missingLocales({ ru: 'Урок', en: 'Lesson' })).toEqual(['kk']);
  });

  it('whitespace is not a translation', () => {
    // The failure this catches is a person tabbing through the Kazakh field to
    // get past the check. It saves, and it renders as a blank card.
    expect(missingLocales({ ru: 'Урок', kk: '   ' })).toEqual(['kk']);
    expect(missingLocales({ ru: 'Урок', kk: '' })).toEqual(['kk']);
    expect(missingLocales(undefined)).toEqual(['ru', 'kk']);
  });

  it('reports every field at once, not one per round trip', () => {
    const problems = bilingualProblems({ id: 'w20-breathing', title: { ru: 'Дыхание' }, summary: {} });
    expect(problems).toEqual([
      { id: 'w20-breathing', field: 'title', missing: ['kk'] },
      { id: 'w20-breathing', field: 'summary', missing: ['ru', 'kk'] },
    ]);
  });

  it('names the card, the field and the language, in Russian', () => {
    // A 400 saying "validation failed" sends a content editor to find a
    // developer. This one can be read and acted on.
    const msg = bilingualMessage(bilingualProblems({
      id: 'w20-breathing', title: { ru: 'Дыхание' }, summary: { ru: 'Про дыхание', kk: 'Тыныс' },
    }));
    expect(msg).toBe('«w20-breathing»: нет казахской версии заголовка');
  });
});

// ---------------------------------------------------------------------------

let app: FastifyInstance;

beforeEach(() => {
  app = buildServer(
    {
      repo: createMemoryRepository(),
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
});

const both = { title: { ru: 'Дыхание', kk: 'Тыныс алу' }, summary: { ru: 'Про дыхание', kk: 'Тыныс туралы' } };

describe('the timeline CMS refuses to publish half a translation', () => {
  it('accepts a card in both languages, and it is really there afterwards', async () => {
    const res = await app.inject({
      method: 'PUT', url: '/admin/content/w20',
      payload: { items: [{ id: 'w20-breathing', kind: 'lesson', ...both }] },
    });
    expect(res.statusCode, res.body).toBe(200);
    // Reading it back is what stops the "wrote nothing" assertions below from
    // passing vacuously on a mistyped key: `catalog.w20 ?? []` equals [] just
    // as happily when the response is shaped differently than I assumed.
    const catalog = (await app.inject({ method: 'GET', url: '/admin/content' })).json().stages;
    expect(catalog.w20.map((i: { id: string }) => i.id)).toEqual(['w20-breathing']);
  });

  it('refuses one that is Russian only, and says which card', async () => {
    const res = await app.inject({
      method: 'PUT', url: '/admin/content/w20',
      payload: { items: [{ id: 'w20-breathing', kind: 'lesson', title: { ru: 'Дыхание' }, summary: { ru: 'Про' } }] },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.error).toBe('translation_required');
    expect(body.stage).toBe('w20');
    expect(body.message).toContain('w20-breathing');
    expect(body.message).toContain('казахской');
  });

  it('writes nothing when one card in the batch is untranslated', async () => {
    // All-or-nothing matters here: saving the good one and refusing the bad one
    // leaves the editor looking at a screen that half took.
    await app.inject({
      method: 'PUT', url: '/admin/content/w20',
      payload: {
        items: [
          { id: 'ok', kind: 'lesson', ...both },
          { id: 'half', kind: 'lesson', title: { ru: 'Только по-русски' }, summary: { ru: '…' } },
        ],
      },
    });
    // The stage is not empty to begin with — it ships with demo content — so
    // the assertion is that NEITHER new card landed, not that the stage is
    // bare. `?? []` against an empty array would have passed either way.
    const { stages } = (await app.inject({ method: 'GET', url: '/admin/content' })).json();
    const ids = (stages.w20 ?? []).map((i: { id: string }) => i.id);
    expect(ids, 'the good half of a refused save was written').not.toContain('ok');
    expect(ids).not.toContain('half');
  });
});

describe('the bulk import names every untranslated card, not the first', () => {
  const stage = (id: string, translated: boolean) => ({
    id, kind: 'lesson' as const,
    ...(translated ? both : { title: { ru: 'Только по-русски' }, summary: { ru: '…' } }),
  });

  it('rejects the whole file and lists what to fix', async () => {
    const res = await app.inject({
      method: 'PUT', url: '/admin/content',
      payload: {
        stages: {
          w10: [stage('a', true)],
          w11: [stage('b', false)],
          w12: [stage('c', false)],
        },
      },
    });
    expect(res.statusCode).toBe(400);
    const body = res.json();
    expect(body.error).toBe('translation_required');
    // An import is a spreadsheet somebody spent a day on. Being told about one
    // missing translation per upload turns that day into a week.
    expect(body.problems.map((p: { id: string }) => p.id)).toContain('b');
    expect(body.problems.map((p: { id: string }) => p.id)).toContain('c');
    expect(body.problems.every((p: { stage: string }) => p.stage)).toBe(true);
    expect(body.message).toContain('ничего не записано');
  });

  it('and really writes nothing — including the stages that were fine', async () => {
    await app.inject({
      method: 'PUT', url: '/admin/content',
      payload: { stages: { w10: [stage('a', true)], w11: [stage('b', false)] } },
    });
    const catalog = (await app.inject({ method: 'GET', url: '/admin/content' })).json().stages;
    const idsIn = (k: string) => (catalog[k] ?? []).map((i: { id: string }) => i.id);
    expect(idsIn('w10'), 'the stage that was fine was written anyway').not.toContain('a');
    expect(idsIn('w11')).not.toContain('b');
  });

  it('takes the file once every card has both languages', async () => {
    const res = await app.inject({
      method: 'PUT', url: '/admin/content',
      payload: { stages: { w10: [stage('a', true)], w11: [stage('b', true)] } },
    });
    expect(res.statusCode, res.body).toBe(200);
  });
});

describe('a course lesson may be drafted in one language and not published in one', () => {
  const lesson = (over: Record<string, unknown> = {}) => ({
    titleRu: 'Первые дни дома',
    youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
    ...over,
  });
  const save = (payload: Record<string, unknown>) =>
    app.inject({ method: 'PUT', url: '/admin/course/lessons', payload: payload as never });

  it('saves a Russian-only draft — that is how anything gets written', async () => {
    const res = await save(lesson({ published: false }));
    expect(res.statusCode, res.body).toBe(200);
  });

  it('refuses to publish it without a Kazakh title', async () => {
    const res = await save(lesson({ published: true }));
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('translation_required');
    // The message has to say what to do instead, or the editor is stuck.
    expect(res.json().message).toContain('черновик');
  });

  it('publishes once the Kazakh title is there', async () => {
    const res = await save(lesson({ published: true, titleKk: 'Үйдегі алғашқы күндер' }));
    expect(res.statusCode, res.body).toBe(200);
  });

  it('a blank Kazakh title is not a Kazakh title', async () => {
    const res = await save(lesson({ published: true, titleKk: '   ' }));
    expect(res.statusCode).toBe(400);
  });
});
