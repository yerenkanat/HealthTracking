/**
 * Frame 09a — «Карточка мамы», the right-hand column: «этап, курс, приложение».
 *
 * The card already showed her children and her devices. Three things the spec
 * asks for were absent, and all three were ALREADY IN THE DATABASE — her
 * orders, whether the course is open to her, and which stage she is at. An
 * operator answering «где мой заказ» had to leave the card, find the orders
 * tab, and search by phone.
 *
 * ON STAGE. Deliberately the SAME vocabulary as a product's stage (migration
 * 033), because the two are compared: «этот товар для этапа "новорождённый", а
 * она на "беременность"» is only a sentence if both words come from one list.
 * Derived here rather than stored, because it changes by itself as a due date
 * passes and a child has a birthday — a stored copy would be wrong within
 * weeks and nobody would know which screen to believe.
 *
 * PURE: a profile, her children, her orders and her course rows in; the card's
 * right-hand column out.
 */

import type { ProductStage } from '../db/repository';

/** One of her orders, as the shop stores it. */
export interface MotherCardOrder {
  id: string;
  status: string;
  totalMinor: number;
  createdAt: string;
  /** What was in it. Absent is "we did not load the lines", not "it was empty". */
  items?: Array<{ productName: string; qty: number }>;
}

export interface MotherCardInput {
  dueDate: string | null;
  children: Array<{ name: string; dateOfBirth: string | null }>;
  /** Her orders, in any order — this module sorts them. */
  orders: MotherCardOrder[];
  courseUnlocked: boolean;
  /** One row per lesson she has opened. */
  courseProgress: Array<{ completed: boolean; updatedAt?: string }>;
  /** ISO instant, injected so the stage is testable. */
  now: string;
  /**
   * The shop could not be read. `orders` is then empty because we FAILED, not
   * because she has none — and the two must never render as the same sentence
   * to an operator on the phone with a woman holding her Kaspi receipt.
   */
  ordersUnavailable?: boolean;
  /** Same, for the entitlement and the progress rows. */
  courseUnavailable?: boolean;
  /**
   * How many of her orders were fetched at most. The counts below are computed
   * over that window and nothing else, so the card has to be able to say so.
   */
  ordersWindow?: number;
  /** The window came back full — older orders exist and are NOT in the counts. */
  ordersTruncated?: boolean;
}

/**
 * One order as the card shows it.
 *
 * «Где мой заказ» is answered with a date, a status and what was in it — an
 * operator who has to ask the customer "which order?" has already lost the
 * call, so the lines travel with the row.
 */
export interface MotherCardOrderRow {
  id: string;
  status: string;
  createdAt: string;
  totalMinor: number;
  items: Array<{ productName: string; qty: number }>;
}

export interface MotherCard {
  stage: ProductStage;
  /** Why the stage says what it does — a derived value must show its working. */
  stageReason: string;
  orders: {
    total: number;
    /** Placed and not yet delivered or cancelled. */
    open: number;
    /**
     * Money actually collected: shipped + delivered only.
     *
     * These are cash-on-delivery orders — nothing is paid until the parcel is
     * handed over, which is exactly why setShopOrderStatus grants the course
     * on shipped/delivered and not on `new`, and why the dashboard's revenue
     * sums the same two statuses. A `new` order is a promise that may never be
     * collected; counting it here quotes 39 000 ₸ «потрачено» at a customer
     * who has paid nothing.
     */
    spentMinor: number;
    /** Placed and not yet collected: new + confirmed. Owed, not spent. */
    pendingMinor: number;
    lastAt: string | null;
    lastStatus: string | null;
    /**
     * The newest OPEN order — the one «заказ в работе» is actually about.
     *
     * `lastStatus` is the newest order overall, which may be a delivered one
     * sitting on top of an unshipped June order. Pairing that status with the
     * open COUNT sent an operator looking for a parcel that never went out.
     */
    openLastAt: string | null;
    openLastStatus: string | null;
    /** Newest first, capped — enough to answer «где мой заказ» on the card. */
    recent: MotherCardOrderRow[];
    /** The shop could not be read: every number above is unknown, not zero. */
    unavailable: boolean;
    /** Older orders exist beyond `window` and are in none of these figures. */
    truncated: boolean;
    /** The size of the window the figures were computed over, when capped. */
    window: number | null;
  };
  course: {
    unlocked: boolean;
    started: number;
    completed: number;
    /** When she last moved in it, or null if she never has. */
    lastAt: string | null;
    /**
     * Access granted and never used. The one number on this block worth
     * acting on: she paid for a course she has not opened.
     */
    neverStarted: boolean;
    /** The course rows could not be read: `unlocked:false` is not an answer. */
    unavailable: boolean;
  };
}

/** How many of her orders the card carries. Older ones stay in the orders tab. */
const RECENT_ORDERS = 5;

const DAY = 86_400_000;

