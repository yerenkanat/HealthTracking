/**
 * Frames 05 / 05a / 05b — the money arithmetic.
 *
 * The assertions that matter are the ones about what is NOT counted: a promise
 * is not revenue, and a margin computed over the lines that happen to have a
 * cost is not the margin.
 */

import { describe, it, expect } from 'vitest';
import { buildFinanceReport, financeCsv } from '../admin/finance';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { InventoryProduct, OrderRefund, ShopOrder, StockMove } from '../db/repository';

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
  note: null, staffId: null, orderId: null, refundId: null, at: '2026-08-10T10:00:00.000Z', ...m,
});

/**
 * The two things a reason='return' move can be, spelled out.
 *
 * They were one number — «Возвратов, шт» — and that is the defect: cancelling
 * an order puts its goods back on the shelf with the same ledger reason a
 * customer's return does, so the count and the rate were computed over orders
 * that had never been in revenue at all. Every case below now says which of the
 * two it means.
 */
const refunded = (delta: number, over: Partial<StockMove> = {}): StockMove =>
  move({ reason: 'return', delta, orderId: 'o-refunded', refundId: 1, ...over });
const cancelled = (delta: number, over: Partial<StockMove> = {}): StockMove =>
  move({ reason: 'return', delta, orderId: 'o-cancelled', refundId: null, ...over });

const refund = (r: Partial<OrderRefund> = {}): OrderRefund => ({
  id: 1, orderId: 'o-refunded', amountMinor: 100_000, reason: 'defect',
  note: null, staffId: null, staffName: null, restockedUnits: 1,
  at: '2026-08-10T10:00:00.000Z', ...r,
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
        refunded(2),
        move({ reason: 'writeoff', delta: -3 }),
      ],
      refunds: [refund({ restockedUnits: 2 })],
    });
    expect(r.returns.soldUnits).toBe(10);
    expect(r.returns.returnedUnits).toBe(2);
    expect(r.returns.writtenOffUnits).toBe(3);
    expect(r.returns.returnRate).toBeCloseTo(0.2);
  });

  /**
   * The number frame 05 printed wrongly.
   *
   * Cancelling an order returns its goods to the shelf with reason='return' and
   * the order id — the same shape a customer's return has — and «Возвратов, шт»
   * and «Доля возвратов, %» counted the two together, over units SOLD. So a
   * month of cancellations read as a month of returns, and, since there was no
   * way to record a real return at all, every figure on that card was about
   * something else entirely.
   */
  it('does not count a cancelled order as a customer return', () => {
    const r = build({
      moves: [
        move({ reason: 'sale', delta: -10 }),
        refunded(1),
        cancelled(3),
      ],
      refunds: [refund({})],
    });
    expect(r.returns.returnedUnits, 'a cancellation is being counted as a return').toBe(1);
    expect(r.returns.cancelledUnits, 'the cancelled units vanished instead of being reported').toBe(3);
    // 1 ÷ 10, not 4 ÷ 10. That is the whole fix.
    expect(r.returns.returnRate).toBeCloseTo(0.1);
  });

  it('reports a return with neither an order nor a refund as neither', () => {
    // Nothing in the product writes one; a row here means somebody edited the
    // ledger by hand. Folding it into either real bucket would move a number a
    // person is answerable for.
    const r = build({
      moves: [move({ reason: 'sale', delta: -10 }), move({ reason: 'return', delta: 2 })],
    });
    expect(r.returns.returnedUnits).toBe(0);
    expect(r.returns.cancelledUnits).toBe(0);
    expect(r.returns.otherReturnUnits).toBe(2);
    expect(r.returns.returnRate).toBe(0);
    expect(r.caveats.join(' ')).toContain('без оформленного возврата');
  });

  it('adds up the money handed back, and takes it off the revenue', () => {
    const r = build({
      orders: [order({ status: 'delivered', totalMinor: 1_000_000 })],
      refunds: [
        refund({ id: 1, amountMinor: 300_000 }),
        refund({ id: 2, amountMinor: 200_000, reason: 'changed_mind' }),
      ],
    });
    expect(r.money.refundedMinor).toBe(500_000);
    expect(r.money.earnedNetMinor).toBe(500_000);
    expect(r.returns.refundCount).toBe(2);
    expect(r.returns.reasonCounts.defect).toBe(1);
    expect(r.returns.reasonCounts.changed_mind).toBe(1);
    expect(r.returns.reasonCounts.not_delivered).toBe(0);
  });

  it('does not floor a month whose refunds outran its own sales', () => {
    // A real and alarming answer. Clamping it at zero would draw that month as
    // merely empty.
    const r = build({ refunds: [refund({ amountMinor: 900_000 })] });
    expect(r.money.earnedNetMinor).toBe(-900_000);
  });

  it('never invents a reason for a refund taken before reasons existed', () => {
    // There are none to invent one for — the table did not exist — and the
    // report says so for any window reaching back before that date instead of
    // redistributing old cancellations into «другое».
    const r = build({ from: '2026-01-01', to: '2026-12-31' });
    expect(r.returns.reasonsRecordedSince).toBe('2026-08-20');
    expect(r.caveats.join(' ')).toContain('Причины возвратов записываются с 2026-08-20');
    expect(Object.values(r.returns.reasonCounts).every((v) => v === 0)).toBe(true);
  });

  it('says the money back is UNKNOWN when the refunds could not be read', () => {
    // 0 ₸ and «мы не смогли прочитать» are different sentences, and the first
    // one is the flattering one.
    const r = build({ refundsUnavailable: true });
    expect(r.slice.refundsComplete).toBe(false);
    expect(financeCsv(r)).toContain('Возвращено денег, ₸;неизвестно');
    expect(financeCsv(r)).not.toContain('Возвращено денег, ₸;0,00');
  });

  it('labels each event as what it is, and carries the refund reason', () => {
    const r = build({
      moves: [refunded(1), cancelled(1), move({ reason: 'writeoff', delta: -1 })],
      refunds: [refund({ reason: 'not_suitable' })],
    });
    expect(r.returns.events.map((e) => e.kind).sort())
      .toEqual(['cancel', 'refund', 'writeoff']);
    const ret = r.returns.events.find((e) => e.kind === 'refund')!;
    expect(ret.refundReason).toBe('not_suitable');
    // A cancellation has no reason to carry, and none is invented for it.
    expect(r.returns.events.find((e) => e.kind === 'cancel')!.refundReason).toBeNull();
  });

  it('values write-offs at cost where cost is known', () => {
    const r = build({
      moves: [move({ reason: 'writeoff', delta: -2 })],
      products: [product('Часы', 1_000_000, 600_000)],
    });
    expect(r.returns.writeOffCostMinor).toBe(1_200_000);
  });

  it('reports a rate of zero rather than dividing by nothing', () => {
    const r = build({ moves: [refunded(1)], refunds: [refund({})] });
    expect(r.returns.returnRate).toBe(0);
    expect(Number.isFinite(r.returns.returnRate)).toBe(true);
  });

  it('lists the events newest first', () => {
    const r = build({
      moves: [
        refunded(1, { at: '2026-08-02T10:00:00.000Z' }),
        move({ reason: 'writeoff', delta: -1, at: '2026-08-09T10:00:00.000Z' }),
      ],
    });
    expect(r.returns.events.map((e) => e.reason)).toEqual(['writeoff', 'return']);
  });
});

