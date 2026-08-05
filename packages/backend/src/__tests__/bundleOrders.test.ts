/**
 * Selling the комплект, and what the sale is allowed to promise.
 *
 * The bundle is the only product in the catalogue that costs MORE than the sum
 * of its parts: 39 000 against 29 800, because it carries the Ма!Ма! course.
 * That makes two rules load-bearing, and both are the kind that quietly stop
 * holding:
 *
 *   - a combo order is priced at the bundle's price, not the parts' sum, and
 *     still takes stock off both parts — one truth about what left the shelf;
 *   - buying a watch and a tracker separately is NOT the комплект. It costs
 *     less and unlocks nothing. If the parts granted the course, the bundle
 *     would have no reason to exist and nobody would ever buy it.
 *
 * And the entitlement follows the GOODS, not the order form: a 'new' order is
 * a promise that may never be collected.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;

const WATCH = 2490000;
const TRACKER = 490000;
const COMBO = 3900000;
const BUYER = '+7 (700) 111-22-33';
/** What the entitlement is keyed by — digits only, leading 8 folded to 7. */
const BUYER_KEY = '77001112233';

/** Stock the first colour of a product and hand back that variant id. */
async function stocked(productId: string, qty = 10): Promise<string> {
  const p = (await repo.adminProducts()).find((x) => x.id === productId)!;
  const v = p.variants[0].id;
  await repo.moveStock({ variantId: v, delta: qty, reason: 'receipt' });
  return v;
}

const order = (items: Array<{ variantId: string; qty: number }>, bundleId?: string) =>
  repo.placeShopOrder({
    customerName: 'Айгерим', phone: BUYER, city: 'Алматы', address: 'ул. Абая 1',
    items, bundleId,
  });

beforeEach(() => {
  repo = createMemoryRepository();
});

describe('pricing the комплект', () => {
  it('is priced at the bundle price, not the sum of its parts', async () => {
    const w = await stocked('watch');
    const t = await stocked('tracker');

    const res = await order([{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }], 'combo');

    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.totalMinor, 'the комплект costs 39 000, above its parts').toBe(COMBO);
    // The set costs MORE than the parts, so there is nothing to discount. A
    // negative "discount" would print as a refund on the receipt.
    expect(res.discountMinor).toBe(0);
  });

  it('takes stock off both parts — the set is not a thing on a shelf', async () => {
    const w = await stocked('watch');
    const t = await stocked('tracker');

    await order([{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }], 'combo');

    const vars = await repo.adminShopVariants();
    expect(vars.find((v) => v.id === w)!.stock).toBe(9);
    expect(vars.find((v) => v.id === t)!.stock).toBe(9);
  });

  it('refuses to be called a комплект without the parts in it', async () => {
    // Otherwise "sold as the combo" over one tracker buys a 40 000 ₸ course
    // for 4 900.
    const t = await stocked('tracker');

    const res = await order([{ variantId: t, qty: 1 }], 'combo');

    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.error).toBe('incomplete_bundle');
    // Nothing was committed: refusing an order must not take stock.
    const vars = await repo.adminShopVariants();
    expect(vars.find((v) => v.id === t)!.stock).toBe(10);
  });

  it('refuses an unknown bundle rather than charging the parts', async () => {
    const w = await stocked('watch');
    const res = await order([{ variantId: w, qty: 1 }], 'no-such-bundle');
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.error).toBe('not_found');
  });
});

describe('what the sale unlocks', () => {
  it('grants the course when the goods ship, not when the order is placed', async () => {
    const w = await stocked('watch');
    const t = await stocked('tracker');
    const res = await order([{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }], 'combo');
    expect(res.ok).toBe(true);
    if (!res.ok) return;

    expect(await repo.hasEntitlement(BUYER_KEY, 'mama_course'),
      'a new order is a promise, not a delivery').toBe(false);

    await repo.setShopOrderStatus(res.id, 'shipped');

    expect(await repo.hasEntitlement(BUYER_KEY, 'mama_course')).toBe(true);
  });

  it('grants nothing when the two devices are bought separately', async () => {
    // The whole reason the bundle is worth offering. 29 800 for the hardware,
    // 39 000 for the hardware AND the course.
    const w = await stocked('watch');
    const t = await stocked('tracker');

    const res = await order([{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }]);
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.totalMinor).toBe(WATCH + TRACKER);

    await repo.setShopOrderStatus(res.id, 'shipped');
    await repo.setShopOrderStatus(res.id, 'delivered');

    expect(await repo.hasEntitlement(BUYER_KEY, 'mama_course')).toBe(false);
  });

  it('keeps the first grant when the order moves shipped → delivered', async () => {
    const w = await stocked('watch');
    const t = await stocked('tracker');
    const res = await order([{ variantId: w, qty: 1 }, { variantId: t, qty: 1 }], 'combo');
    if (!res.ok) throw new Error('order refused');

    await repo.setShopOrderStatus(res.id, 'shipped');
    await repo.setShopOrderStatus(res.id, 'delivered');

    const owned = await repo.listEntitlements('mama_course', 50);
    expect(owned.filter((e) => e.phone === BUYER_KEY),
      'one purchase, one grant').toHaveLength(1);
    expect(owned[0].orderId, 'the grant says which sale earned it').toBe(res.id);
  });
});

describe('the storefront can see the комплект at all', () => {
  it('lists the bundle with its parts, so a buyer can pick both colours', async () => {
    const products = await repo.shopProducts();
    const combo = products.find((p) => p.id === 'combo');

    expect(combo, 'a product nobody can see is a product nobody can buy').toBeTruthy();
    expect(combo!.kind).toBe('bundle');
    expect(combo!.priceMinor).toBe(COMBO);
    expect(combo!.parts.map((p) => p.partId).sort()).toEqual(['tracker', 'watch']);
    // No colours of its own — the buyer chooses the parts' colours.
    expect(combo!.variants).toEqual([]);
  });
});
