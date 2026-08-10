/**
 * Frames 05 / 05a / 05b — the money arithmetic.
 *
 * The assertions that matter are the ones about what is NOT counted: a promise
 * is not revenue, and a margin computed over the lines that happen to have a
 * cost is not the margin.
 */

import { describe, it, expect } from 'vitest';
import { buildFinanceReport, financeCsv } from '../admin/finance';
import type { InventoryProduct, ShopOrder, StockMove } from '../db/repository';

const NO_CATALOGUE = {
  nameKk: null, stage: null, category: null, descriptionRu: null, descriptionKk: null,
  ageMinMonths: null, ageMaxMonths: null, photoUrl: null,
  seoSlug: null, seoTitle: null, seoDescription: null,
} as const;

const product = (name: string, priceMinor: number, costMinor: number | null): InventoryProduct => ({
  id: name, name, sku: null, priceMinor, costMinor, kind: 'simple', active: true, sort: 0,
  lowStockThreshold: 3, stock: 10, lowStock: false, variants: [], ...NO_CATALOGUE,
});

let n = 0;
const order = (o: Partial<ShopOrder> & { status: ShopOrder['status'] }): ShopOrder => ({
  id: `o${++n}`, customerName: 'Айгерім', phone: '+77000000000', city: 'Алматы',
  address: 'ул. 1', note: null, totalMinor: 1_000_000, discountMinor: 0,
  createdAt: '2026-08-10T10:00:00.000Z',
  items: [{ productName: 'Часы', color: 'rose', qty: 1, unitPriceMinor: 1_000_000 }],
  ...o,
});

const move = (m: Partial<StockMove> & { reason: StockMove['reason']; delta: number }): StockMove => ({
  id: ++n, variantId: 'v1', productName: 'Часы', color: 'rose',
  note: null, staffId: null, orderId: null, at: '2026-08-10T10:00:00.000Z', ...m,
});

const WINDOW = { from: '2026-08-01', to: '2026-08-31' };
const build = (i: Partial<Parameters<typeof buildFinanceReport>[0]>) =>
  buildFinanceReport({
    orders: [], products: [], moves: [], planMinor: null, ...WINDOW, ...i,
  });

describe('what counts as earned', () => {
  it('counts shipped and delivered, not new and confirmed', () => {
    const r = build({
      orders: [
        order({ status: 'delivered', totalMinor: 3_900_000 }),
        order({ status: 'shipped', totalMinor: 1_000_000 }),
        order({ status: 'new', totalMinor: 5_000_000 }),
        order({ status: 'confirmed', totalMinor: 2_000_000 }),
      ],
    });
    // A month looks profitable until the cancellations land, if promises count.
    expect(r.money.earnedMinor).toBe(4_900_000);
    expect(r.money.promisedMinor).toBe(7_000_000);
  });

  it('keeps cancellations separate rather than dropping them', () => {
    // Money that was nearly made is a number somebody wants; silently omitting
    // it makes a bad month look like a quiet one.
    const r = build({ orders: [order({ status: 'cancelled', totalMinor: 900_000 })] });
    expect(r.money.lostMinor).toBe(900_000);
    expect(r.money.earnedMinor).toBe(0);
  });

  it('averages the earned orders only', () => {
    const r = build({
      orders: [
        order({ status: 'delivered', totalMinor: 1_000_000 }),
        order({ status: 'delivered', totalMinor: 3_000_000 }),
        order({ status: 'new', totalMinor: 99_000_000 }),
      ],
    });
    expect(r.money.averageCheckMinor).toBe(2_000_000);
  });

  it('has no average to report when nothing was earned', () => {
    expect(build({ orders: [order({ status: 'new' })] }).money.averageCheckMinor).toBe(0);
  });

  it('ignores orders outside the window', () => {
    const r = build({
      orders: [
        order({ status: 'delivered', createdAt: '2026-07-31T23:00:00.000Z', totalMinor: 500_000 }),
        order({ status: 'delivered', createdAt: '2026-08-01T00:00:00.000Z', totalMinor: 700_000 }),
      ],
    });
    expect(r.money.earnedMinor).toBe(700_000);
  });
});