describe('a period deeper than the rows it was given', () => {
  /**
   * Ask for last February.
   *
   * /admin/finance reads the newest 1 000 orders and the newest 2 000 stock
   * moves and then reports on whatever window is asked for. A sale writes one
   * stock move PER ORDER LINE, so the moves slice is exhausted first: for an
   * older month every move in the window is missing, `soldUnits` is 0,
   * `returnedUnits` is 0, and the rate was 0 ÷ 0 = 0. The CSV then printed
   * «Доля возвратов, % — 0,0» under three confident caveats, none of which was
   * the true one. A fabricated zero, in the file somebody forwards.
   */
  const FEB = { from: '2026-02-01', to: '2026-02-28' };
  const truncatedToAugust = {
    ...FEB,
    moves: [move({ reason: 'sale', delta: -1, at: '2026-08-10T10:00:00.000Z' })],
    movesTruncated: true,
    movesWindow: 2000,
  };

  it('says the return rate is unknown rather than zero', () => {
    const r = build(truncatedToAugust);
    expect(r.returns.returnRate, 'a period nobody looked at reported a 0% return rate')
      .toBeNull();
    expect(r.slice.movesComplete).toBe(false);
  });

  it('and the CSV prints the word, not a number', () => {
    // The cell outlives every caveat around it: it gets pasted on its own.
    const csv = financeCsv(build(truncatedToAugust));
    expect(csv).toContain('Доля возвратов, %;неизвестно');
    expect(csv, 'a fabricated zero survived into the export').not.toContain('Доля возвратов, %;0,0');
  });

  it('names the truncation as a caveat, and says which way to fix it', () => {
    const caveats = build(truncatedToAugust).caveats.join(' ');
    expect(caveats).toContain('2000');
    expect(caveats).toContain('период короче');
  });

  it('marks the counts it can only give a floor for', () => {
    const csv = financeCsv(build({
      ...truncatedToAugust,
      moves: [
        move({ reason: 'sale', delta: -1, at: '2026-08-10T10:00:00.000Z' }),
        refunded(1, { at: '2026-02-10T10:00:00.000Z' }),
      ],
      refunds: [refund({ at: '2026-02-10T10:00:00.000Z' })],
    }));
    expect(csv).toContain('Возвратов от покупателей, шт;не менее 1');
  });

  it('a full slice that still reaches past the start is complete', () => {
    // Truncation alone is not incompleteness. 2 000 moves whose oldest predates
    // the window answer the question fully, and calling that «неизвестно» would
    // train everyone to ignore the word.
    const r = build({
      ...FEB,
      moves: [
        move({ reason: 'sale', delta: -10, at: '2026-01-20T10:00:00.000Z' }),
        refunded(2, { at: '2026-02-10T10:00:00.000Z' }),
        move({ reason: 'sale', delta: -10, at: '2026-02-11T10:00:00.000Z' }),
      ],
      movesTruncated: true,
      movesWindow: 2000,
    });
    expect(r.slice.movesComplete).toBe(true);
    expect(r.returns.returnRate).toBeCloseTo(0.2);
  });

  it('a truncated slice that fetched nothing at all covers nothing', () => {
    const r = build({ ...FEB, moves: [], movesTruncated: true, movesWindow: 2000 });
    expect(r.slice.movesComplete).toBe(false);
    expect(r.returns.returnRate).toBeNull();
  });

  it('the money block says so too, and prints its totals as floors', () => {
    const r = build({
      ...FEB,
      orders: [order({ status: 'delivered', createdAt: '2026-08-10T10:00:00.000Z' })],
      ordersTruncated: true,
      ordersWindow: 1000,
    });
    expect(r.slice.ordersComplete).toBe(false);
    expect(r.caveats.join(' ')).toContain('1000');
    expect(financeCsv(r)).toContain('Заработано, ₸;не менее 0,00');
  });

  it('an untruncated report claims nothing about slices', () => {
    // The flags have to mean something: a report over everything is complete,
    // and its numbers are printed plainly.
    const r = build({ moves: [move({ reason: 'sale', delta: -5 })] });
    expect(r.slice).toEqual({
      ordersComplete: true, movesComplete: true, refundsComplete: true,
      ordersWindow: null, movesWindow: null,
    });
    expect(financeCsv(r)).not.toContain('не менее');
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

// ---------------------------------------------------------------------------

describe('GET /admin/finance reports on the period it can actually see', () => {
  /**
   * The route reads a fixed number of newest rows and accepts any window.
   *
   * The report cannot know that on its own — it is pure, it sees a list. So the
   * route has to tell it, exactly as the mother's card already tells
   * buildMotherCard (`ordersTruncated`, routes/admin.ts). This drives the whole
   * chain over HTTP because the wiring is the part that goes missing: the pure
   * tests above all pass with the flags never sent.
   */
  const financeApp = (stockMoves: (limit: number) => Promise<StockMove[]>) => {
    const repo = createMemoryRepository();
    return buildServer(
      {
        repo: { ...repo, stockMoves } as unknown as ReturnType<typeof createMemoryRepository>,
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
  };

  // More recent moves than the route will read, so the slice it gets back is
  // full and every one of them post-dates the February it is asked about.
  const AUGUST = Array.from({ length: 4000 }, () =>
    move({ reason: 'sale', delta: -1, at: '2026-08-10T10:00:00.000Z' }));

  it('says «неизвестно» for a month that fell off the end of the slice', async () => {
    const app = financeApp(async (limit) => AUGUST.slice(0, limit));
    const body = (await app.inject({
      method: 'GET', url: '/admin/finance?from=2026-02-01&to=2026-02-28',
    })).json();
    expect(body.slice.movesComplete, 'the route never told the report its slice was full')
      .toBe(false);
    expect(body.returns.returnRate, 'a February nobody read reported a 0% return rate')
      .toBeNull();
    await app.close();
  });

  it('and the exported CSV carries the word rather than a zero', async () => {
    const app = financeApp(async (limit) => AUGUST.slice(0, limit));
    const res = await app.inject({
      method: 'GET', url: '/admin/finance?from=2026-02-01&to=2026-02-28&format=csv',
    });
    expect(res.body).toContain('Доля возвратов, %;неизвестно');
    expect(res.body).not.toContain('Доля возвратов, %;0,0');
    // And the file says why, since a cell gets forwarded without the screen.
    expect(res.body).toContain('движений склада');
    await app.close();
  });

  it('a short slice reports a real rate', async () => {
    // Non-vacuity: if this route answered «неизвестно» always, the word would
    // stop being read the same week it shipped.
    const app = financeApp(async () => [
      move({ reason: 'sale', delta: -10, at: '2026-02-10T10:00:00.000Z' }),
      refunded(2, { at: '2026-02-12T10:00:00.000Z' }),
    ]);
    const body = (await app.inject({
      method: 'GET', url: '/admin/finance?from=2026-02-01&to=2026-02-28',
    })).json();
    expect(body.slice.movesComplete).toBe(true);
    expect(body.returns.returnRate).toBeCloseTo(0.2);
    await app.close();
  });
});
