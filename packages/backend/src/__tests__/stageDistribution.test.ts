/**
 * Which stages the users are actually standing in.
 *
 * `stageDistribution` was declared on AdminAnalytics, documented as "stage key
 * → how many accounts sit there right now", and hardcoded to `{}` in BOTH
 * repositories. Nothing ever had a value, so nothing could draw it — and the
 * panel's "47 of 101 stages have content" never said WHICH 47. The authoring
 * backlog was ordered by guesswork: a beautifully covered week 8 is worth
 * nothing if everybody is at month 3.
 *
 * The arithmetic here is the part that has to be right. A stage key is the
 * CMS's own (`w1`..`w40`, `m0`..`m60`), so an off-by-one puts a real mother's
 * week against somebody else's content.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createMemoryRepository } from '../db/memoryRepository';
import { computeBiMetrics } from '../analytics/biMetrics.js';
import { buildSyntheticPopulation } from '../analytics/syntheticPopulation.js';
import type { Repository } from '../db/repository';
import { panelSettle } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/// The Аналитика tab draws six sections before it reaches the content card, and
/// they run in one function — a section that throws on a malformed payload
/// takes every later one with it, including the one under test. So /admin/bi
/// gets a real answer rather than {}.
const NOW = new Date('2026-08-06T10:00:00.000Z');
const BI = computeBiMetrics({ ...buildSyntheticPopulation(NOW), now: NOW });

let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

/// Built from LOCAL calendar parts, not toISOString.
///
/// A stage is a calendar fact — "seventy days from today" — and the repository
/// compares calendar days. toISOString converts to UTC first, so run anywhere
/// east of Greenwich shortly after midnight it hands back yesterday's date, and
/// every one of these fixtures is silently a day short. That is a whole
/// pregnancy week when it lands on a boundary, and it would have read as an
/// arithmetic bug in code that was right.
const ymd = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const daysFromNow = (n: number) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return ymd(d);
};
const monthsAgo = (n: number) => {
  const d = new Date();
  d.setMonth(d.getMonth() - n);
  return ymd(d);
};

const blankProfile = {
  displayName: 'Айгерім', phone: '+77001112233', dueDate: null, locale: 'ru',
  birthDate: null, city: null, address: null, doctorPhone: null,
  avgCycleLength: null, avgPeriodLength: null,
};

const dist = async () => (await repo.adminAnalytics()).stageDistribution;

/// The in-memory repository ships a seeded demo family, so these assert the
/// DELTA a change makes rather than the whole object — an absolute expectation
/// here would be pinning the fixture, not the arithmetic.
let base: Record<string, number>;
beforeEach(async () => { base = await dist(); });
const at = (d: Record<string, number>, k: string) => (d[k] ?? 0) - (base[k] ?? 0);

describe('where the users are', () => {
  it('is no longer permanently empty', async () => {
    // The whole defect: this answered {} whatever the data was, in both
    // repositories, for as long as the field has existed.
    await repo.upsertProfile('u1', { ...blankProfile, dueDate: daysFromNow(70) });
    expect(Object.keys(await dist()).length).toBeGreaterThan(0);
  });

  it('puts a pregnancy in the week she is in', async () => {
    // Ten weeks to go out of forty is week 30. Asserted absolutely, not as a
    // delta: the memory repository holds ONE profile, so overwriting it leaves
    // exactly one pregnancy in the whole distribution.
    await repo.upsertProfile('u1', { ...blankProfile, dueDate: daysFromNow(70) });
    const d = await dist();
    expect(Object.keys(d).filter((k) => k.startsWith('w'))).toEqual(['w30']);
    expect(d.w30).toBe(1);
  });

  it('caps a very early pregnancy at week 1 rather than week 0', async () => {
    // There is no w0 in the CMS, so a due date further out than forty weeks
    // must land on the first real stage instead of a key nothing can serve.
    await repo.upsertProfile('u1', { ...blankProfile, dueDate: daysFromNow(400) });
    expect(at(await dist(), 'w1')).toBe(1);
  });

  it('does not count a due date that has passed', async () => {
    // Not week 41 — a birth nobody recorded. Counting it would pile every
    // stale account onto w40 and send somebody off to write for a week that
    // has nobody in it.
    await repo.upsertProfile('u1', { ...blankProfile, dueDate: daysFromNow(-30) });
    const d = await dist();
    expect(Object.keys(d).filter((k) => k.startsWith('w'))).toEqual([]);
    expect(at(d, 'w40')).toBe(0);
  });

  it('puts a child in the month it is in', async () => {
    await repo.upsertChild('u1', { id: 'c1', name: 'Сұлтан', dateOfBirth: monthsAgo(3) });
    expect(at(await dist(), 'm3')).toBe(1);
  });

  it('a newborn is m0, which is a real stage', async () => {
    await repo.upsertChild('u1', { id: 'c1', name: 'Аружан', dateOfBirth: daysFromNow(-3) });
    expect(at(await dist(), 'm0')).toBe(1);
  });

  it('caps an older child at the last stage there is', async () => {
    // Past five years the CMS stops. Better the last real stage than a key
    // with nothing behind it.
    await repo.upsertChild('u1', { id: 'c1', name: 'Асыл', dateOfBirth: monthsAgo(96) });
    expect(at(await dist(), 'm60')).toBe(1);
  });

  it('counts a mother expecting her second in BOTH stages', async () => {
    // The same overlap the pregnant/mothers counts already state outright: she
    // reads her week and her toddler's month, and forcing her into one would
    // misstate whichever number somebody happens to read.
    await repo.upsertProfile('u1', { ...blankProfile, dueDate: daysFromNow(70) });
    await repo.upsertChild('u1', { id: 'c1', name: 'Сұлтан', dateOfBirth: monthsAgo(20) });

    const d = await dist();
    expect(d.w30).toBe(1);
    expect(at(d, 'm20')).toBe(1);
  });

  it('ignores a child with no birthday', async () => {
    // Stage is derived from the date; without one there is no stage, and
    // guessing would be inventing a user where there is none.
    await repo.upsertChild('u1', { id: 'nodob', name: 'Без даты' });
    expect(await dist()).toEqual(base);
  });

  it('says which stages have content, not only how many', async () => {
    // The panel reads this instead of the CMS catalogue, which lives in a
    // script block it cannot see.
    await repo.putStageContent('m33', [
      { id: 'i1', title: 'Прикорм', kind: 'article', url: 'https://example.kz/a' },
    ] as never);
    const a = await repo.adminAnalytics();
    expect(a.contentStageKeys).toContain('m33');
    expect(a.contentStageKeys.length).toBe(a.contentStages);
  });
});

/// And what the back office does with it.
describe('the content-coverage card', () => {
  const ANALYTICS = {
    totalUsers: 261, pregnant: 120, withChildren: 140, devices: 161,
    alerts7d: 3, sosAllTime: 7,
    // Two stages full of people; only one of them has anything to read.
    stageDistribution: { m3: 42, w30: 17, m0: 5 },
    contentStageKeys: ['w30'],
    contentStages: 1, contentItems: 364, contentLinked: 300,
  };

  async function render(analytics: unknown): Promise<{ text: string; errors: string[] }> {
    const html = readFileSync(PANEL, 'utf8');
    const errors: string[] = [];
    const vc = new VirtualConsole();
    vc.on('jsdomError', (e: Error) => errors.push(e.message));

    const settle = panelSettle();
  const dom = new JSDOM(html, {
      runScripts: 'dangerously', pretendToBeVisual: true,
      url: 'http://localhost/admin', virtualConsole: vc,
      beforeParse(window) {
        window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
          const noop = () => {};
          return new Proxy(
            { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
            { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
          );
        }) as never;
        Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
        window.scrollTo = () => {};
        settle.attach(window as never, async (path: string) => {
          const p = String(path);
          // The panel opens on a sign-in gate and asks who is signed in before
          // it renders anything; answering {} leaves it on the gate for ever.
          if (p.includes('/admin/me')) {
            return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
          }
          if (p.includes('/admin/bi')) {
            return { ok: true, status: 200, json: async () => BI };
          }
          const body = p.includes('/admin/analytics') ? analytics : {};
          return { ok: true, status: 200, json: async () => body };
        });
      },
    });

    const { window } = dom;
    await settle.quiet('boot');
    window.document.querySelector('[data-view="analytics"]')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the Аналитика tab');

    return {
      text: (window.document.querySelector('#anContent')?.textContent ?? '').replace(/\s+/g, ' ').trim(),
      errors,
    };
  }

  it('leads with the stages that have users and nothing to read', async () => {
    const page = await render(ANALYTICS);
    expect(page.errors).toEqual([]);
    expect(page.text).toMatch(/Есть пользователи, нет материала/i);
    // The biggest gap first: 42 people at three months and nothing for them.
    expect(page.text).toContain('3 мес.');
    expect(page.text).toContain('42');
  });

  it('does not list a stage that is already covered as a gap', async () => {
    const page = await render(ANALYTICS);
    // w30 has content, so it is not in the queue — and it is the SECOND
    // biggest, which is exactly how a naive "top stages" list would show it.
    const gapSection = page.text.split('Есть пользователи, нет материала')[1] ?? '';
    expect(gapSection).not.toContain('30-я неделя');
  });

  it('says so plainly when every occupied stage is covered', async () => {
    const page = await render({
      ...ANALYTICS, contentStageKeys: ['m3', 'w30', 'm0'],
    });
    expect(page.text).toMatch(/материал уже подготовлен/i);
  });

  it('draws the rest of the card when there is no distribution at all', async () => {
    // An older backend answers without the field. The coverage line above it
    // is the older, more important half and must survive.
    const page = await render({ ...ANALYTICS, stageDistribution: undefined });
    expect(page.errors).toEqual([]);
    expect(page.text).toContain('364');
  });
});