describe('margin, and how much of it is real', () => {
  it('computes margin over the lines whose cost is known', () => {
    const r = build({
      orders: [order({ status: 'delivered', totalMinor: 1_000_000 })],
      products: [product('Часы', 1_000_000, 600_000)],
    });
    expect(r.margin.costMinor).toBe(600_000);
    expect(r.margin.marginMinor).toBe(400_000);
    expect(r.margin.coverage).toBe(1);
  });

  it('reports the coverage when a product has no cost', () => {
    // The important one. A margin computed over 50% of revenue reads as THE
    // margin unless the screen says otherwise.
    const r = build({
      orders: [
        order({
          status: 'delivered', totalMinor: 2_000_000,
          items: [
            { productName: 'Часы', color: 'rose', qty: 1, unitPriceMinor: 1_000_000 },
            { productName: 'Трекер', color: 'blue', qty: 1, unitPriceMinor: 1_000_000 },
          ],
        }),
      ],
      products: [product('Часы', 1_000_000, 600_000), product('Трекер', 1_000_000, null)],
    });
    expect(r.margin.coverage).toBe(0.5);
    expect(r.margin.missingCost).toEqual(['Трекер']);
    expect(r.caveats.join(' ')).toContain('Трекер');
    expect(r.caveats.join(' ')).toContain('50%');
  });

  it('does not claim full coverage when there were no orders at all', () => {
    // coverage 1 would read as "every line priced" on an empty month.
    expect(build({}).margin.coverage).toBe(0);
  });
});

describe('returns and write-offs (05a)', () => {
  it('counts units, not signed deltas', () => {
    const r = build({
      moves: [
        move({ reason: 'sale', delta: -10 }),
        move({ reason: 'return', delta: 2 }),
        move({ reason: 'writeoff', delta: -3 }),
      ],
    });
    expect(r.returns.soldUnits).toBe(10);
    expect(r.returns.returnedUnits).toBe(2);
    expect(r.returns.writtenOffUnits).toBe(3);
    expect(r.returns.returnRate).toBeCloseTo(0.2);
  });

  it('values write-offs at cost where cost is known', () => {
    const r = build({
      moves: [move({ reason: 'writeoff', delta: -2 })],
      products: [product('Часы', 1_000_000, 600_000)],
    });
    expect(r.returns.writeOffCostMinor).toBe(1_200_000);
  });

  it('reports a rate of zero rather than dividing by nothing', () => {
    const r = build({ moves: [move({ reason: 'return', delta: 1 })] });
    expect(r.returns.returnRate).toBe(0);
    expect(Number.isFinite(r.returns.returnRate)).toBe(true);
  });

  it('lists the events newest first', () => {
    const r = build({
      moves: [
        move({ reason: 'return', delta: 1, at: '2026-08-02T10:00:00.000Z' }),
        move({ reason: 'writeoff', delta: -1, at: '2026-08-09T10:00:00.000Z' }),
      ],
    });
    expect(r.returns.events.map((e) => e.reason)).toEqual(['writeoff', 'return']);
  });
});

describe('what the report refuses to claim', () => {
  it('always says the payment-method split is unavailable', () => {
    // shop_orders has no payment-method column. Guessing one on a screen where
    // somebody reconciles a bank statement is the worst place to be plausibly
    // wrong, so the absence is stated on every report.
    expect(build({}).caveats.join(' ')).toContain('способ оплаты');
  });

  it('reports plan progress only when a plan is set', () => {
    expect(build({}).planProgress).toBeNull();
    const r = build({
      planMinor: 10_000_000,
      orders: [order({ status: 'delivered', totalMinor: 2_500_000 })],
    });
    expect(r.planProgress).toBeCloseTo(0.25);
  });
});

describe('the CSV export (05b)', () => {
  it('opens correctly in a Russian Excel', () => {
    const csv = financeCsv(build({}));
    expect(csv.startsWith('﻿')).toBe(true);  // Cyrillic, not mojibake
    expect(csv).toContain(';');                    // semicolons, not commas
    expect(csv).toContain('\r\n');
  });

  it('uses a decimal COMMA, so a price is not read as thousands', () => {
    const csv = financeCsv(build({ orders: [order({ status: 'delivered', totalMinor: 3_900_000 })] }));
    expect(csv).toContain('39000,00');
  });

  it('carries the caveats into the file', () => {
    // A number pasted into a message loses its footnote; the margin one is
    // load-bearing.
    const csv = financeCsv(build({
      orders: [order({ status: 'delivered' })],
      products: [product('Часы', 1_000_000, null)],
    }));
    expect(csv).toContain('Оговорка');
    expect(csv).toContain('Себестоимость не указана');
  });

  it('quotes a value containing a semicolon', () => {
    const csv = financeCsv(build({
      orders: [order({ status: 'delivered' })],
      products: [product('Часы', 1_000_000, null), product('Трекер', 1, null)],
    }));
    // The missing-cost caveat lists names separated by commas inside one cell;
    // any cell holding the delimiter must be quoted or the columns shift.
    for (const line of csv.split('\r\n')) {
      const unquoted = line.replace(/"[^"]*"/g, '');
      expect(unquoted.split(';').length).toBeLessThanOrEqual(2);
    }
  });
});
