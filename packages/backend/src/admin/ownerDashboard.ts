/**
 * Frame 00 — «Дашборд владельца».
 *
 * docs/CLAUDE-admin-design.md: «Четыре ряда: (1) пять метрик денег — выручка к
 * плану, чистая прибыль, заказы, деньги в товаре, кассовый разрыв; (2) «Что
 * горит» … (3) «Кто с нами» … (4) тёмная карточка «Решение недели». Никакой
 * кнопки «Новый заказ».»
 *
 * The spec's last clause is the whole design: this is not a screen for DOING
 * anything. The owner has an operator for that. It answers one question —
 * "is the business all right, and if not, what should I decide this week" —
 * and every element on it earns its place by helping answer that or is cut.
 *
 * ON HONESTY. Three of the five money figures are exact and two are estimates,
 * and the difference is stated rather than smoothed over:
 *
 *   * Revenue, orders and money-in-stock come straight from the ledger.
 *   * NET PROFIT values sold units at each product's CURRENT cost, because no
 *     cost is stored on the order line at the time of sale. If cost has moved
 *     since, so has this number. `costCoverage` says how much of the revenue
 *     had a known cost behind it, so a figure computed over a third of the
 *     catalogue cannot be read as a fact.
 *   * The CASH GAP is money already sunk into stock that has not sold, less
 *     money customers have committed and not yet paid. It is a liquidity
 *     signal, not an accounting balance.
 *
 * PURE: orders, products and settings in; numbers out. No repository, no clock
 * beyond the instant it is given.
 */

import type { InventoryProduct, ShopOrder } from '../db/repository';

/** Statuses whose money is EARNED — the goods left the building. */
const EARNED = new Set(['shipped', 'delivered']);
/** Statuses whose money is PROMISED — committed, not yet collected. */
const PROMISED = new Set(['new', 'confirmed']);

export interface OwnerMoney {
  /** Earned this calendar month, in minor units. */
  revenueMinor: number;
  /** The month's target, from settings. Null when nobody has set one. */
  planMinor: number | null;
  /** revenue / plan, 0..n. Null without a plan — NOT 0, which reads as failure. */
  planPct: number | null;
  /** Revenue less the cost of what was sold. See the honesty note above. */
  netProfitMinor: number;
  /**
   * Share of this month's revenue whose product cost is known, 0..1.
   *
   * The number that decides whether netProfitMinor may be believed. A profit
   * computed over a third of the catalogue is not a profit, and the screen
   * says so instead of printing it in the same weight as the rest.
   */
  costCoverage: number;
  /** Orders earned this month. */
  orders: number;
  /** What the shelf cost us — cash already spent and not yet recovered. */
  moneyInStockMinor: number;
  /**
   * Cash sunk into unsold stock, less what customers have committed.
   *
   * Positive means more is tied up in goods than is on its way in. Not an
   * accounting figure: it is the question «хватит ли денег до следующей
   * поставки» asked of the two numbers that actually answer it.
   */
  cashGapMinor: number;
  /** Money promised but not collected — the other half of the gap. */
  pipelineMinor: number;
}

/** One day of the 14-day revenue chart. */
export interface RevenueDay {
  /** YYYY-MM-DD, in UTC — the same day boundary the rest of the panel uses. */
  day: string;
  revenueMinor: number;
  orders: number;
}

/** «Откуда выручка» — which products the month's money came from. */
export interface RevenueSource {
  product: string;
  revenueMinor: number;
  units: number;
  /** Share of the month's revenue, 0..1. */
  share: number;
}

/** One thing that is on fire, with what to do about it. */
export interface Burning {
  /** Stable key, so the panel can style and test one without matching Russian. */
  key: string;
  /** What is wrong, in one line. */
  title: string;
  /** How bad. `crit` is money or safety; `warn` is something slipping. */
  level: 'crit' | 'warn';
  /** The count behind it, when there is one. */
  count?: number;
}

/** The dark card: one decision, three ways to take it. */
export interface Decision {
  key: string;
  /** The situation, stated as the question it forces. */
  question: string;
  /** Why it is being asked THIS week — the number that raised it. */
  because: string;
  /** Three courses of action. Never fewer: two options is a yes/no in disguise. */
  options: string[];
}

export interface OwnerDashboard {
  money: OwnerMoney;
  revenue14d: RevenueDay[];
  sources: RevenueSource[];
  burning: Burning[];
  decision: Decision | null;
}

/** UTC calendar day of an ISO timestamp. */
function dayOf(iso: string): string {
  return iso.slice(0, 10);
}

/** First instant of the month containing [now], UTC. */
function monthStart(now: Date): number {
  return Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
}

