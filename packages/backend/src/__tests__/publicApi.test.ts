/**
 * The public content API (/api/v1): reference calendars + protocols, and the
 * PERSONALISED timelines a consumer (e.g. a WhatsApp bot) schedules against.
 * Covers the pure date math, the API-key gate, input validation, and the
 * personalised endpoints.
 */
import { describe, it, expect } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { firstWeek, lastWeek } from '../pregnancy/weeks';
import { pregnancyWeekOn, childWeekOn, parseDate, pregnancyTimeline } from '../api/personalize';

function app(contentApiKey?: string): FastifyInstance {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => null,
      contentApiKey,
    },
    { logger: false },
  );
}

const d = (s: string) => parseDate(s)!;

describe('personalisation math', () => {
  it('reads gestational week from a due date (EDD = LMP + 280d)', () => {
    // 137 days before a 2026-12-09 due date → 280−137 = 143 → floor(143/7) = week 20.
    expect(pregnancyWeekOn(d('2026-12-09'), d('2026-07-25'))).toBe(20);
    // On the due date itself → 40 weeks (clamped into the covered range).
    expect(pregnancyWeekOn(d('2026-12-09'), d('2026-12-09'))).toBe(Math.min(40, lastWeek));
  });

  it('clamps a week before/after the calendar into range', () => {
    // Long before conception → clamps up to the first covered week.
    expect(pregnancyWeekOn(d('2026-12-09'), d('2025-12-09'))).toBe(firstWeek);
  });

  it('advances the week by one for every 7 days elapsed', () => {
    const w0 = pregnancyWeekOn(d('2026-12-09'), d('2026-07-25'));
    const w1 = pregnancyWeekOn(d('2026-12-09'), d('2026-08-01')); // +7 days
    expect(w1).toBe(w0 + 1);
  });

  it('reads child age in weeks from a birth date', () => {
    expect(childWeekOn(d('2026-06-01'), d('2026-06-29'))).toBe(4); // 28 days → 4 weeks
  });

  it('builds a dated timeline whose current entry contains the "from" date', () => {
    const { currentWeek, timeline } = pregnancyTimeline(d('2026-12-09'), d('2026-07-25'), 6);
    expect(currentWeek).toBe(20);
    expect(timeline).toHaveLength(6);
    expect(timeline[0].week).toBe(20);
    // "from" falls on/after the current week's start and before the next week's.
    expect(timeline[0].weekStart <= '2026-07-25').toBe(true);
    expect(timeline[1].weekStart > '2026-07-25').toBe(true);
    expect(timeline[0].content).not.toBeNull();
  });
});

describe('GET /api/v1 (index + gate)', () => {
  it('serves a self-describing index when open', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.authRequired).toBe(false);
    expect(j.coverage.pregnancyWeeks.last).toBe(lastWeek);
    expect(Object.keys(j.endpoints).length).toBeGreaterThan(6);
    await a.close();
  });

  it('reflects live daily-audio coverage in the index, per track', async () => {
    const repo = createMemoryRepository();
    await repo.upsertDailyAudio({ track: 'pregnancy', day: 140, locale: 'ru', title: 'x', mime: 'audio/mpeg', bytes: Buffer.from([1, 2, 3]) });
    await repo.upsertDailyAudio({ track: 'child', day: 30, locale: 'kk', title: 'y', mime: 'audio/mpeg', bytes: Buffer.from([4, 5]) });
    const a = buildServer(
      { repo, guardrail: { callLLM: async () => 'ok' }, ingest: { cacheLocation: async () => {}, resolveTransition: async () => null, sendEmergencyPush: async () => {}, sendGeofencePush: async () => {} }, cacheLastLocation: async () => null, setBpCalibration: async () => {}, authUser: async () => null, authAdmin: async () => null },
      { logger: false },
    );
    const j = (await a.inject({ method: 'GET', url: '/api/v1' })).json();
    expect(j.coverage.audio).toEqual({ pregnancy: 1, child: 1 });
    await a.close();
  });

  it('serves the shop catalogue (goods) with price and colours, plus one-by-id', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1/shop/products' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.currency).toBe('KZT');
    const watch = j.products.find((p: { id: string }) => p.id === 'watch');
    expect(watch.priceTenge).toBe(24900); // matches the landing page (migration 018)
    expect(Array.isArray(watch.colours)).toBe(true);
    expect((await a.inject({ url: '/api/v1/shop/products/tracker' })).statusCode).toBe(200);
    expect((await a.inject({ url: '/api/v1/shop/products/nope' })).statusCode).toBe(404);

    // The комплект is in the catalogue as a bundle: 39 000, no colours of its
    // own, and made of the two devices whose colours the buyer picks.
    const combo = j.products.find((p: { id: string }) => p.id === 'combo');
    expect(combo.priceTenge).toBe(39000);
    expect(combo.kind).toBe('bundle');
    expect(combo.parts.map((p: { partId: string }) => p.partId).sort()).toEqual(['tracker', 'watch']);
    // A set holds no stock of its own; unsold parts, not an empty colour list,
    // are what makes it unavailable.
    expect(combo.inStock, 'nothing is stocked in a fresh store').toBe(false);

    // and the index reflects the product count
    expect((await a.inject({ url: '/api/v1' })).json().coverage.shopProducts).toBe(3);
    await a.close();
  });

  it('rejects a missing/wrong key when one is configured, accepts the right one', async () => {
    const a = app('secret-key');
    expect((await a.inject({ method: 'GET', url: '/api/v1/pregnancy/weeks' })).statusCode).toBe(401);
    expect((await a.inject({ method: 'GET', url: '/api/v1/pregnancy/weeks', headers: { 'x-api-key': 'nope' } })).statusCode).toBe(401);
    expect((await a.inject({ method: 'GET', url: '/api/v1/pregnancy/weeks', headers: { 'x-api-key': 'secret-key' } })).statusCode).toBe(200);
    await a.close();
  });
});

