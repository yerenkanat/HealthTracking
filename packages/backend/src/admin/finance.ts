/**
 * Frames 05 / 05a / 05b — «Финансы · платежи», «Возвраты и брак», «Отчёт».
 *
 * WHAT THIS DOES NOT DO, AND WHY
 *
 * The spec calls frame 05 «платежи», which implies splitting money by how it
 * was paid — Kaspi against cash on delivery. shop_orders has no payment-method
 * column and never has, so that split cannot be computed. Inventing it (guess
 * from the presence of a Kaspi link, say) would put a confident number on a
 * screen where somebody reconciles a bank statement, which is the worst
 * possible place to be plausibly wrong. The screen instead reports the split it
 * CAN stand behind — earned, promised, lost — and says the method breakdown
 * needs a column that does not exist.
 *
 * ON «ЗАРАБОТАНО». Only shipped and delivered count. An order sitting at «new»
 * is a promise: stock is reserved and nothing has been collected. Counting it
 * as revenue is how a month looks profitable until the cancellations land.
 * Same split as the owner's dashboard, deliberately — two screens disagreeing
 * about this month's revenue is worse than either being slightly wrong.
 *
 * ON MARGIN. cost_minor is nullable and most products have none. Margin is
 * therefore computed over the lines whose cost IS known, and the screen is told
 * how much of the revenue that covers. A margin figure silently computed over
 * 40 % of sales reads as the real one.
 *
 * PURE: orders, products and stock moves in, the three screens' numbers out.
 */

import { ORDER_REFUND_REASONS } from '../db/repository';
import type {
  InventoryProduct, OrderRefund, OrderRefundReason, ShopOrder, StockMove,
} from '../db/repository';

/** Shipped or delivered — money that has actually been collected. */
export const EARNED_STATUSES = new Set(['shipped', 'delivered']);

/**
 * The day frame 05a shipped, and therefore the first day a refund can carry a
 * reason.
 *
 * Printed on the screen beside the reason breakdown, because the alternative —
 * counting every older return as «другое» — invents a fact about an event
 * nobody recorded. There is nothing to backfill: no refund could be booked
 * before migration 051 created the table. Return moves older than this are
 * order cancellations, and they are counted as exactly that.
 */
export const REFUND_REASONS_SINCE = '2026-08-20';

/** «брак», not «defect» — this is read by a person, in Russian, in a CSV. */
export const REFUND_REASON_RU: Record<OrderRefundReason, string> = {
  defect: 'брак',
  not_suitable: 'не подошёл',
  changed_mind: 'передумала',
  not_delivered: 'не доставлен',
  other: 'другое',
};
/** Placed but not yet out of the door. Stock is reserved; nothing is collected. */
export const PROMISED_STATUSES = new Set(['new', 'confirmed']);

export interface MoneyBlock {
  /** Minor units. */
  earnedMinor: number;
  promisedMinor: number;
  /** Cancelled orders, at the value they would have been. */
  lostMinor: number;
  discountMinor: number;
  orders: number;
  /** Average of the EARNED orders only. Zero when there are none. */
  averageCheckMinor: number;
  /**
   * Money handed back in this window — frame 05a, migration 051.
   *
   * Bucketed by the date of the REFUND, not of the order it reverses: a July
   * комплект refunded in August is August's loss, which is the month the cash
   * actually left. Complete rather than a floor — refunds are read for the
   * whole window instead of as a newest-N slice, so this figure never carries
   * «не менее».
   *
   * Not a payment breakdown. WHERE the money went back to (Kaspi / наличные) is
   * not stored, for the same reason the split above it does not exist.
   */
  refundedMinor: number;
  /**
   * earned − refunded.
   *
   * Deliberately NOT clamped at zero. A month whose refunds exceed its own
   * sales is a real and alarming answer, and flooring it to 0 would draw that
   * month as merely empty.
   */
  earnedNetMinor: number;
}

export interface MarginBlock {
  /** Cost of the goods behind the earned revenue, where cost is recorded. */
  costMinor: number;
  /** Earned revenue for lines whose product cost IS known. */
  coveredRevenueMinor: number;
  marginMinor: number;
  /** 0..1 — how much of the earned revenue the margin is actually computed on. */
  coverage: number;
  /** Products sold in this window with no cost recorded. Names, for the note. */
  missingCost: string[];
}

