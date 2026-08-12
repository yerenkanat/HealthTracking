/**
 * Frame 03 «Карточка заказа» — everything the card states, computed once.
 *
 * The panel could have assembled most of this from the list it already holds.
 * It must not: the WhatsApp rule and the "what the history does not know" rule
 * are decisions about honesty, and a decision duplicated in HTML drifts from
 * the one the server makes within a month. They live here, they are pure, and
 * they are tested without a browser.
 *
 * PURE: an order and its recorded events in, the card's derived facts out.
 */

import type { ShopOrder, ShopOrderEvent, ShopOrderStatus } from '../db/repository';
import { whatsappReplyLink } from './support';

/** The panel's own vocabulary, kept beside the rules that mention it. */
export const ORDER_STATUS_RU: Record<ShopOrderStatus, string> = {
  new: 'Новый',
  confirmed: 'Подтверждён',
  shipped: 'Отправлен',
  delivered: 'Доставлен',
  cancelled: 'Отменён',
};

/**
 * A human-sized reference for an order.
 *
 * The spec's mock-ups show «4826». Real orders are UUIDs, and there is no
 * sequence column to turn one into a four-digit number — inventing one for the
 * screen would produce a reference the operator reads out on the phone and
 * which matches nothing in the database. So: the first eight characters of the
 * real id, which IS the order and can be pasted back into a search.
 */
export function orderRef(id: string): string {
  return String(id).slice(0, 8);
}

/** Tenge from minor units, no currency sign — the caller adds it. */
function tenge(minor: number): string {
  return String(Math.round((minor ?? 0) / 100));
}

/**
 * «Написать в WhatsApp» for the customer on this order.
 *
 * Reuses whatsappReplyLink and therefore its rule: fewer than ten digits is not
 * a number we can write to, and the answer is null so the card can say the
 * order has no reachable contact instead of rendering a button that opens a
 * broken chat. That case is real — an order taken over the phone from a
 * landline, or one typed with the number left blank.
 *
 * The order reference and the sum travel in the text because the first thing
 * the customer asks is "which order?", and the operator should not have to
 * retype either.
 */
export function orderWhatsappLink(
  order: Pick<ShopOrder, 'id' | 'customerName' | 'phone' | 'totalMinor'>,
): string | null {
  const greeting = order.customerName?.trim()
    ? `Здравствуйте, ${order.customerName.trim()}!`
    : 'Здравствуйте!';
  return whatsappReplyLink(
    { phone: order.phone, customerName: order.customerName, subject: '' },
    `${greeting} Пишем из Ana-Bala по заказу №${orderRef(order.id)} на ${tenge(order.totalMinor)} ₸.`,
  );
}

export interface OrderTimelineEntry {
  at: string;
  /** 'created' is derived from the order row; 'status' is a recorded move. */
  kind: 'created' | 'status';
  status: ShopOrderStatus | null;
  from: ShopOrderStatus | null;
  /** Who did it — a name, an id we could not resolve, or null for nobody. */
  by: string | null;
}

export interface OrderTimeline {
  entries: OrderTimelineEntry[];
  /**
   * True when the recorded history cannot account for how the order got where
   * it is: either there are no events at all and it is past «Новый», or the
   * earliest recorded move starts from a status other than «Новый».
   *
   * Every order placed before migration 039 is in this state, and so is every
   * order whose status moved before it. The card prints the gap. An empty
   * timeline under a delivered order otherwise reads as "nothing ever happened
   * to it", which is the one thing a history must never say.
   */
  gap: boolean;
}

export function buildOrderTimeline(
  order: Pick<ShopOrder, 'createdAt' | 'status'>,
  events: ShopOrderEvent[],
): OrderTimeline {
  const ordered = [...events].sort((a, b) => a.at.localeCompare(b.at) || a.id - b.id);

  const entries: OrderTimelineEntry[] = [
    // Not stored as an event: the order row already carries the moment it was
    // created, and writing a second copy of it would give the screen two dates
    // that can disagree.
    { at: order.createdAt, kind: 'created', status: 'new', from: null, by: null },
    ...ordered.map((e): OrderTimelineEntry => ({
      at: e.at,
      kind: 'status',
      status: e.toStatus,
      from: e.fromStatus,
      by: e.staffName ?? e.staffId ?? null,
    })),
  ];

  const gap = ordered.length === 0
    ? order.status !== 'new'
    : ordered[0].fromStatus !== 'new';

  return { entries, gap };
}