describe('content + personalised endpoints', () => {
  it('serves the full pregnancy calendar and one week', async () => {
    const a = app();
    const all = await a.inject({ method: 'GET', url: '/api/v1/pregnancy/weeks' });
    expect(all.statusCode).toBe(200);
    expect(all.json().weeks.length).toBeGreaterThan(0);
    const one = await a.inject({ method: 'GET', url: '/api/v1/pregnancy/weeks/20' });
    expect(one.statusCode).toBe(200);
    expect(one.json().week.week).toBe(20);
    expect(one.json().week.ru).toBeTruthy();
    await a.close();
  });

  it('serves a personalised pregnancy timeline', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1/pregnancy/timeline?dueDate=2026-12-09&from=2026-07-25&weeks=4' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.currentWeek).toBe(20);
    expect(j.timeline).toHaveLength(4);
    expect(j.timeline[0]).toMatchObject({ week: 20 });
    expect(j.timeline[0].weekStart).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(j.timeline[0].content.ru).toBeTruthy();
    await a.close();
  });

  it('400s a missing or malformed due date', async () => {
    const a = app();
    expect((await a.inject({ method: 'GET', url: '/api/v1/pregnancy/timeline' })).statusCode).toBe(400);
    expect((await a.inject({ method: 'GET', url: '/api/v1/pregnancy/timeline?dueDate=09.12.2026' })).statusCode).toBe(400);
    await a.close();
  });

  it('serves a personalised child-development timeline', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1/child/timeline?birthDate=2026-06-01&from=2026-06-29&weeks=3' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.currentWeek).toBe(4);
    expect(j.timeline).toHaveLength(3);
    expect(j.timeline[0].content.ru).toBeTruthy();
    await a.close();
  });

  it('maps the antenatal protocol onto real dates for a due date', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1/protocols/antenatal/timeline?dueDate=2026-12-09' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.visits.length).toBeGreaterThan(0);
    expect(j.visits[0]).toHaveProperty('fromDate');
    expect(j.visits[0]).toHaveProperty('toDate');
    expect(j.visits[0].fromDate < j.visits[0].toDate).toBe(true);
    await a.close();
  });

  it('maps the vaccination schedule onto due dates + status for a birth date', async () => {
    const a = app();
    const r = await a.inject({ method: 'GET', url: '/api/v1/protocols/vaccination/timeline?birthDate=2026-06-01&from=2026-06-01' });
    expect(r.statusCode).toBe(200);
    const j = r.json();
    expect(j.vaccines.length).toBeGreaterThan(0);
    expect(j.vaccines[0]).toHaveProperty('dueDate');
    expect(['past', 'due', 'upcoming']).toContain(j.vaccines[0].status);
    // birth-day vaccines (atMonth 0) are due on the birth date itself.
    const atBirth = j.vaccines.find((v: { atMonth: number }) => v.atMonth === 0);
    if (atBirth) expect(atBirth.dueDate).toBe('2026-06-01');
    await a.close();
  });
});