export interface ReturnsBlock {
  /**
   * Units a CUSTOMER sent back, i.e. covered by a booked refund.
   *
   * This used to count cancellations too. Both write reason='return' with an
   * order id — cancelling an order puts its goods back on the shelf — so
   * «Возвратов, шт» and «Доля возвратов, %» were computed over orders that had
   * never been in revenue at all, divided by units sold. The rate was
   * meaningless in both directions: inflated by every cancelled order, and
   * blind to every real return, because until frame 05a there was no way to
   * record one. Refund-linked moves only, now (StockMove.refundId).
   */
  returnedUnits: number;
  /**
   * Units back on the shelf because an ORDER WAS CANCELLED.
   *
   * Reported beside the returns rather than folded into them or dropped: the
   * stock really did move, and the warehouse needs the number. It is just not
   * a return, and it is not in the rate.
   */
  cancelledUnits: number;
  /**
   * Return moves belonging to neither — no refund and no order.
   *
   * Nothing in the product writes one: the two writers of reason='return' are
   * cancellation (with an order) and a refund (with both). A row here means
   * somebody wrote to the ledger by hand, and it is surfaced rather than
   * quietly added to one of the two real buckets, where it would move a number
   * a person is held to.
   */
  otherReturnUnits: number;
  /** Refunds booked in the window. Not units — one refund can cover several. */
  refundCount: number;
  /**
   * How many refunds gave each reason.
   *
   * Only refunds booked from REFUND_REASONS_SINCE can appear here, because only
   * they have a reason. Older returns are not redistributed into «другое».
   */
  reasonCounts: Record<OrderRefundReason, number>;
  /** The date above, carried to the screen so it can say it rather than imply it. */
  reasonsRecordedSince: string;
  /** Units written off — breakage, loss, expiry. */
  writtenOffUnits: number;
  /** Units sold in the window, for a rate that means something. */
  soldUnits: number;
  /**
   * REFUNDED units ÷ sold, 0 when nothing was sold — and NULL when the stock
   * moves behind it do not cover the whole window.
   *
   * Cancellations are not in the numerator any more. See returnedUnits.
   *
   * The route reads a fixed number of the newest moves, and a sale writes one
   * per order line, so an older window can fall entirely off the end of that
   * slice. Every count in this block was then 0, this rate was 0 ÷ 0 = 0, and
   * the CSV printed «Доля возвратов, % — 0,0» for a February nobody had looked
   * at. That is not a low return rate, it is no data, and the two must not
   * render the same. Null means «неизвестно» and the screens print that word.
   */
  returnRate: number | null;
  /** What the write-offs cost us, where cost is known. */
  writeOffCostMinor: number;
  /** The individual events, newest first, for the table. */
  events: Array<{
    at: string; productName: string; color: string;
    units: number;
    /** The ledger's own word for the row. */
    reason: 'return' | 'writeoff';
    /**
     * What the row IS — the distinction `reason` cannot make on its own, and
     * the one the screen has to draw: «возврат» and «отмена заказа» are the
     * same ledger reason and two different events.
     */
    kind: 'refund' | 'cancel' | 'other' | 'writeoff';
    /**
     * Why she sent it back, for a refund whose refund row is in this window.
     *
     * Null means «не показана здесь», never «не указана»: a refund always has a
     * reason, but a move can be read in a window whose refund row was not.
     */
    refundReason: OrderRefundReason | null;
    note: string | null;
  }>;
}