export interface OwnerInput {
  orders: ShopOrder[];
  products: InventoryProduct[];
  /** Monthly revenue target in minor units, from settings. */
  planMinor: number | null;
  /** Signals from elsewhere on the panel, for «Что горит». */
  signals: {
    /** Queues past their SLA, by queue name. */
    overdue: string[];
    /** Product ids at or below their low-stock threshold. */
    lowStock: string[];
    /** Medical cards published without a clinician's signature. */
    unreviewedMedical: number;
    /** Paired devices missing from the registry — the grey-market count. */
    unregisteredDevices: number;
    /** Protected reads recorded with no reason given. */
    accessWithoutReason: number;
    /** Course access granted to people who have never pressed play. */
    courseNeverStarted: number;
  };
}

export function buildOwnerDashboard(input: OwnerInput, now: Date): OwnerDashboard {
  const { orders, products, planMinor, signals } = input;
  const since = monthStart(now);

  // Cost per product NAME, because that is all an order line carries. Matching
  // on name is imperfect — a renamed product loses its history — and the
  // coverage figure below is what makes that visible rather than silent.
  const costByName = new Map<string, number>();
  for (const p of products) {
    if (p.costMinor != null) costByName.set(p.name, p.costMinor);
  }

  let revenueMinor = 0;
  let orderCount = 0;
  let cogsMinor = 0;
  let revenueWithKnownCost = 0;
  let pipelineMinor = 0;
  const byProduct = new Map<string, { revenueMinor: number; units: number }>();

  for (const o of orders) {
    const t = Date.parse(o.createdAt);
    if (!Number.isFinite(t)) continue;

    if (PROMISED.has(o.status)) {
      // Pipeline is NOT limited to this month: money committed in March and
      // still unshipped in April is exactly the money the cash gap is about.
      pipelineMinor += o.totalMinor;
    }

    if (t < since || !EARNED.has(o.status)) continue;
    revenueMinor += o.totalMinor;
    orderCount++;

    for (const line of o.items) {
      const lineRevenue = line.unitPriceMinor * line.qty;
      const agg = byProduct.get(line.productName) ?? { revenueMinor: 0, units: 0 };
      agg.revenueMinor += lineRevenue;
      agg.units += line.qty;
      byProduct.set(line.productName, agg);

      const cost = costByName.get(line.productName);
      if (cost != null) {
        cogsMinor += cost * line.qty;
        revenueWithKnownCost += lineRevenue;
      }
    }
  }

  // Over LINE revenue, not order totals: a discount lives on the order and not
  // on its lines, so dividing one by the other would drift past 1.
  const lineRevenue = [...byProduct.values()].reduce((s, v) => s + v.revenueMinor, 0);
  const costCoverage = lineRevenue > 0 ? revenueWithKnownCost / lineRevenue : 0;

  const moneyInStockMinor = products.reduce(
    (s, p) => s + (p.costMinor != null && p.kind !== 'bundle' ? p.costMinor * Math.max(0, p.stock) : 0),
    0,
  );

  // Fourteen days INCLUDING today, oldest first, with the empty days present.
  // Dropping a day with no sales would draw a chart that hides exactly the
  // thing it is read for.
  const revenue14d: RevenueDay[] = [];
  const dayIndex = new Map<string, RevenueDay>();
  for (let i = 13; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 86_400_000);
    const day = d.toISOString().slice(0, 10);
    const row = { day, revenueMinor: 0, orders: 0 };
    revenue14d.push(row);
    dayIndex.set(day, row);
  }
  for (const o of orders) {
    if (!EARNED.has(o.status)) continue;
    const row = dayIndex.get(dayOf(o.createdAt));
    if (!row) continue;
    row.revenueMinor += o.totalMinor;
    row.orders++;
  }

  const sources: RevenueSource[] = [...byProduct.entries()]
    .map(([product, v]) => ({
      product,
      revenueMinor: v.revenueMinor,
      units: v.units,
      share: lineRevenue > 0 ? v.revenueMinor / lineRevenue : 0,
    }))
    .sort((a, b) => b.revenueMinor - a.revenueMinor);

  return {
    money: {
      revenueMinor,
      planMinor,
      // Null rather than 0 without a plan: 0 % renders as a failed month, and
      // "nobody set a target" is a different thing from "we missed it".
      planPct: planMinor && planMinor > 0 ? revenueMinor / planMinor : null,
      netProfitMinor: revenueMinor - cogsMinor,
      costCoverage,
      orders: orderCount,
      moneyInStockMinor,
      cashGapMinor: moneyInStockMinor - pipelineMinor,
      pipelineMinor,
    },
    revenue14d,
    sources,
    burning: whatBurns(signals),
    decision: decisionOfTheWeek({ signals, revenueMinor, planMinor, costCoverage, sources }),
  };
}

