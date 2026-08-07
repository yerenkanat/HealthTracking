/**
 * What is waiting for somebody, and how long it has been waiting.
 *
 * docs/CLAUDE-admin-design.md: «Дашбордов два. Владельцу — деньги, «что горит»,
 * люди, удержание и «решение недели». Оператору — очереди задач. Не смешивать.»
 *
 * There was one dashboard, and it was the owner's: revenue, margin, stock
 * value, retention. An operator opening the panel got a screen answering
 * questions that are not hers, and no screen answering the only one that is —
 * what do I do next. Since the back office learned to refuse `finance` to
 * anybody who is not an owner, she gets that same screen with its numbers
 * blanked, which is worse.
 *
 * The number that matters in a queue is not its LENGTH. Three callbacks sitting
 * for four days is a worse morning than twelve from the last hour, and a count
 * alone cannot tell those apart — so every queue carries the age of its oldest
 * item, which is the thing somebody is actually failing at.
 *
 * PURE: lists in, queues out. No repository, no clock beyond the instant it is
 * handed, so the same shapes are testable against a fixed set of rows.
 */

export interface QueueItem {
  id: string;
  /** Who it is about, as a person reads it. */
  who: string;
  /** One line of context — the package asked about, the city, the alert code. */
  detail: string;
  /** When it started waiting. */
  since: string;
}

export interface Queue {
  /** How many are waiting. */
  waiting: number;
  /** Hours the oldest has waited. Null when the queue is empty. */
  oldestHours: number | null;
  /** The front of the queue, oldest first — what to pick up next. */
  next: QueueItem[];
}

const EMPTY: Queue = { waiting: 0, oldestHours: null, next: [] };

/** How many whole hours ago, never negative — a clock skew must not read as "in the future". */
function hoursSince(iso: string, nowMs: number): number {
  const then = Date.parse(iso);
  if (!Number.isFinite(then)) return 0;
  return Math.max(0, Math.floor((nowMs - then) / 3_600_000));
}

/**
 * Oldest first — that is the order the work should be done in, and it is not
 * the order any of these lists arrive in. Every feed in this system is
 * newest-first because that is right for a log and exactly wrong for a queue:
 * it puts the thing that has waited longest at the bottom of the screen.
 */
function toQueue<T>(
  rows: T[],
  since: (r: T) => string,
  item: (r: T) => QueueItem,
  nowMs: number,
  show = 5,
): Queue {
  if (rows.length === 0) return EMPTY;
  const sorted = [...rows].sort((a, b) => Date.parse(since(a)) - Date.parse(since(b)));
  return {
    waiting: sorted.length,
    oldestHours: hoursSince(since(sorted[0]), nowMs),
    next: sorted.slice(0, show).map(item),
  };
}

export interface QueueInputs {
  leads: Array<{ id: string; customerName: string; phone: string; package: string; status: string; createdAt: string }>;
  orders: Array<{ id: string; customerName: string; city: string; status: string; totalMinor: number; createdAt: string }>;
  emergencies: Array<{ id: string; displayName: string; code: string; severity: string; at: string; acknowledgedAt: string | null }>;
}

export interface Queues {
  /** Callbacks nobody has rung back yet. */
  leads: Queue;
  /** Paid or promised, not yet dispatched. */
  orders: Queue;
  /** An SOS nobody has acknowledged. */
  emergencies: Queue;
}

/**
 * @param nowMs the instant to measure ages against, passed in so a test can
 *        fix it and so every queue on one screen is measured from one moment.
 */
export function buildQueues(input: QueueInputs, nowMs: number): Queues {
  return {
    // 'new' only. Once somebody has rung — «Позвонили» — it is out of the queue
    // even if it never became an order: a lead that was called and declined is
    // finished work, and leaving it in would make the queue never empty, which
    // is how a queue stops being read.
    leads: toQueue(
      input.leads.filter((l) => l.status === 'new'),
      (l) => l.createdAt,
      (l) => ({ id: l.id, who: l.customerName || l.phone, detail: l.package || 'заявка с сайта', since: l.createdAt }),
      nowMs,
    ),
    // Everything promised and not yet gone out the door. `delivered` and
    // `cancelled` are finished; `shipped` has left us and is the courier's
    // problem, not a queue anybody here can shorten.
    orders: toQueue(
      input.orders.filter((o) => o.status === 'new' || o.status === 'confirmed'),
      (o) => o.createdAt,
      (o) => ({
        id: o.id,
        who: o.customerName,
        detail: `${o.city}${o.status === 'confirmed' ? ' · подтверждён' : ''}`,
        since: o.createdAt,
      }),
      nowMs,
    ),
    emergencies: toQueue(
      input.emergencies.filter((e) => e.acknowledgedAt == null),
      (e) => e.at,
      (e) => ({ id: e.id, who: e.displayName, detail: `${e.code} · ${e.severity}`, since: e.at }),
      nowMs,
    ),
  };
}

/**
 * The one line above the board: is anything actually late?
 *
 * A board of three numbers still needs somebody to decide whether today is
 * fine. These are the thresholds this business works to — an SOS is measured in
 * minutes, a callback in hours, an order in days — and each is named rather
 * than folded into one "overdue" flag, because what to do about each is
 * different.
 */
export const SLA_HOURS = { emergencies: 1, leads: 4, orders: 48 } as const;

export function overdue(q: Queues): Array<keyof Queues> {
  return (Object.keys(SLA_HOURS) as Array<keyof Queues>)
    .filter((k) => (q[k].oldestHours ?? 0) >= SLA_HOURS[k] && q[k].waiting > 0)
    // Worst first: an unacknowledged SOS outranks a stale callback however long
    // the callback has been sitting.
    .sort((a, b) => SLA_HOURS[a] - SLA_HOURS[b]);
}
