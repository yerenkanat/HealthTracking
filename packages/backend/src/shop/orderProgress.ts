/**
 * Screen 42 — «Мой заказ».
 *
 * docs/CLAUDE-app-design.md: «карточка «Курьер везёт сегодня» → таймлайн
 * статусов → состав заказа → «Написать / Отменить».»
 *
 * A woman pays 39 000 ₸ through the app and then the app never mentions it
 * again. POST /shop/orders existed; nothing could read one back. The only way
 * to find out where her order was, was to message somebody on WhatsApp — which
 * is what the support number is for, and not what it should be spent on.
 *
 * This turns a stored order into the two things the screen shows: where it is
 * now, said as a sentence, and the steps behind and ahead of it.
 *
 * PURE: an order in, its progress out. No repository, no clock beyond the
 * instant it is given.
 */

import type { ShopOrder, ShopOrderStatus } from '../db/repository';

/**
 * The journey, in order. `cancelled` is deliberately NOT on it: it is not a
 * later stage of delivery, it is the journey stopping, and drawing it as a
 * fourth step implies the parcel is still coming.
 */
export const ORDER_STEPS = ['new', 'confirmed', 'shipped', 'delivered'] as const;
export type OrderStep = (typeof ORDER_STEPS)[number];

export interface ProgressStep {
  step: OrderStep;
  /** Reached, or still ahead. */
  done: boolean;
  /** The one the order is on now. */
  current: boolean;
}

export interface OrderProgress {
  orderId: string;
  status: ShopOrderStatus;
  cancelled: boolean;
  steps: ProgressStep[];
  /**
   * Can she still call it off herself?
   *
   * Only before it ships. Once it is with a courier, cancelling in an app does
   * not stop a van — offering the button would be a promise the system cannot
   * keep, and she would find out by receiving the parcel.
   */
  cancellable: boolean;
  /** Money, for the summary line. */
  totalMinor: number;
  items: ShopOrder['items'];
  createdAt: string;
  city: string;
  address: string;
}

export function orderProgress(order: ShopOrder): OrderProgress {
  const cancelled = order.status === 'cancelled';
  const reached = cancelled ? -1 : ORDER_STEPS.indexOf(order.status as OrderStep);

  return {
    orderId: order.id,
    status: order.status,
    cancelled,
    steps: ORDER_STEPS.map((step, i) => ({
      step,
      // A cancelled order has no completed steps drawn: the timeline is about
      // where the parcel is, and it is nowhere.
      done: !cancelled && i <= reached,
      current: !cancelled && i === reached,
    })),
    cancellable: order.status === 'new' || order.status === 'confirmed',
    totalMinor: order.totalMinor,
    items: order.items,
    createdAt: order.createdAt,
    city: order.city,
    address: order.address,
  };
}

/**
 * Which orders are worth showing her.
 *
 * Newest first, and a delivered order stays: «где мой заказ» is asked after it
 * arrives too — to check what was in it, or to find the number to call about a
 * warranty. Only genuinely old delivered ones drop off.
 */
export function visibleOrders(
  orders: ShopOrder[],
  now: Date,
  keepDeliveredDays = 60,
): ShopOrder[] {
  const cutoff = now.getTime() - keepDeliveredDays * 86_400_000;
  return orders
    .filter((o) => {
      const t = Date.parse(o.createdAt);
      if (!Number.isFinite(t)) return false;
      // Anything still moving is always shown, however old — an order stuck in
      // `new` for three months is exactly what she needs to see.
      if (o.status !== 'delivered' && o.status !== 'cancelled') return true;
      return t >= cutoff;
    })
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}
