/**
 * Days of cover — the sentence a stock level needs to mean anything.
 *
 * The arithmetic is trivial; what is worth pinning is the cases where a naive
 * division gives a confident wrong answer, because each of those would appear
 * on the warehouse screen as a fact.
 */

import { describe, it, expect } from 'vitest';
import { needsReorder, runwayOf } from '../inventory/runway';

describe('how long the shelf lasts', () => {
  it('the spec\'s own example: 26 units, 12 a shipment', () => {
    // «хватит на 4 дня при поставке 12» — 26 on hand selling ~6 a day.
    const r = runwayOf(26, 180, 30)!;
    expect(r.perDay).toBe(6);
    expect(r.days).toBe(4);
    expect(r.noSales).toBe(false);
  });

  it('floors, because a part-day is not a day you can promise', () => {
    // 10 units at 3/day is 3.33 days. Reporting 3 is the number a buyer can
    // act on; rounding to 3.3 or up to 4 both promise stock that is not there.
    expect(runwayOf(10, 90, 30)!.days).toBe(3);
    expect(runwayOf(29, 300, 30)!.days).toBe(2);
  });

  it('nothing sold is not infinite cover', () => {
    const r = runwayOf(40, 0, 30)!;
    expect(r.noSales).toBe(true);
    expect(r.perDay).toBe(0);
    // The caller must render this as "no sales", never as a number of days:
    // «хватит на ∞ дней» next to a product nobody is buying reads as the best
    // news on the screen about the worst thing on it.
    expect(r.days).toBe(Number.POSITIVE_INFINITY);
  });

  it('an empty shelf is zero days, sales or no sales', () => {
    expect(runwayOf(0, 0, 30)!.days).toBe(0);
    expect(runwayOf(0, 60, 30)!.days).toBe(0);
  });

  it('refuses to answer rather than answering wrongly', () => {
    expect(runwayOf(10, 5, 0), 'a zero-day window is a division by zero').toBeNull();
    expect(runwayOf(-1, 5, 30), 'a negative level means the ledger and the shelf disagree').toBeNull();
    expect(runwayOf(10, -5, 30), 'negative sales would report a shelf that fills itself').toBeNull();
    expect(runwayOf(Number.NaN, 5, 30)).toBeNull();
  });
});

describe('when to reorder', () => {
  const LEAD = 14;

  it('flags stock that runs out before a shipment can land', () => {
    expect(needsReorder(runwayOf(26, 180, 30), LEAD), '4 days of cover').toBe(true);
    expect(needsReorder(runwayOf(200, 180, 30), LEAD), '33 days of cover').toBe(false);
  });

  it('the boundary is "runs out before it arrives", not "on the day"', () => {
    // Exactly 14 days of cover and a 14-day lead time: the shipment lands the
    // day the shelf empties. Tight, not late.
    expect(needsReorder(runwayOf(140, 300, 30), LEAD)).toBe(false); // 14 days
    expect(needsReorder(runwayOf(130, 300, 30), LEAD)).toBe(true);  // 13 days
  });

  it('does not nag about a product nobody is buying', () => {
    // 2 units left and no sales in a month. Ordering more is the wrong action;
    // the low-stock threshold somebody set by hand is the right signal here,
    // and it is still there.
    expect(needsReorder(runwayOf(2, 0, 30), LEAD)).toBe(false);
  });

  it('says nothing when the runway could not be computed', () => {
    expect(needsReorder(null, LEAD)).toBe(false);
  });
});
