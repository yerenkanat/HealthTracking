/**
 * Frame 12 — «Поддержка».
 *
 * The queue, and the one number an operator's screen turns on: how long
 * somebody has been waiting for a FIRST answer.
 *
 * ON WHAT "WAITING" MEANS. Measured from the customer's last message to our
 * last reply — never from the ticket's creation date. A ticket we answered in
 * four minutes and which has been open a fortnight because she has not written
 * back is not a support failure, and counting it as one teaches an operator to
 * ignore the colour on the screen. `status: 'waiting'` is precisely the state
 * where the ball is in her court, and it is excluded from the SLA for that
 * reason.
 *
 * ON THE SLA ITSELF. Reused from admin/queues.ts rather than invented here —
 * `SLA_HOURS.leads` is four hours and support is the same promise. Two numbers
 * for one promise drift, and the one on the dashboard would disagree with the
 * one on this screen within a month.
 *
 * PURE: tickets in, the board out.
 */

import type { SupportStatus, SupportTicketRow } from '../db/repository';
import { SLA_HOURS } from './queues';

/** Support answers on the same promise as a callback request. */
export const SUPPORT_SLA_HOURS = SLA_HOURS.leads;

/** Neither closed nor waiting on the customer: ours to answer. */
export const OURS_TO_ANSWER: readonly SupportStatus[] = ['new', 'open'];

export interface SupportQueueItem extends SupportTicketRow {
  /**
   * Hours since she last needed an answer, or null when the ball is not in our
   * court. Null and 0 are different: null means "not our turn".
   */
  waitingHours: number | null;
  /** Past the promise, and still ours. */
  overdue: boolean;
  /** She has never had a reply from anyone. */
  neverAnswered: boolean;
}

export interface SupportBoard {
  items: SupportQueueItem[];
  counts: Record<SupportStatus, number>;
  /** Ours to answer, right now. */
  waiting: number;
  /** Of those, past the promise. */
  overdue: number;
  /** Hours the oldest unanswered has been waiting; null when none are. */
  oldestHours: number | null;
  /** Never had a first reply. The worst kind of waiting. */
  neverAnswered: number;
}

const HOUR = 3_600_000;

export function buildSupportBoard(
  tickets: SupportTicketRow[],
  nowIso: string,
): SupportBoard {
  const now = new Date(nowIso).getTime();

  const items: SupportQueueItem[] = tickets.map((t) => {
    const ours = (OURS_TO_ANSWER as readonly string[]).includes(t.status);
    // From when SHE last needed us — her message — which for a ticket with no
    // reply is its creation. Once we answer, the clock stops; if she writes
    // again the route bumps updated_at and it starts over.
    const since = t.answeredAt ? null : new Date(t.createdAt).getTime();
    const waitingHours = ours && since != null
      ? Math.max(0, (now - since) / HOUR)
      : null;

    return {
      ...t,
      waitingHours,
      overdue: waitingHours != null && waitingHours >= SUPPORT_SLA_HOURS,
      neverAnswered: t.answeredAt == null && t.status !== 'closed',
    };
  });

  // Oldest unanswered FIRST. This is a queue, not a log: the newest ticket is
  // the least urgent thing on it, and sorting newest-first is how the person
  // who has waited longest stays at the bottom of the screen all day.
  items.sort((a, b) => {
    if (a.waitingHours == null && b.waitingHours == null) {
      return b.createdAt.localeCompare(a.createdAt);
    }
    if (a.waitingHours == null) return 1;
    if (b.waitingHours == null) return -1;
    return b.waitingHours - a.waitingHours;
  });

  const counts = { new: 0, open: 0, waiting: 0, closed: 0 } as Record<SupportStatus, number>;
  for (const t of tickets) counts[t.status] = (counts[t.status] ?? 0) + 1;

  const ours = items.filter((i) => i.waitingHours != null);
  return {
    items,
    counts,
    waiting: ours.length,
    overdue: ours.filter((i) => i.overdue).length,
    oldestHours: ours.length ? Math.round(ours[0].waitingHours! * 10) / 10 : null,
    neverAnswered: items.filter((i) => i.neverAnswered).length,
  };
}

/**
 * «Ответить в WhatsApp» — the link that opens the conversation already started.
 *
 * Returns null when there is no number to write to, so the panel can show the
 * row as unanswerable rather than rendering a button that opens nothing. That
 * is a real case: a ticket raised from the panel by an operator taking a phone
 * call may carry a name and no number at all.
 */
export function whatsappReplyLink(
  ticket: Pick<SupportTicketRow, 'phone' | 'customerName' | 'subject'>,
  template?: string,
): string | null {
  const digits = (ticket.phone ?? '').replace(/\D/g, '');
  if (digits.length < 10) return null;

  const greeting = ticket.customerName?.trim()
    ? `Здравствуйте, ${ticket.customerName.trim()}!`
    : 'Здравствуйте!';
  // The subject travels with it so she does not have to remember which of her
  // questions this is about — the commonest reason a support thread stalls.
  const body = template?.trim()
    ? template.trim()
    : `${greeting} Вы писали нам: «${ticket.subject}».`;

  return `https://wa.me/${digits}?text=${encodeURIComponent(body)}`;
}

/**
 * Fill a template's {placeholders} from what we know.
 *
 * An unfilled placeholder is left VISIBLE rather than blanked: «доставка: {eta}»
 * reaching a customer is embarrassing, and an operator will catch it — whereas
 * «доставка: » reads as finished and gets sent.
 */
export function fillTemplate(body: string, values: Record<string, string>): string {
  return body.replace(/\{(\w+)\}/g, (whole, key) => values[key] ?? whole);
}
