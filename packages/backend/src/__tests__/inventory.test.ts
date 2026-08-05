/**
 * Stock control: the ledger, the bundle, and refusing the impossible.
 *
 * What existed was an integer per colour. A delivery, a sale, a breakage and a
 * typo all looked identical — "the number is different now" — so the question
 * stock control exists to answer, *we counted forty and it says thirty-seven,
 * what happened*, had no answer anywhere in the system.
 *
 * The rules these lock down:
 *   - every change leaves a row saying why, and those rows sum to the count;
 *   - stock can never go below zero, because a ledger must not describe a
 *     state that cannot exist;
 *   - a bundle holds no stock of its own — it is worth as many sets as its
 *     scarcest part allows, so a combo can never oversell either half.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;

/** The first colour of a product, which is all these tests need. */
async function variantOf(productId: string): Promise<string> {
  const products = await repo.adminProducts();
  const p = products.find((x) => x.id === productId);
  expect(p, `no product ${productId}`).toBeTruthy();
  expect(p!.variants.length, `${productId} has no colours to stock`).toBeGreaterThan(0);
  return p!.variants[0].id;
}

const productById = async (id: string) =>
  (await repo.adminProducts()).find((p) => p.id === id)!;

beforeEach(() => {
  repo = createMemoryRepository();
});

describe('the ledger', () => {
  it('a receipt raises the count and records why', async () => {
    const v = await variantOf('watch');
    const res = await repo.moveStock({ variantId: v, delta: 50, reason: 'receipt', note: 'накладная 118', staffId: 's1' });
    expect(res).toEqual({ ok: true, stock: 50 });

    const moves = await repo.stockMoves(10, v);
    expect(moves).toHaveLength(1);
    expect(moves[0].delta).toBe(50);
    expect(moves[0].reason).toBe('receipt');
    expect(moves[0].note).toBe('накладная 118');
    expect(moves[0].staffId, 'a receipt with no author cannot be queried later').toBe('s1');
  });

  it('sums to the stock level — the ledger IS the count', async () => {
    // If these two can disagree, neither can be trusted, and the first person
    // to compare them stops using both.
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 50, reason: 'receipt' });
    await repo.moveStock({ variantId: v, delta: -3, reason: 'sale' });
    await repo.moveStock({ variantId: v, delta: -1, reason: 'writeoff', note: 'разбита при доставке' });
    await repo.moveStock({ variantId: v, delta: 2, reason: 'return' });

    const moves = await repo.stockMoves(100, v);
    const summed = moves.reduce((n, m) => n + m.delta, 0);
    const p = await productById('watch');
    const onHand = p.variants.find((x) => x.id === v)!.stock;
    expect(summed).toBe(onHand);
    expect(onHand).toBe(48);
  });

  it('refuses to go below zero, and changes nothing when it does', async () => {
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 2, reason: 'receipt' });

    const res = await repo.moveStock({ variantId: v, delta: -5, reason: 'sale' });
    expect(res).toEqual({ ok: false, error: 'insufficient_stock' });

    const p = await productById('watch');
    expect(p.variants.find((x) => x.id === v)!.stock, 'the refusal still moved stock').toBe(2);
    // And it left no row: a refused move is not a thing that happened.
    expect(await repo.stockMoves(100, v)).toHaveLength(1);
  });

  it('refuses an unknown variant rather than inventing one', async () => {
    const res = await repo.moveStock({ variantId: 'no-such-variant', delta: 1, reason: 'receipt' });
    expect(res).toEqual({ ok: false, error: 'unknown_variant' });
  });

  it('a stocktake writes the difference, not the total', async () => {
    // Somebody counts the shelf and types 7. The ledger has to record what
    // changed, or the history stops adding up to the count.
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 10, reason: 'receipt' });
    await repo.setShopVariantStock(v, 7, { staffId: 's1', note: 'пересчёт' });

    const moves = await repo.stockMoves(10, v);
    expect(moves[0].delta).toBe(-3);
    expect(moves[0].reason).toBe('correction');
    expect(moves[0].note).toBe('пересчёт');

    const summed = (await repo.stockMoves(100, v)).reduce((n, m) => n + m.delta, 0);
    expect(summed).toBe(7);
  });

  it('a stocktake that changes nothing writes nothing', async () => {
    // Otherwise the history fills with rows that record an absence of events,
    // and the entries that matter get lost among them.
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 5, reason: 'receipt' });
    await repo.setShopVariantStock(v, 5);
    expect(await repo.stockMoves(100, v)).toHaveLength(1);
  });
});

