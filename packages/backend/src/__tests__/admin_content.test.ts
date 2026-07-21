/**
 * Back-office: content CMS, drilldowns, fleet, safety feed, analytics.
 *
 * Editing the catalogue changes what EVERY user sees — including what is
 * offered for sale — so the write path is admin-only and audited, and a stage
 * key the app cannot resolve is refused rather than stored somewhere nothing
 * will ever read.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import type { InjectPayload, Response as InjectResponse } from 'light-my-request';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

type StaffRole = 'admin' | 'clinician' | 'support';

function makeApp(role: StaffRole | null) {
  const repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => (role ? { staffId: 's1', role } : null),
    },
    { logger: false },
  );
}

let app: FastifyInstance;
const get = (url: string): Promise<InjectResponse> => app.inject({ method: 'GET', url });
const put = (url: string, payload: InjectPayload): Promise<InjectResponse> =>
  app.inject({ method: 'PUT', url, payload });

const lesson = {
  id: 'w20-breathing',
  kind: 'lesson',
  title: { ru: 'Дыхание', kk: 'Тыныс алу', en: 'Breathing' },
  summary: { ru: 'Короткий урок.', kk: 'Қысқа сабақ.', en: 'A short lesson.' },
  url: 'https://example.com/v',
  durationMin: 6,
};
const product = {
  id: 'w20-pillow',
  kind: 'product',
  title: { ru: 'Подушка', kk: 'Жастық', en: 'Pillow' },
  summary: { ru: 'Для сна на боку.', kk: 'Бүйірде ұйықтауға.', en: 'For side sleeping.' },
  priceMinor: 1290000,
  currency: 'KZT',
};

describe('reading the catalogue', () => {
  beforeEach(async () => {
    app = makeApp('support');
    await app.ready();
  });

  it('any staff can read it', async () => {
    const r = await get('/admin/content');
    expect(r.statusCode).toBe(200);
    expect(r.json().stages).toBeTruthy();
  });

  it('reports coverage across the whole timeline', async () => {
    // 101 stages exist whether or not anything is published in them — the
    // first thing an author needs to know is what is still empty.
    const c = (await get('/admin/content')).json().coverage;
    expect(c.total).toBe(101);
    expect(c.filled.length + c.empty.length).toBe(101);
    expect(c.filled).toContain('w20');
  });

  it('support staff cannot EDIT the catalogue', async () => {
    // Reading is one thing; changing what every user is shown, and sold, is not.
    expect((await put('/admin/content/w20', { items: [lesson] })).statusCode).toBe(403);
  });
});

describe('editing the catalogue', () => {
  beforeEach(async () => {
    app = makeApp('admin');
    await app.ready();
  });

  it('an admin can publish a stage', async () => {
    const r = await put('/admin/content/w20', { items: [lesson, product] });
    expect(r.statusCode).toBe(200);
    expect(r.json().items).toBe(2);
    const stages = (await get('/admin/content')).json().stages;
    expect(stages.w20).toHaveLength(2);
    expect(stages.w20[1].priceMinor).toBe(1290000);
  });

  it('the edit is written to the audit log', async () => {
    await put('/admin/content/w20', { items: [lesson] });
    const audit = (await get('/admin/audit')).json().audit;
    expect(audit.some((a: { action: string; target: string }) =>
      a.action === 'edit_content' && a.target === 'w20')).toBe(true);
  });

  it('emptying a stage removes it rather than leaving a hollow entry', async () => {
    await put('/admin/content/w20', { items: [] });
    const body = (await get('/admin/content')).json();
    expect(body.stages.w20).toBeUndefined();
    expect(body.coverage.empty).toContain('w20');
  });

  it('refuses a stage the app could never show', async () => {
    // Pregnancy stops at week 40 and childhood at month 60. Content filed
    // outside that is unreachable, so it is rejected on the way in.
    for (const bad of ['w0', 'w41', 'm61', 'm-1', 'x9', 'week20']) {
      expect((await put(`/admin/content/${bad}`, { items: [lesson] })).statusCode).toBe(400);
    }
  });

  it('accepts both ends of the real range', async () => {
    for (const good of ['w1', 'w40', 'm0', 'm60']) {
      expect((await put(`/admin/content/${good}`, { items: [lesson] })).statusCode).toBe(200);
    }
  });

  it('refuses two items sharing an id', async () => {
    // Duplicates would render as indistinguishable cards and merge in analytics.
    const r = await put('/admin/content/w21', { items: [lesson, { ...product, id: lesson.id }] });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toContain('duplicate');
  });

  it('refuses a malformed item', async () => {
    expect((await put('/admin/content/w22', { items: [{ id: 'x' }] })).statusCode).toBe(400);
    expect((await put('/admin/content/w22', { items: [{ ...lesson, kind: 'coupon' }] })).statusCode).toBe(400);
    // Price must be a positive integer in minor units.
    expect((await put('/admin/content/w22', { items: [{ ...product, priceMinor: 12.5 }] })).statusCode).toBe(400);
    expect((await put('/admin/content/w22', { items: [{ ...product, priceMinor: -1 }] })).statusCode).toBe(400);
  });

  it('nobody signed in cannot edit', async () => {
    app = makeApp(null);
    await app.ready();
    expect((await put('/admin/content/w20', { items: [lesson] })).statusCode).toBe(401);
  });
});

describe('drilldowns and fleet', () => {
  beforeEach(async () => {
    app = makeApp('clinician');
    await app.ready();
  });

  it('a user detail assembles the whole family', async () => {
    const r = await get(`/admin/users/${DEMO_USER}/detail`);
    expect(r.statusCode).toBe(200);
    const d = r.json();
    expect(d.displayName).toBeTruthy();
    expect(Array.isArray(d.children)).toBe(true);
    expect(Array.isArray(d.devices)).toBe(true);
    expect(d).toHaveProperty('sleepNights');
  });

  it('viewing a user is audited as PHI access', async () => {
    await get(`/admin/users/${DEMO_USER}/detail`);
    app = makeApp('admin');
    await app.ready();
    // A fresh app has its own repo, so just assert the route records for its own.
    const own = makeApp('admin');
    await own.ready();
    await own.inject({ method: 'GET', url: `/admin/users/${DEMO_USER}/detail` });
    const audit = (await own.inject({ method: 'GET', url: '/admin/audit' })).json().audit;
    expect(audit.some((a: { action: string }) => a.action === 'view_user_detail')).toBe(true);
  });

  it('an unknown user is a 404, not an empty shell', async () => {
    expect((await get('/admin/users/00000000-0000-0000-0000-000000000000/detail')).statusCode).toBe(404);
  });

  it('the fleet and safety feed answer', async () => {
    expect((await get('/admin/devices')).statusCode).toBe(200);
    expect((await get('/admin/safety')).statusCode).toBe(200);
  });

  it('analytics reports content reach alongside users', async () => {
    const a = (await get('/admin/analytics')).json();
    expect(a).toHaveProperty('totalUsers');
    expect(a).toHaveProperty('contentStages');
    expect(a).toHaveProperty('contentLinked');
  });

  it('none of it is readable without staff credentials', async () => {
    app = makeApp(null);
    await app.ready();
    for (const path of ['/admin/devices', '/admin/safety', '/admin/analytics', `/admin/users/${DEMO_USER}/detail`]) {
      expect((await get(path)).statusCode).toBe(401);
    }
  });
});

describe('one item serving several stages', () => {
  beforeEach(async () => {
    app = makeApp('admin');
    await app.ready();
  });

  const shared = {
    ...lesson,
    id: 'trimester2-nutrition',
    alsoStages: ['w15', 'w16', 'w17'],
  };

  it('accepts and returns the shared stages', async () => {
    expect((await put('/admin/content/w14', { items: [shared] })).statusCode).toBe(200);
    const stages = (await get('/admin/content')).json().stages;
    expect(stages.w14[0].alsoStages).toEqual(['w15', 'w16', 'w17']);
  });

  it('stores the item exactly once', async () => {
    // The entire point: one copy, so editing it changes every appearance. If
    // the server expanded it into each stage on write, the CMS would be back to
    // fourteen copies with fourteen places to edit.
    await put('/admin/content/w14', { items: [shared] });
    const stages = (await get('/admin/content')).json().stages;
    expect(stages.w15).toBeUndefined();
    const copies = Object.values(stages as Record<string, Array<{ id: string }>>)
      .flat()
      .filter((i) => i.id === 'trimester2-nutrition');
    expect(copies).toHaveLength(1);
  });

  it('counts a stage covered only by a shared item as covered', async () => {
    // Reporting w15 as empty would send someone to author content that is
    // already there — the duplication this feature exists to stop.
    await put('/admin/content/w14', { items: [shared] });
    const cov = (await get('/admin/content')).json().coverage;
    expect(cov.empty).not.toContain('w15');
    expect(cov.filled).toContain('w15');
    expect(cov.sharedOnly).toEqual(['w15', 'w16', 'w17']);
  });

  it('counts the item once, not once per stage it appears in', async () => {
    // Relative to whatever the repository already seeds: a lesson shared
    // across four weeks must add ONE to the catalogue size, not four, or the
    // count stops meaning "things that exist".
    const before = (await get('/admin/content')).json().coverage;
    await put('/admin/content/w14', { items: [shared] });
    const after = (await get('/admin/content')).json().coverage;
    expect(after.items - before.items).toBe(1);
    expect(after.linked - before.linked).toBe(1);
  });

  it('a stage with its own content is not listed as shared-only', async () => {
    await put('/admin/content/w14', { items: [shared] });
    await put('/admin/content/w15', { items: [product] });
    const cov = (await get('/admin/content')).json().coverage;
    expect(cov.sharedOnly).not.toContain('w15');
    expect(cov.filled).toContain('w15');
  });

  it('refuses a stage key the app cannot resolve', async () => {
    // A typo here would silently attach the item to nothing, and the author
    // would see it published with no way to tell it never appears.
    const r = await put('/admin/content/w14', {
      items: [{ ...shared, alsoStages: ['w15', 'nonsense'] }],
    });
    expect(r.statusCode).toBe(400);
  });

  it('an item with no shared stages still round-trips', async () => {
    await put('/admin/content/w20', { items: [lesson] });
    const stages = (await get('/admin/content')).json().stages;
    expect(stages.w20[0].alsoStages).toBeUndefined();
    expect((await get('/admin/content')).json().coverage.sharedOnly).toEqual([]);
  });
});