export interface FinanceReport {
  from: string;
  to: string;
  money: MoneyBlock;
  margin: MarginBlock;
  returns: ReturnsBlock;
  /** Plan for the month, if one is set. */
  planMinor: number | null;
  /** earned ÷ plan, null when no plan is set. */
  planProgress: number | null;
  /**
   * What this report cannot say, in plain words. Rendered under the numbers
   * rather than kept in a comment — the person reading it is the one who needs
   * to know which figures to trust.
   */
  caveats: string[];
  /**
   * Whether the rows behind the figures actually reach back to `from`.
   *
   * The route reads the newest N orders and the newest M stock moves and then
   * asks for any window it likes. Ask for last February and the answer was
   * computed over rows that all post-date it — silently, with three confident
   * caveats on screen, none of them the true one.
   *
   * The mother's card already had the answer to this shape of problem
   * (`ordersTruncated`, routes/admin.ts): when the slice is full, SAY the
   * figures are a slice rather than presenting a partial total as the whole.
   */
  slice: {
    /** The orders behind «заработано», «обещано», «маржа» cover the window. */
    ordersComplete: boolean;
    /** The stock moves behind returns and write-offs cover the window. */
    movesComplete: boolean;
    /**
     * The refunds behind «Возвращено денег» were read at all.
     *
     * Unlike the two above this is not about a slice — the whole window is read
     * — it is about the read having FAILED. The route catches a repository
     * error so one broken table cannot black out the whole screen, and a
     * caught error left `refundedMinor: 0` looking exactly like a month with no
     * refunds. False, and false in the flattering direction. The screen prints
     * «неизвестно» when this is false.
     */
    refundsComplete: boolean;
    /** How many rows the caller asked for, for a message that names it. */
    ordersWindow: number | null;
    movesWindow: number | null;
  };
}

export interface FinanceInput {
  orders: ShopOrder[];
  products: InventoryProduct[];
  moves: StockMove[];
  /**
   * Refunds booked in the window — the whole window, not a slice.
   *
   * Optional so the pure tests and any older caller still compile; absent means
   * «ни одного», which is the truth for every period before frame 05a.
   */
  refunds?: OrderRefund[];
  /** The refunds read threw. Absent means it did not. */
  refundsUnavailable?: boolean;
  planMinor: number | null;
  /** Inclusive ISO date, YYYY-MM-DD. */
  from: string;
  /** Inclusive ISO date, YYYY-MM-DD. */
  to: string;
  /**
   * How many rows the caller asked its repository for, and whether it got that
   * many — i.e. whether there is very likely older data it did not fetch.
   *
   * Absent means "everything there is", which is what the pure tests pass and
   * what a caller reading the whole table would pass. A caller that reads a
   * window and does NOT say so gets a report that cannot know it is partial,
   * which is the bug: /admin/finance read the newest 1 000 orders and 2 000
   * stock moves and reported on any window at all.
   */
  ordersWindow?: number;
  ordersTruncated?: boolean;
  movesWindow?: number;
  movesTruncated?: boolean;
}

/**
 * Does the fetched slice reach back past the start of the window?
 *
 * A full slice does not by itself mean the report is partial — 1 000 orders
 * that all fall inside the window answer the question completely. What makes it
 * partial is a full slice whose OLDEST row is still newer than `from`: there is
 * then data before it that was never read, and it is exactly the data the
 * window asked about. A full slice that fetched nothing at all cannot cover
 * anything, so it is not complete either.
 */
function sliceCovers(dates: string[], truncated: boolean, from: string): boolean {
  if (!truncated) return true;
  if (dates.length === 0) return false;
  let oldest = dates[0];
  for (const d of dates) if (d < oldest) oldest = d;
  return oldest.slice(0, 10) <= from;
}

const inWindow = (iso: string, from: string, to: string) => {
  const d = (iso ?? '').slice(0, 10);
  return d >= from && d <= to;
};