/**
 * «Что горит» — what needs somebody today, worst first.
 *
 * Deliberately short. A list of fifteen things is a list nobody reads, and the
 * counter in the header is a promise that each line is worth the interruption.
 */
export function whatBurns(s: OwnerInput['signals']): Burning[] {
  const out: Burning[] = [];

  if (s.overdue.length > 0) {
    // A person has been waiting past the time we said we would answer. Nothing
    // else on this list is a person waiting.
    out.push({
      key: 'overdue',
      title: `Очереди просрочены: ${s.overdue.join(', ')}`,
      level: 'crit',
      count: s.overdue.length,
    });
  }
  if (s.unreviewedMedical > 0) {
    out.push({
      key: 'unreviewed_medical',
      title: 'Медицинские карточки опубликованы без подписи врача',
      level: 'crit',
      count: s.unreviewedMedical,
    });
  }
  if (s.accessWithoutReason > 0) {
    out.push({
      key: 'access_without_reason',
      title: 'Просмотры защищённых данных без основания',
      level: 'crit',
      count: s.accessWithoutReason,
    });
  }
  if (s.lowStock.length > 0) {
    out.push({
      key: 'low_stock',
      title: 'Товары заканчиваются',
      level: 'warn',
      count: s.lowStock.length,
    });
  }
  if (s.unregisteredDevices > 0) {
    out.push({
      key: 'unregistered_devices',
      title: 'Устройства не из нашего реестра',
      level: 'warn',
      count: s.unregisteredDevices,
    });
  }
  if (s.courseNeverStarted > 0) {
    out.push({
      key: 'course_never_started',
      title: 'Купили курс и ни разу не открыли',
      level: 'warn',
      count: s.courseNeverStarted,
    });
  }
  return out;
}

/**
 * «Решение недели» — the one question worth an owner's attention, with three
 * ways to answer it.
 *
 * One decision, not a list. The card is dark and alone at the bottom of the
 * screen because its whole job is to be the last thing read and the only thing
 * carried out of the room.
 *
 * Chosen by severity, and it returns null when nothing qualifies — a card that
 * manufactures a decision every week teaches its reader to ignore it.
 */
export function decisionOfTheWeek(ctx: {
  signals: OwnerInput['signals'];
  revenueMinor: number;
  planMinor: number | null;
  costCoverage: number;
  sources: RevenueSource[];
}): Decision | null {
  const { signals, revenueMinor, planMinor, costCoverage, sources } = ctx;

  if (signals.unreviewedMedical > 0) {
    return {
      key: 'medical_review',
      question: 'Кто подписывает медицинские тексты, пока врача нет?',
      because: `${signals.unreviewedMedical} карточек опубликовано без подписи. Это советы беременным.`,
      options: [
        'Снять их с публикации до проверки',
        'Оплатить врачу разовую вычитку всей очереди',
        'Взять врача на part-time с фиксированным SLA',
      ],
    };
  }

  if (planMinor && planMinor > 0 && revenueMinor < planMinor * 0.6) {
    const top = sources[0];
    return {
      key: 'behind_plan',
      question: 'План месяца не закрывается. Что двигаем?',
      because: top
        ? `Выручка ${Math.round((revenueMinor / planMinor) * 100)} % плана; ` +
          `${Math.round(top.share * 100)} % её даёт «${top.product}».`
        : `Выручка ${Math.round((revenueMinor / planMinor) * 100)} % плана, продаж почти нет.`,
      options: [
        'Вложиться в то, что уже продаётся',
        'Снизить план — он был поставлен не по данным',
        'Проверить, где отваливаются заявки, прежде чем тратить на рекламу',
      ],
    };
  }

  if (signals.courseNeverStarted > 0) {
    return {
      key: 'course_unused',
      question: 'Курс купили и не смотрят. Он держит цену комплекта?',
      because: `${signals.courseNeverStarted} мам с доступом ни разу не открыли ни одного урока.`,
      options: [
        'Написать им — узнать, что помешало',
        'Первый урок открывать автоматически в день покупки',
        'Признать, что курс не продаёт комплект, и убрать его из цены',
      ],
    };
  }

  // Cost coverage last: it makes the profit figure unreliable rather than the
  // business unwell, so it only surfaces when nothing worse is happening.
  if (costCoverage < 0.7) {
    return {
      key: 'cost_coverage',
      question: 'Себестоимость известна не по всем товарам. Считаем прибыль вслепую?',
      because: `Только ${Math.round(costCoverage * 100)} % выручки имеет известную себестоимость.`,
      options: [
        'Проставить себестоимость по приёмкам за месяц',
        'Требовать цену закупки при каждой приёмке',
        'Показывать прибыль только по товарам с известной ценой',
      ],
    };
  }

  return null;
}
