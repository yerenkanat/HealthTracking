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

import type { InventoryProduct, ShopOrder, StockMove } from '../db/repository';

/** Shipped or delivered — money that has actually been collected. */
export const EARNED_STATUSES = new Set(['shipped', 'delivered']);
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
  /** Units that came back. */
  returnedUnits: number;
  /** Units written off — breakage, loss, expiry. */
  writtenOffUnits: number;
  /** Units sold in the window, for a rate that means something. */
  soldUnits: number;
  /**
   * returned ÷ sold, 0 when nothing was sold — and NULL when the stock moves
   * behind it do not cover the whole window.
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
    units: number; reason: 'return' | 'writeoff'; note: string | null;
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
    /** How many rows the caller asked for, for a message that names it. */
    ordersWindow: number | null;
    movesWindow: number | null;
  };
}

export interface FinanceInput {
  orders: ShopOrder[];
  products: InventoryProduct[];
  moves: StockMove[];
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

  const money: MoneyBlock = {
    earnedMinor,
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
  const returns = moves.filter((m) => m.reason === 'return');
  const writeoffs = moves.filter((m) => m.reason === 'writeoff');
  const sales = moves.filter((m) => m.reason === 'sale');

  // Deltas are signed: a sale is negative, a return positive, a write-off
  // negative. Absolute values here, because these are counts of things that
  // happened rather than movements of a level.
  const units = (list: StockMove[]) => list.reduce((n, m) => n + Math.abs(m.delta), 0);
  const returnedUnits = units(returns);
  const soldUnits = units(sales);

  let writeOffCostMinor = 0;
  for (const m of writeoffs) {
    const c = costByName.get(m.productName);
    if (c != null) writeOffCostMinor += c * Math.abs(m.delta);
  }

  const returnsBlock: ReturnsBlock = {
    returnedUnits,
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
    ['Возвратов, шт', atLeast(String(r.returns.returnedUnits), !r.slice.movesComplete)],
    ['Списано, шт', atLeast(String(r.returns.writtenOffUnits), !r.slice.movesComplete)],
    ['Списано на сумму, ₸', atLeast(money(r.returns.writeOffCostMinor), !r.slice.movesComplete)],
    // «неизвестно», never 0,0. A fabricated zero in a spreadsheet outlives
    // every caveat around it: the cell gets pasted into a message on its own.
    ['Доля возвратов, %', r.returns.returnRate == null
      ? 'неизвестно'
      : (r.returns.returnRate * 100).toFixed(1).replace('.', ',')],
  ];
  // The caveats travel WITH the file. A number pasted into a message loses its
  // footnote otherwise, and the margin one is load-bearing.
  for (const c of r.caveats) rows.push(['Оговорка', c]);

  const esc = (v: string) => (/[";\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
  return '﻿' + rows.map((r2) => r2.map(esc).join(';')).join('\r\n') + '\r\n';
}
