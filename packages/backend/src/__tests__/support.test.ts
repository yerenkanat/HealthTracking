/**
 * Frame 12 — the support queue's arithmetic.
 *
 * The assertions that matter are about what does NOT count as us being slow.
 * A queue that cries wolf is a queue an operator stops reading.
 */

import { describe, it, expect } from 'vitest';
import {
  buildSupportBoard, fillTemplate, OURS_TO_ANSWER, SUPPORT_SLA_HOURS, whatsappReplyLink,
} from '../admin/support';
import type { SupportTicketRow } from '../db/repository';

const NOW = '2026-08-11T12:00:00.000Z';
const hoursAgo = (h: number) =>
  new Date(Date.parse(NOW) - h * 3_600_000).toISOString();

let n = 0;
const ticket = (t: Partial<SupportTicketRow> = {}): SupportTicketRow => ({
  id: `t${++n}`,
  userId: null,
  phone: '+7 707 345 22 44',
  customerName: 'Айгерім',
  channel: 'whatsapp',
  subject: 'Где мой заказ',
  body: '',
  status: 'new',
  assigneeId: null,
  createdAt: hoursAgo(1),
  updatedAt: hoursAgo(1),
  answeredAt: null,
  closedAt: null,
  appContext: null,
  // She has not written since raising it — the board falls back to createdAt,
  // which is what every case below assumes unless it says otherwise.
  lastCustomerAt: null,
  // She has never opened the thread. The board does not read this — it is the
  // app's badge that does — but the row carries it.
  customerReadAt: null,
  ...t,
});

describe('whose turn it is', () => {
  it('counts a new, unanswered ticket as ours', () => {
    const b = buildSupportBoard([ticket({ createdAt: hoursAgo(2) })], NOW);
    expect(b.waiting).toBe(1);
    expect(b.items[0].waitingHours).toBeCloseTo(2, 1);
  });

  it('does NOT count one we already answered', () => {
    // She has not written back. That is not a support failure, and counting it
    // teaches an operator to ignore the colour on the screen.
    const b = buildSupportBoard(
      [ticket({ status: 'open', answeredAt: hoursAgo(1), createdAt: hoursAgo(40) })], NOW);
    expect(b.waiting).toBe(0);
    expect(b.items[0].waitingHours).toBeNull();
  });

  it('does NOT count one explicitly waiting on the customer', () => {
    const b = buildSupportBoard([ticket({ status: 'waiting', createdAt: hoursAgo(90) })], NOW);
    expect(b.waiting).toBe(0);
  });

  it('does not count a closed ticket', () => {
    const b = buildSupportBoard(
      [ticket({ status: 'closed', closedAt: hoursAgo(1), createdAt: hoursAgo(100) })], NOW);
    expect(b.waiting).toBe(0);
    expect(b.neverAnswered).toBe(0);
  });

  it('null and zero hours are different answers', () => {
    // Null is "not our turn"; 0 is "ours, and it just arrived". Collapsing them
    // would put a brand-new ticket and a finished one in the same bucket.
    const b = buildSupportBoard(
      [ticket({ createdAt: NOW }), ticket({ status: 'waiting' })], NOW);
    const fresh = b.items.find((i) => i.status === 'new')!;
    const theirs = b.items.find((i) => i.status === 'waiting')!;
    expect(fresh.waitingHours).toBe(0);
    expect(theirs.waitingHours).toBeNull();
  });
});

describe('whose message the clock starts at', () => {
  // Frame 43 gave the app a way to write back into the thread, so a ticket can
  // now be old, answered, and urgent all at once.
  it('measures from HER LAST message, not from the ticket', () => {
    // Raised a fortnight ago, answered then, and she wrote again an hour ago.
    // Measuring from createdAt would print «336 ч» beside a message that
    // arrived while the operator was reading the screen.
    const b = buildSupportBoard([ticket({
      status: 'open', createdAt: hoursAgo(336), answeredAt: hoursAgo(335),
      lastCustomerAt: hoursAgo(1),
    })], NOW);
    expect(b.items[0].waitingHours).toBeCloseTo(1, 1);
    expect(b.overdue).toBe(0);
  });

  it('restarts the clock when she writes after our answer', () => {
    const b = buildSupportBoard([ticket({
      status: 'open', createdAt: hoursAgo(20), answeredAt: hoursAgo(19),
      lastCustomerAt: hoursAgo(6),
    })], NOW);
    expect(b.waiting).toBe(1);
    expect(b.items[0].overdue).toBe(true);
  });

  it('still stops it while she is silent', () => {
    // Her last message came BEFORE our answer, so the ball is in her court.
    const b = buildSupportBoard([ticket({
      status: 'open', createdAt: hoursAgo(30), answeredAt: hoursAgo(2),
      lastCustomerAt: hoursAgo(3),
    })], NOW);
    expect(b.items[0].waitingHours).toBeNull();
  });

  it('does not call her «ни разу не отвечали» after we have answered', () => {
    // answeredAt records when WE last spoke and is deliberately never cleared
    // by her reply; clearing it would report that nobody had ever answered a
    // woman who has been answered twice.
    const b = buildSupportBoard([ticket({
      status: 'open', answeredAt: hoursAgo(5), lastCustomerAt: hoursAgo(1),
    })], NOW);
    expect(b.neverAnswered).toBe(0);
    expect(b.waiting).toBe(1);
  });
});