export function buildFinanceReport(input: FinanceInput): FinanceReport {
  const { from, to } = input;
  // Decided before anything is counted, because it decides which of the
  // numbers below are answers and which are «неизвестно».
  const ordersComplete = sliceCovers(
    input.orders.map((o) => o.createdAt ?? ''), Boolean(input.ordersTruncated), from);
  const movesComplete = sliceCovers(
    input.moves.map((m) => m.at ?? ''), Boolean(input.movesTruncated), from);
  const orders = input.orders.filter((o) => inWindow(o.createdAt, from, to));
  const costByName = new Map<string, number | null>();
  for (const p of input.products) costByName.set(p.name, p.costMinor ?? null);

  // ---- Money ------------------------------------------------------------
  const earned = orders.filter((o) => EARNED_STATUSES.has(o.status));
  const promised = orders.filter((o) => PROMISED_STATUSES.has(o.status));
  const lost = orders.filter((o) => o.status === 'cancelled');

  const sum = (list: ShopOrder[]) => list.reduce((n, o) => n + o.totalMinor, 0);
  const earnedMinor = sum(earned);

  // Refunds are bucketed by their OWN date — the month the cash left — and are
  // read whole rather than sliced, so this is never a floor.
  const refunds = (input.refunds ?? []).filter((r) => inWindow(r.at, from, to));
  const refundedMinor = refunds.reduce((n, r) => n + r.amountMinor, 0);

  const money: MoneyBlock = {
    earnedMinor,
    refundedMinor,
    // Not clamped: refunds outrunning a month's own sales is a real answer.
    earnedNetMinor: earnedMinor - refundedMinor,
    promisedMinor: sum(promised),
    lostMinor: sum(lost),
    discountMinor: orders.reduce((n, o) => n + (o.discountMinor ?? 0), 0),
    orders: orders.length,
    // Over EARNED orders only. Including promises would move the average every
    // time somebody places an order they later cancel.
    averageCheckMinor: earned.length ? Math.round(earnedMinor / earned.length) : 0,
  };

  // ---- Margin -----------------------------------------------------------
  let costMinor = 0;
  let coveredRevenueMinor = 0;
  const missingCost = new Set<string>();
  for (const o of earned) {
    for (const line of o.items) {
      const unitCost = costByName.get(line.productName);
      if (unitCost == null) {
        missingCost.add(line.productName);
        continue;
      }
      costMinor += unitCost * line.qty;
      coveredRevenueMinor += line.unitPriceMinor * line.qty;
    }
  }
  const margin: MarginBlock = {
    costMinor,
    coveredRevenueMinor,
    marginMinor: coveredRevenueMinor - costMinor,
    // Against the revenue we could price, not against every order: a coverage
    // of 1 must mean "every line had a cost", not "there were no orders".
    coverage: earnedMinor > 0 ? Math.min(1, coveredRevenueMinor / earnedMinor) : 0,
    missingCost: [...missingCost].sort(),
  };

  // ---- Returns and write-offs ------------------------------------------
  const moves = input.moves.filter((m) => inWindow(m.at, from, to));
  const writeoffs = moves.filter((m) => m.reason === 'writeoff');
  const sales = moves.filter((m) => m.reason === 'sale');

  /**
   * Which of the three things a reason='return' row actually is.
   *
   * A refund carries the refund it belongs to; a cancellation carries only the
   * order it un-did. Everything below hangs off this one function, because the
   * bug being fixed is precisely that the report had no way to ask.
   */
  const kindOf = (m: StockMove): 'refund' | 'cancel' | 'other' =>
    (m.refundId != null ? 'refund' : m.orderId ? 'cancel' : 'other');
  const returns = moves.filter((m) => m.reason === 'return');
  const refundMoves = returns.filter((m) => kindOf(m) === 'refund');
  const cancelMoves = returns.filter((m) => kindOf(m) === 'cancel');
  const orphanMoves = returns.filter((m) => kindOf(m) === 'other');
  /** The reason a refund gave, for the moves it wrote. */
  const reasonByRefund = new Map<number, OrderRefundReason>();
  for (const r of refunds) reasonByRefund.set(r.id, r.reason);

  // Deltas are signed: a sale is negative, a return positive, a write-off
  // negative. Absolute values here, because these are counts of things that
  // happened rather than movements of a level.
  const units = (list: StockMove[]) => list.reduce((n, m) => n + Math.abs(m.delta), 0);
  const returnedUnits = units(refundMoves);
  const soldUnits = units(sales);

  const reasonCounts = Object.fromEntries(
    ORDER_REFUND_REASONS.map((r) => [r, 0]),
  ) as Record<OrderRefundReason, number>;
  for (const r of refunds) reasonCounts[r.reason] += 1;

  let writeOffCostMinor = 0;
  for (const m of writeoffs) {
    const c = costByName.get(m.productName);
    if (c != null) writeOffCostMinor += c * Math.abs(m.delta);
  }

  const returnsBlock: ReturnsBlock = {
    returnedUnits,
    cancelledUnits: units(cancelMoves),
    otherReturnUnits: units(orphanMoves),
    refundCount: refunds.length,
    reasonCounts,
    reasonsRecordedSince: REFUND_REASONS_SINCE,
    writtenOffUnits: units(writeoffs),
    soldUnits,
    // Unknown, not zero, when the moves behind it do not reach the window.
    // «Возвратов было 0 %» and «мы не смотрели» are different sentences, and
    // the first one is the one that gets quoted.
    returnRate: !movesComplete ? null : soldUnits > 0 ? returnedUnits / soldUnits : 0,
    writeOffCostMinor,
    events: [...returns, ...writeoffs]
      .sort((a, b) => b.at.localeCompare(a.at))
      .map((m) => ({
        at: m.at, productName: m.productName, color: m.color,
        units: Math.abs(m.delta),
        reason: m.reason as 'return' | 'writeoff',
        kind: m.reason === 'writeoff' ? ('writeoff' as const) : kindOf(m),
        refundReason: m.refundId != null ? reasonByRefund.get(m.refundId) ?? null : null,
        note: m.note,
      })),
  };

  // ---- What this cannot say --------------------------------------------
  const caveats: string[] = [
    // Stated on every report, because its absence is structural rather than a
    // gap somebody can fill in by tidying data.
    'Разбивка по способу оплаты (Kaspi / наличные) недоступна: в заказе не хранится способ оплаты.',
  ];
  if (margin.missingCost.length) {
    caveats.push(
      `Себестоимость не указана у: ${margin.missingCost.join(', ')}. ` +
      `Маржа посчитана по ${Math.round(margin.coverage * 100)}% выручки.`);
  }
  if (money.promisedMinor > 0) {
    caveats.push(
      'Заказы в статусах «новый» и «подтверждён» в выручку не входят — это обещание, а не деньги.');
  }
  // Only when there IS money to say it about: a permanent line about an absent
  // column trains the reader to skip the block it lives in.
  if (money.refundedMinor > 0) {
    caveats.push(
      'Куда именно вернули деньги — на Kaspi или наличными — в базе не хранится: ' +
      'у заказа нет способа оплаты. Записаны сумма, причина, кто оформил и когда.');
  }
  // Said whenever the window reaches back before refunds could be recorded, so
  // «возвратов не было» cannot be read off a period in which recording one was
  // impossible.
  if (from < REFUND_REASONS_SINCE) {
    caveats.push(
      `Причины возвратов записываются с ${REFUND_REASONS_SINCE}. До этой даты возврат в ` +
      'системе оформить было нельзя: товар возвращали отменой заказа или списанием, ' +
      'и причина у них не записана — задним числом она не проставляется.');
  }
  if (returnsBlock.otherReturnUnits > 0) {
    caveats.push(
      `Возвратов на склад без заказа и без оформленного возврата: ` +
      `${returnsBlock.otherReturnUnits} шт. Их не пишет ни одна кнопка панели — ` +
      'строки заведены напрямую в базе, и в долю возвратов они не входят.');
  }
  if (input.refundsUnavailable) {
    caveats.push(
      'Возвраты покупателям НЕ прочитались: «Возвращено денег» и причины возвратов ' +
      'на этом экране неизвестны, а не равны нулю. Выручка ниже возвратов не учитывает. ' +
      'Обновите страницу; если повторяется — скажите разработчику.');
  }
  // First in the list would be better still, but the payment-method line is
  // structural and always present; these two are conditional and rare, and a
  // reader who sees them must not be able to mistake them for the usual pair.
  if (!ordersComplete) {
    caveats.push(
      `Прочитаны только последние ${input.ordersWindow ?? 0} заказов, и они не покрывают начало ` +
      'периода: выручка, обещано, отмены, скидки и маржа — НЕ ПОЛНЫЕ, это нижняя граница. ' +
      'Возьмите период короче.');
  }
  if (!movesComplete) {
    caveats.push(
      `Прочитаны только последние ${input.movesWindow ?? 0} движений склада, и они не покрывают ` +
      'начало периода: возвраты, списания и продажи в штуках — НЕ ПОЛНЫЕ, а доля возвратов ' +
      'неизвестна. Возьмите период короче.');
  }

  return {
    from, to, money, margin,
    returns: returnsBlock,
    planMinor: input.planMinor,
    planProgress: input.planMinor && input.planMinor > 0
      ? money.earnedMinor / input.planMinor
      : null,
    caveats,
    slice: {
      ordersComplete,
      movesComplete,
      refundsComplete: !input.refundsUnavailable,
      ordersWindow: input.ordersWindow ?? null,
      movesWindow: input.movesWindow ?? null,
    },
  };
}

