/**
 * The Dashboard's arithmetic.
 *
 * A business dashboard is read to decide things — order more stock, chase the
 * unshipped orders, stop selling in a city nobody lives in. That makes a wrong
 * number worse than a missing one: an empty card is obviously empty, while
 * "выручка 156 000 ₸" that silently counts cancelled orders reads as fact.
 *
 * So these pin the definitions rather than the plumbing:
 *   - revenue is what SHIPPED. A new order is a phone call.
 *   - a cancelled order is not revenue and its stock came back.
 *   - stock value never counts a bundle, whose stock IS its parts.
 *   - "pregnant" and "mother" overlap, and the overlap is stated.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;
const NOW = '2026-08-06T10:00:00.000Z';

async function stocked(productId: string, qty: number): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const v = p.variants[0].id;
  await repo.moveStock({ variantId: v, delta: qty, reason: 'receipt' });
  return v;
}

const order = (items: Array<{ variantId: string; qty: number }>, bundleId?: string) =>
  repo.placeShopOrder({
    customerName: 'Айгерим', phone: '+77001112233', city: 'Алматы',
    address: 'ул. Абая 1', items, bundleId,
  });

beforeEach(() => { repo = createMemoryRepository(); });

describe('what the shop has done', () => {
  it('counts nothing as revenue until it ships', async () => {
    const v = await stocked('watch', 5);
    const res = await order([{ variantId: v, qty: 1 }]);
    if (!res.ok) throw new Error('order refused');

    let snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.orders.total).toBe(1);
    expect(snap.commerce.revenueMinor, 'a new order is a promise').toBe(0);
    expect(snap.commerce.pipelineMinor, 'and it belongs in the pipeline').toBe(2490000);
    expect(snap.commerce.avgOrderMinor).toBeNull();

    await repo.setShopOrderStatus(res.id, 'shipped');

    snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.revenueMinor).toBe(2490000);
    expect(snap.commerce.pipelineMinor).toBe(0);
    expect(snap.commerce.avgOrderMinor).toBe(2490000);
  });

  it('does not count a cancelled order as money', async () => {
    const v = await stocked('watch', 5);
    const res = await order([{ variantId: v, qty: 1 }]);
    if (!res.ok) throw new Error('order refused');
    await repo.setShopOrderStatus(res.id, 'cancelled');

    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.revenueMinor).toBe(0);
    expect(snap.commerce.pipelineMinor).toBe(0);
    expect(snap.commerce.orders.cancelled).toBe(1);
    // The stock came back with the cancellation, so it is on the shelf again.
    expect(snap.commerce.stock.units).toBe(5);
  });

  it('values the shelf without counting the комплект twice', async () => {
    await stocked('watch', 2);
    await stocked('tracker', 3);

    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.stock.units, 'a bundle holds no stock of its own').toBe(5);
    expect(snap.commerce.stock.retailMinor).toBe(2 * 2490000 + 3 * 490000);
    // No purchase cost is recorded yet, so margin is unknown — and it says so
    // rather than reporting the whole retail value as profit.
    expect(snap.commerce.stock.costMinor).toBe(0);
    expect(snap.commerce.stock.unitsWithoutCost).toBe(5);
  });

  it('reports the margin only over stock whose cost is known', async () => {
    await stocked('watch', 2);
    await repo.upsertProduct({ id: 'watch', name: 'Смарт-часы Ana-Bala', priceMinor: 2490000, costMinor: 1600000 });

    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.stock.costMinor).toBe(2 * 1600000);
    expect(snap.commerce.stock.unitsWithoutCost).toBe(0);
  });

  it('separates leads waiting for a call from the ones already handled', async () => {
    await repo.recordShopLead({ customerName: 'Мадина', phone: '+77010000000', locale: 'ru' });
    await repo.recordShopLead({ customerName: 'Сауле', phone: '+77020000000', locale: 'ru' });
    const l = (await repo.adminShopLeads(10))[0];
    await repo.setShopLeadStatus(l.id, 'called');

    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.leads.total).toBe(2);
    expect(snap.commerce.leads.new).toBe(1);
  });

  it('names the products that are running out', async () => {
    // Nothing has been received, so everything is at zero.
    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.lowStock).toContain('watch');

    await stocked('watch', 50);
    expect((await repo.dashboardSnapshot(NOW)).commerce.lowStock).not.toContain('watch');
  });
});

describe('who the users are', () => {
  it('counts the children by sex and by age', async () => {
    const snap = await repo.dashboardSnapshot(NOW);
    // The demo cohort: the counts must be the rows, not a made-up split.
    expect(snap.children.total).toBe(snap.children.boys + snap.children.girls + snap.children.unknown);
    expect(snap.children.byAge.reduce((t, b) => t + b.count, 0)).toBe(snap.children.withDob);
  });

  it('lets pregnant and mother overlap instead of forcing a choice', async () => {
    const snap = await repo.dashboardSnapshot(NOW);
    // A mother expecting her second is both; the shape has to allow it, or
    // whichever bucket she is forced into misstates the other number.
    expect(snap.mothers.both).toBeLessThanOrEqual(Math.min(snap.mothers.pregnant, snap.mothers.mothers));
  });

  it('says how many did not give a city rather than guessing', async () => {
    const snap = await repo.dashboardSnapshot(NOW);
    const named = snap.cities.reduce((t, c) => t + c.users, 0);
    expect(named + snap.citiesUnknown).toBeLessThanOrEqual(snap.users.total + snap.cities.length);
    expect(snap.citiesUnknown).toBeGreaterThanOrEqual(0);
  });

  it('splits the fleet into what we sell — watches and trackers', async () => {
    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.devices.watches + snap.devices.trackers).toBeLessThanOrEqual(snap.devices.total);
  });
});

describe('the snapshot as a whole', () => {
  it('is stamped with the instant every number is as of', async () => {
    // The panel used to stitch six endpoints together, so "12 users" and
    // "13 cities" could both be true and disagree.
    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.asOf).toBe(NOW);
  });

  it('reports an empty business as empty, not as missing', async () => {
    const snap = await repo.dashboardSnapshot(NOW);
    expect(snap.commerce.orders.total).toBe(0);
    expect(snap.commerce.revenueMinor).toBe(0);
    // Null, not 0: there is no average of no orders, and 0 ₸ would read as
    // "we sell things and get nothing for them".
    expect(snap.commerce.avgOrderMinor).toBeNull();
  });
});