describe('the combo', () => {
  it('exists as a product with its own price', async () => {
    // The landing has sold it since launch and the back office had no such
    // product, so it could not be priced, counted or stopped from overselling.
    const combo = await productById('combo');
    expect(combo).toBeTruthy();
    expect(combo.kind).toBe('bundle');
    expect(combo.priceMinor).toBeGreaterThan(0);
  });

  it('is priced at what the landing sells it for', async () => {
    // 39 000 ₸, «Комплект «Мама и ребёнок»». The first version of this shipped
    // 27 900 under a made-up name, because I assumed a bundle must be a
    // discount and never opened the page. It is the opposite: the combo is the
    // two devices PLUS the Ма!Ма! course, which the landing presents as a
    // 40 000 ₸ gift — so it costs MORE than the hardware sum, and that extra is
    // exactly what unlocks the lessons in the app.
    const combo = await productById('combo');
    expect(combo.priceMinor).toBe(3900000);
    expect(combo.name).toContain('Мама и ребёнок');
  });

  it('costs more than the hardware alone, because it carries the course', async () => {
    const [watch, tracker, combo] = await Promise.all([
      productById('watch'), productById('tracker'), productById('combo'),
    ]);
    expect(combo.priceMinor).toBeGreaterThan(watch.priceMinor + tracker.priceMinor);
  });

  it('is worth as many sets as its scarcest part allows', async () => {
    await repo.moveStock({ variantId: await variantOf('watch'), delta: 5, reason: 'receipt' });
    await repo.moveStock({ variantId: await variantOf('tracker'), delta: 2, reason: 'receipt' });
    expect((await productById('combo')).stock, 'two trackers cap it at two combos').toBe(2);
  });

  it('is zero when either part is out of stock', async () => {
    await repo.moveStock({ variantId: await variantOf('watch'), delta: 10, reason: 'receipt' });
    // No trackers received at all.
    expect((await productById('combo')).stock).toBe(0);
  });

  it('holds no stock of its own that could drift', async () => {
    // Receiving watches alone must move the combo, because the combo is not a
    // thing on a shelf — it is an arithmetic statement about two other things.
    const before = (await productById('combo')).stock;
    await repo.moveStock({ variantId: await variantOf('watch'), delta: 3, reason: 'receipt' });
    await repo.moveStock({ variantId: await variantOf('tracker'), delta: 3, reason: 'receipt' });
    expect((await productById('combo')).stock).toBe(before + 3);
  });
});

describe('running out', () => {
  it('is flagged before a customer finds it', async () => {
    const watch = await productById('watch');
    expect(watch.stock).toBe(0);
    expect(watch.lowStock, 'nothing on the shelf and no warning').toBe(true);
  });

  it('stops being flagged once there is enough', async () => {
    const v = await variantOf('watch');
    const threshold = (await productById('watch')).lowStockThreshold;
    await repo.moveStock({ variantId: v, delta: threshold + 1, reason: 'receipt' });
    expect((await productById('watch')).lowStock).toBe(false);
  });
});

describe('orders and the ledger', () => {
  it('a sale is recorded, not just subtracted', async () => {
    // Sales were the one movement that left no trace: the count fell and the
    // history said nothing, so the two disagreed by everything ever sold.
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 10, reason: 'receipt' });

    const order = await repo.placeShopOrder({
      customerName: 'Айгерім', phone: '+7 707 000 00 00', city: 'Алматы',
      address: 'Абая 1', items: [{ variantId: v, qty: 2 }],
    });
    expect(order.ok).toBe(true);

    const moves = await repo.stockMoves(50, v);
    const sale = moves.find((m) => m.reason === 'sale');
    expect(sale, 'the sale left no ledger row').toBeTruthy();
    expect(sale!.delta).toBe(-2);
    expect(sale!.orderId, 'a sale that cannot be traced to its order').toBeTruthy();

    const summed = moves.reduce((n, m) => n + m.delta, 0);
    const p = await productById('watch');
    expect(summed).toBe(p.variants.find((x) => x.id === v)!.stock);
  });

  it('cancelling an order puts the goods back', async () => {
    // It did not, before: the order was marked cancelled and the stock stayed
    // gone, so every cancellation quietly shrank the sellable inventory.
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 10, reason: 'receipt' });
    const order = await repo.placeShopOrder({
      customerName: 'X', phone: '+7 700 000 00 00', city: 'Алматы',
      address: 'Абая 1', items: [{ variantId: v, qty: 3 }],
    });
    expect((await productById('watch')).variants.find((x) => x.id === v)!.stock).toBe(7);

    await repo.setShopOrderStatus((order as { id: string }).id, 'cancelled');
    expect((await productById('watch')).variants.find((x) => x.id === v)!.stock).toBe(10);

    const back = (await repo.stockMoves(50, v)).find((m) => m.reason === 'return');
    expect(back!.delta).toBe(3);
  });

  it('cancelling twice does not return the stock twice', async () => {
    const v = await variantOf('watch');
    await repo.moveStock({ variantId: v, delta: 5, reason: 'receipt' });
    const order = await repo.placeShopOrder({
      customerName: 'X', phone: '+7 700 000 00 00', city: 'Алматы',
      address: 'Абая 1', items: [{ variantId: v, qty: 1 }],
    });
    const id = (order as { id: string }).id;
    await repo.setShopOrderStatus(id, 'cancelled');
    await repo.setShopOrderStatus(id, 'cancelled');
    expect((await productById('watch')).variants.find((x) => x.id === v)!.stock).toBe(5);
  });
});