/**
 * Frame 05b — the report as CSV.
 *
 * Semicolon-separated and BOM-prefixed: Excel in a Russian locale splits on
 * semicolons, and without the BOM it renders Cyrillic as mojibake. Both are
 * about the file opening correctly on the machine it will actually be opened
 * on, which is the only test that matters for an export.
 */
export function financeCsv(r: FinanceReport): string {
  const money = (minor: number) => (minor / 100).toFixed(2).replace('.', ',');
  /**
   * A floor, marked as one.
   *
   * A cell is read on its own, long after the caveat rows have been scrolled
   * past or deleted. «не менее 12» survives being pasted into a message;
   * «12» computed over an unknown fraction of the period does not.
   */
  const atLeast = (v: string, partial: boolean) => (partial ? `не менее ${v}` : v);
  const rows: string[][] = [
    ['Показатель', 'Значение'],
    ['Период', `${r.from} — ${r.to}`],
    ['Заработано, ₸', atLeast(money(r.money.earnedMinor), !r.slice.ordersComplete)],
    ['Обещано (не оплачено), ₸', atLeast(money(r.money.promisedMinor), !r.slice.ordersComplete)],
    ['Потеряно на отменах, ₸', atLeast(money(r.money.lostMinor), !r.slice.ordersComplete)],
    ['Скидки, ₸', atLeast(money(r.money.discountMinor), !r.slice.ordersComplete)],
    ['Заказов', atLeast(String(r.money.orders), !r.slice.ordersComplete)],
    ['Средний чек, ₸', money(r.money.averageCheckMinor)],
    ['Себестоимость, ₸', atLeast(money(r.margin.costMinor), !r.slice.ordersComplete)],
    ['Маржа, ₸', atLeast(money(r.margin.marginMinor), !r.slice.ordersComplete)],
    ['Маржа посчитана по, % выручки', String(Math.round(r.margin.coverage * 100))],
    // Money back, before the counts: it is the figure this frame exists for,
    // and it is complete rather than a floor — refunds are read whole.
    ['Возвращено денег, ₸', r.slice.refundsComplete
      ? money(r.money.refundedMinor)
      : 'неизвестно'],
    ['Выручка за вычетом возвратов, ₸', r.slice.refundsComplete
      ? atLeast(money(r.money.earnedNetMinor), !r.slice.ordersComplete)
      : 'неизвестно'],
    ['Возвратов оформлено', r.slice.refundsComplete ? String(r.returns.refundCount) : 'неизвестно'],
    // Split, because they were one number and should never have been. A
    // cancelled order's goods coming back is not a customer returning one.
    ['Возвратов от покупателей, шт',
      atLeast(String(r.returns.returnedUnits), !r.slice.movesComplete)],
    ['Возвращено на склад при отмене заказов, шт',
      atLeast(String(r.returns.cancelledUnits), !r.slice.movesComplete)],
    ['Списано, шт', atLeast(String(r.returns.writtenOffUnits), !r.slice.movesComplete)],
    ['Списано на сумму, ₸', atLeast(money(r.returns.writeOffCostMinor), !r.slice.movesComplete)],
    // «неизвестно», never 0,0. A fabricated zero in a spreadsheet outlives
    // every caveat around it: the cell gets pasted into a message on its own.
    ['Доля возвратов, %', r.returns.returnRate == null
      ? 'неизвестно'
      : (r.returns.returnRate * 100).toFixed(1).replace('.', ',')],
  ];
  // The reasons, one row each and only where there is something to say. A row
  // of zeroes for every reason reads as a survey nobody answered.
  for (const reason of ORDER_REFUND_REASONS) {
    const n = r.returns.reasonCounts[reason];
    if (n > 0) rows.push([`Причина возврата · ${REFUND_REASON_RU[reason]}`, String(n)]);
  }
  if (r.returns.otherReturnUnits > 0) {
    rows.push(['Возвраты без заказа и без оформления, шт', String(r.returns.otherReturnUnits)]);
  }
  // The caveats travel WITH the file. A number pasted into a message loses its
  // footnote otherwise, and the margin one is load-bearing.
  for (const c of r.caveats) rows.push(['Оговорка', c]);

  const esc = (v: string) => (/[";\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  return '﻿' + rows.map((r2) => r2.map(esc).join(';')).join('\r\n') + '\r\n';
}