describe('the promise', () => {
  it('uses the SAME number as the rest of the panel', () => {
    // Two constants for one promise drift, and the dashboard would disagree
    // with this screen within a month.
    expect(SUPPORT_SLA_HOURS).toBe(4);
  });

  it('marks a ticket past the promise as overdue', () => {
    const b = buildSupportBoard([ticket({ createdAt: hoursAgo(5) })], NOW);
    expect(b.overdue).toBe(1);
    expect(b.items[0].overdue).toBe(true);
  });

  it('leaves one inside the promise alone', () => {
    const b = buildSupportBoard([ticket({ createdAt: hoursAgo(3) })], NOW);
    expect(b.overdue).toBe(0);
  });

  it('an answered-but-ancient ticket is never overdue', () => {
    const b = buildSupportBoard(
      [ticket({ status: 'open', createdAt: hoursAgo(500), answeredAt: hoursAgo(490) })], NOW);
    expect(b.overdue).toBe(0);
  });
});

describe('the order of the queue', () => {
  it('puts the longest wait FIRST', () => {
    // A queue, not a log. Newest-first keeps whoever has waited longest at the
    // bottom of the screen all day.
    const b = buildSupportBoard([
      ticket({ subject: 'recent', createdAt: hoursAgo(1) }),
      ticket({ subject: 'ancient', createdAt: hoursAgo(30) }),
      ticket({ subject: 'middling', createdAt: hoursAgo(6) }),
    ], NOW);
    expect(b.items.map((i) => i.subject)).toEqual(['ancient', 'middling', 'recent']);
  });

  it('sinks tickets that are not ours below every one that is', () => {
    const b = buildSupportBoard([
      ticket({ subject: 'theirs', status: 'waiting', createdAt: hoursAgo(200) }),
      ticket({ subject: 'ours', createdAt: hoursAgo(1) }),
    ], NOW);
    expect(b.items[0].subject).toBe('ours');
  });

  it('reports the oldest wait, and null when nothing is waiting', () => {
    expect(buildSupportBoard([ticket({ createdAt: hoursAgo(7) })], NOW).oldestHours).toBeCloseTo(7, 1);
    expect(buildSupportBoard([ticket({ status: 'closed' })], NOW).oldestHours).toBeNull();
  });
});

describe('never answered', () => {
  it('is counted separately from merely waiting', () => {
    // The worst kind: nobody has said anything to her at all.
    const b = buildSupportBoard([
      ticket({ status: 'open', answeredAt: hoursAgo(2) }),
      ticket({ status: 'new' }),
    ], NOW);
    expect(b.neverAnswered).toBe(1);
  });
});

describe('«Ответить в WhatsApp»', () => {
  it('opens a conversation that has already started', () => {
    const link = whatsappReplyLink(ticket({ phone: '+7 707 345 22 44' }))!;
    expect(link).toContain('wa.me/77073452244');
    expect(decodeURIComponent(link)).toContain('Айгерім');
    // The subject travels with it — the commonest reason a thread stalls is
    // her not knowing which of her questions this is about.
    expect(decodeURIComponent(link)).toContain('Где мой заказ');
  });

  it('returns null when there is no number to write to', () => {
    // An operator taking a phone call may raise a ticket with a name and no
    // number. A button that opens nothing is worse than a row that says so.
    expect(whatsappReplyLink(ticket({ phone: null }))).toBeNull();
    expect(whatsappReplyLink(ticket({ phone: '123' }))).toBeNull();
  });

  it('greets without a name when we do not have one', () => {
    const link = whatsappReplyLink(ticket({ customerName: null }))!;
    expect(decodeURIComponent(link)).toContain('Здравствуйте!');
  });
});

describe('templates', () => {
  it('fills what it knows', () => {
    expect(fillTemplate('Заказ {status}, доставка {eta}.', { status: 'собран', eta: 'завтра' }))
      .toBe('Заказ собран, доставка завтра.');
  });

  it('leaves an unknown placeholder VISIBLE rather than blanking it', () => {
    // «доставка: {eta}» reaching a customer is embarrassing and an operator
    // catches it. «доставка: » reads as finished and gets sent.
    expect(fillTemplate('Доставка {eta}.', {})).toBe('Доставка {eta}.');
  });
});

describe('the states', () => {
  it('only new and open are ours to answer', () => {
    expect([...OURS_TO_ANSWER]).toEqual(['new', 'open']);
  });
});