/**
 * Whole months between two dates, floored, never negative.
 *
 * UTC getters throughout, deliberately. A birth date arrives as `2026-03-08`,
 * which JavaScript parses as UTC midnight; reading it back with the LOCAL
 * getters gives 7 March in any negative-offset timezone, so the same child was
 * a month older on a server in one place than in another and the stage flipped
 * with the deployment region. The answer must not depend on where the process
 * happens to be running.
 */
export function monthsBetween(fromIso: string, toIso: string): number {
  const a = new Date(fromIso);
  const b = new Date(toIso);
  if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) return 0;
  let m = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + (b.getUTCMonth() - a.getUTCMonth());
  if (b.getUTCDate() < a.getUTCDate()) m--;
  return Math.max(0, m);
}

/**
 * Which stage she is at.
 *
 * Pregnancy wins over a child, because a mother expecting her second is being
 * sold maternity things, not toddler things. The youngest child decides the
 * rest — she has whatever the youngest needs, and the older ones' needs are
 * already met.
 */
export function motherStage(
  input: Pick<MotherCardInput, 'dueDate' | 'children' | 'now'>,
): { stage: ProductStage; reason: string } {
  const now = new Date(input.now).getTime();

  if (input.dueDate) {
    const due = new Date(input.dueDate).getTime();
    // A due date a fortnight past is still pregnancy: babies are late, and
    // flipping her to «новорождённый» on the due date itself would be a guess
    // dressed as a fact.
    if (!Number.isNaN(due) && due > now - 14 * DAY) {
      // Said out loud when the date is behind us, because «срок родов
      // 2026-07-30» beside today's 2026-08-08 otherwise reads as stale data
      // rather than as the deliberate fortnight of grace.
      const overdue = due <= now;
      return {
        stage: 'pregnancy',
        reason: overdue
          ? `срок родов ${input.dueDate} — уже прошёл, но менее двух недель назад`
          : `срок родов ${input.dueDate}`,
      };
    }
  }

  const withDob = input.children.filter((c) => c.dateOfBirth);
  if (withDob.length === 0) {
    // Children with no birth date tell us nothing about the stage, and no
    // children at all is a real answer rather than a missing one.
    return {
      stage: input.children.length ? 'any' : 'planning',
      reason: input.children.length
        ? 'у детей не указана дата рождения'
        : 'нет детей и не указан срок родов',
    };
  }

  const youngest = withDob
    .map((c) => ({ name: c.name, months: monthsBetween(c.dateOfBirth!, input.now) }))
    .sort((a, b) => a.months - b.months)[0];

  const stage: ProductStage =
    youngest.months < 2 ? 'newborn'
    : youngest.months < 12 ? 'infant'
    : youngest.months < 36 ? 'toddler'
    : 'any';

  return {
    stage,
    reason: `младшему ребёнку (${youngest.name}) ${youngest.months} мес.`,
  };
}

/** Neither delivered nor cancelled — something is still owed to her. */
const OPEN_STATUSES = new Set(['new', 'confirmed', 'shipped']);

export function buildMotherCard(input: MotherCardInput): MotherCard {
  const { stage, reason } = motherStage(input);
  const orders = [...input.orders].sort((a, b) => b.createdAt.localeCompare(a.createdAt));

  const started = input.courseProgress.length;
  // The newest `updatedAt` across her progress rows. Sorted rather than
  // Math.max'd on parsed dates so a row with no timestamp — the shape the type
  // allows — cannot turn the answer into NaN.
  const lastAt = input.courseProgress
    .map((p) => p.updatedAt)
    .filter((t): t is string => typeof t === 'string' && t.length > 0)
    .sort((a, b) => b.localeCompare(a))[0] ?? null;

  return {
    stage,
    stageReason: reason,
    orders: {
      total: orders.length,
      open: orders.filter((o) => OPEN_STATUSES.has(o.status)).length,
      // Cancelled orders are not money she spent. Counting them would make a
      // customer who cancelled twice look like our best one.
      spentMinor: orders
        .filter((o) => o.status !== 'cancelled')
        .reduce((n, o) => n + o.totalMinor, 0),
      lastAt: orders[0]?.createdAt ?? null,
      lastStatus: orders[0]?.status ?? null,
      // Cancelled ones are KEPT here, unlike in the money. «Где мой заказ» is
      // sometimes answered with "it was cancelled on the 3rd", and an order
      // hidden from the list is an operator saying "I don't see any order".
      recent: orders.slice(0, RECENT_ORDERS).map((o) => ({
        id: o.id,
        status: o.status,
        createdAt: o.createdAt,
        totalMinor: o.totalMinor,
        items: (o.items ?? []).map((i) => ({ productName: i.productName, qty: i.qty })),
      })),
    },
    course: {
      unlocked: input.courseUnlocked,
      started,
      completed: input.courseProgress.filter((p) => p.completed).length,
      lastAt,
      neverStarted: input.courseUnlocked && started === 0,
    },
  };
}
