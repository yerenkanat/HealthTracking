/**
 * The retention periods, and the thing that makes them true.
 *
 * privacy/retention.ts swept ONE table. Everything else holding personal data
 * was kept until the account was deleted, or for ever where it is keyed by a
 * phone number rather than by user_id — a zone crossing, a name and a number
 * from the landing form, an abandoned sign-in code, the log of which numbers
 * tried to sign in. The published policy said so honestly, which is a different
 * thing from it being all right.
 *
 * Deleting data is irreversible, so every sweep here is checked TWICE: that it
 * removes what its period says it must, and that it leaves the row next to it
 * alone. The second half is the one that matters. A sweep that never runs is a
 * promise unkept; a sweep that over-deletes takes a mother's SOS history, a
 * customer's support thread or the evidence of who read a health record, and
 * nothing brings any of it back.
 *
 * Boundaries are exercised exactly, not approximately: a row at exactly the
 * period is still INSIDE its window, so "older than" is strict everywhere.
 */

import { describe, it, expect, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  AUDIT_RETENTION_DAYS,
  AUDIT_RETENTION_YEARS,
  GEOFENCE_EVENT_RETENTION_DAYS,
  LOGIN_ATTEMPT_RETENTION_DAYS,
  PHONE_CODE_RETENTION_DAYS,
  RETENTION_KEPT,
  RETENTION_SWEEPS,
  ROUTE_RETENTION_DAYS,
  SAFETY_ALERT_RETENTION_DAYS,
  SAFETY_ALERT_RETENTION_MONTHS,
  SHOP_LEAD_RETENTION_DAYS,
  SUPPORT_RETENTION_DAYS,
  SUPPORT_RETENTION_YEARS,
  retentionCutoff,
  sweepAll,
  type RetentionDeps,
} from '../privacy/retention';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const NOW = new Date('2026-08-19T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

/**
 * Write with the clock wound back, so a row can be as old as a period.
 *
 * Several of these tables stamp their own `now()` — phone_codes, the two
 * attempt tables, shop_leads, support_tickets — exactly as the Postgres
 * DEFAULTs do. Backdating the clock is how a fake row gets an age without
 * adding a test-only parameter to production code.
 */
async function withClockAt<T>(iso: string, fn: () => Promise<T>): Promise<T> {
  vi.useFakeTimers();
  vi.setSystemTime(new Date(iso));
  try {
    return await fn();
  } finally {
    vi.useRealTimers();
  }
}

const cutoffFor = (days: number) => retentionCutoff(NOW, days);

// Two children on two accounts. Most of these sweeps are by AGE alone, and the
// second row is here to prove they do not take a neighbour with them.
const CHILD_A = '11111111-1111-1111-1111-111111111111';
const CHILD_B = '22222222-2222-2222-2222-222222222222';

describe('the periods are decisions, written once', () => {
  it('every sweep takes its number from a named constant, not a literal', () => {
    // The defect this whole change replaces is a number typed at a call site
    // with nothing behind it — the panel's «3 года» for a table nothing ever
    // deleted. Every entry on the schedule must be one of these.
    const named = new Set([
      ROUTE_RETENTION_DAYS,
      GEOFENCE_EVENT_RETENTION_DAYS,
      SAFETY_ALERT_RETENTION_DAYS,
      AUDIT_RETENTION_DAYS,
      PHONE_CODE_RETENTION_DAYS,
      LOGIN_ATTEMPT_RETENTION_DAYS,
      SHOP_LEAD_RETENTION_DAYS,
      SUPPORT_RETENTION_DAYS,
    ]);
    for (const s of RETENTION_SWEEPS) {
      expect(named.has(s.days), `${s.table} keeps a period no constant names`).toBe(true);
      expect(s.days, `${s.table} has a nonsensical period`).toBeGreaterThan(0);
      expect(s.why.length, `${s.table} has no stated reason`).toBeGreaterThan(10);
    }
  });

  it('the numbers are the ones that were decided', () => {
    expect(ROUTE_RETENTION_DAYS).toBe(90);
    // A crossing is the route that produced it. Keeping it longer was never a
    // decision, just an omission.
    expect(GEOFENCE_EVENT_RETENTION_DAYS).toBe(ROUTE_RETENTION_DAYS);
    expect(SAFETY_ALERT_RETENTION_MONTHS).toBe(12);
    expect(SAFETY_ALERT_RETENTION_DAYS).toBe(365);
    expect(AUDIT_RETENTION_YEARS).toBe(3);
    expect(AUDIT_RETENTION_DAYS).toBe(3 * 365);
    expect(PHONE_CODE_RETENTION_DAYS).toBe(30);
    expect(LOGIN_ATTEMPT_RETENTION_DAYS).toBe(90);
    expect(SHOP_LEAD_RETENTION_DAYS).toBe(365);
    expect(SUPPORT_RETENTION_YEARS).toBe(3);
    expect(SUPPORT_RETENTION_DAYS).toBe(3 * 365);
  });

  it('the screen and the sweep read one constant, so they cannot disagree', () => {
    // AUDIT_RETENTION_YEARS is what the security card prints and
    // AUDIT_RETENTION_DAYS is what the cutoff uses. Deriving one from the other
    // is the whole point: b8aac0c existed because a screen said three years
    // while nothing deleted anything.
    expect(AUDIT_RETENTION_DAYS / AUDIT_RETENTION_YEARS).toBe(365);
  });

  it('every table on the schedule is swept exactly once', () => {
    const tables = RETENTION_SWEEPS.map((s) => s.table);
    expect(new Set(tables).size, 'a table is on the schedule twice').toBe(tables.length);
    expect(tables).toEqual([
      'location_history',
      'geofence_events',
      'safety_alerts',
      'audit_log',
      'phone_codes',
      'login_attempts',
      'shop_leads',
      'support_tickets',
    ]);
  });

  it('what is deliberately kept says why, in writing', () => {
    // The orders decision is the one that must never quietly become a sweep:
    // an accounting record deleted on a period nobody can cite is worse than
    // one kept too long, and the policy tells the customer this in those words.
    const orders = RETENTION_KEPT.find((k) => k.table.includes('shop_orders'));
    expect(orders, 'orders are no longer listed as deliberately kept').toBeDefined();
    expect(orders!.why).toMatch(/accounting/i);
    expect(orders!.why).toMatch(/LAWYER/);
    expect(RETENTION_SWEEPS.some((s) => s.table.includes('shop_order'))).toBe(false);
  });
});

describe('geofence_events — a crossing cannot outlive the route it came from', () => {
  const evt = (childId: string, at: string) => ({
    childId, geofenceId: 'gf-1', geofenceName: 'Дом',
    transition: 'exit' as const, at, source: 'gps' as const,
  });

  it('a crossing past 90 days goes; one inside the window stays', async () => {
    const repo = createMemoryRepository();
    await repo.insertGeofenceEvent(evt(CHILD_A, daysAgo(120)));
    await repo.insertGeofenceEvent(evt(CHILD_A, daysAgo(10)));
    // Another child's recent crossing: the sweep is by age, never by child.
    await repo.insertGeofenceEvent(evt(CHILD_B, daysAgo(1)));

    expect(await repo.pruneGeofenceEvents(cutoffFor(GEOFENCE_EVENT_RETENTION_DAYS))).toBe(1);

    const a = await repo.listGeofenceEvents(CHILD_A, 50);
    expect(a.map((e) => e.at)).toEqual([daysAgo(10)]);
    expect((await repo.listGeofenceEvents(CHILD_B, 50)).length).toBe(1);
  });

  it('exactly 90 days old is still inside the window', async () => {
    const repo = createMemoryRepository();
    await repo.insertGeofenceEvent(evt(CHILD_A, daysAgo(90)));
    expect(await repo.pruneGeofenceEvents(cutoffFor(GEOFENCE_EVENT_RETENTION_DAYS))).toBe(0);
    expect((await repo.listGeofenceEvents(CHILD_A, 50)).length).toBe(1);
  });

  it('sweeping crossings does not touch the trail beside them', async () => {
    // Two tables, one period, two DELETEs. A sweep that reached into the other
    // would delete a route on a crossing's clock, which is how a fix that is
    // "obviously fine" removes 90 days of somebody else's data.
    const repo = createMemoryRepository();
    await repo.insertLocation({
      childId: CHILD_A, coords: { lat: 43.2, lng: 76.8 },
      source: 'gps', observedAt: daysAgo(200),
    });
    await repo.insertGeofenceEvent(evt(CHILD_A, daysAgo(200)));
    expect(await repo.pruneGeofenceEvents(cutoffFor(GEOFENCE_EVENT_RETENTION_DAYS))).toBe(1);
    expect(await repo.lastLocation(CHILD_A)).not.toBeNull();
  });
});

describe('safety_alerts — twelve months, SOS included', () => {
  const alert = (kind: 'sos' | 'left', at: string) =>
    ({ childId: CHILD_A, kind, zoneName: kind === 'sos' ? '' : 'Школа', at });

  it('an alert past twelve months goes; one inside stays', async () => {
    const repo = createMemoryRepository();
    await repo.recordAlert(DEMO_USER, alert('left', daysAgo(400)));
    await repo.recordAlert(DEMO_USER, alert('left', daysAgo(200)));
    expect(await repo.pruneSafetyAlerts(cutoffFor(SAFETY_ALERT_RETENTION_DAYS))).toBe(1);
    const rows = await repo.listAlerts(DEMO_USER, 50);
    expect(rows.map((r) => r.at)).toEqual([daysAgo(200)]);
  });

  it('an SOS is swept on the same clock as any other alert', async () => {
    // Deliberate, and the sharpest edge on this page: what is kept is the
    // record of the event, not a permanent movement history of a child. An SOS
    // exempted here would quietly become that history.
    const repo = createMemoryRepository();
    await repo.recordAlert(DEMO_USER, alert('sos', daysAgo(400)));
    await repo.recordAlert(DEMO_USER, alert('sos', daysAgo(30)));
    expect(await repo.pruneSafetyAlerts(cutoffFor(SAFETY_ALERT_RETENTION_DAYS))).toBe(1);
    const rows = await repo.listAlerts(DEMO_USER, 50);
    expect(rows.map((r) => r.at)).toEqual([daysAgo(30)]);
  });

  it('exactly 365 days old is still inside the window', async () => {
    const repo = createMemoryRepository();
    await repo.recordAlert(DEMO_USER, alert('sos', daysAgo(365)));
    expect(await repo.pruneSafetyAlerts(cutoffFor(SAFETY_ALERT_RETENTION_DAYS))).toBe(0);
    expect((await repo.listAlerts(DEMO_USER, 50)).length).toBe(1);
  });

  it('another family is not swept out with hers', async () => {
    // safety_alerts is stored per user. The sweep is by age only, so a second
    // account's recent rows must be untouched by hers going.
    const repo = createMemoryRepository();
    await repo.recordAlert(DEMO_USER, alert('left', daysAgo(400)));
    await repo.recordAlert('other-user', alert('left', daysAgo(3)));
    expect(await repo.pruneSafetyAlerts(cutoffFor(SAFETY_ALERT_RETENTION_DAYS))).toBe(1);
    expect((await repo.listAlerts('other-user', 50)).length).toBe(1);
    expect((await repo.listAlerts(DEMO_USER, 50)).length).toBe(0);
  });
});

describe('audit_log — three years, and now something enforces it', () => {
  it('an entry past three years goes; one inside stays', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(1200), () =>
      repo.writeAudit({ staffId: 's1', action: 'view_health', target: 'u1', reason: 'Обращение' }));
    await withClockAt(daysAgo(300), () =>
      repo.writeAudit({ staffId: 's1', action: 'view_location', target: 'u1', reason: 'Звонок' }));

    expect(await repo.pruneAuditLog(cutoffFor(AUDIT_RETENTION_DAYS))).toBe(1);
    const left = (await repo.listAudit(50)).entries;
    expect(left.length).toBe(1);
    expect(left[0].action).toBe('view_location');
  });

  it('exactly three years old is still inside the window', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(AUDIT_RETENTION_DAYS), () =>
      repo.writeAudit({ staffId: 's1', action: 'view_health', target: 'u1', reason: 'Обращение' }));
    expect(await repo.pruneAuditLog(cutoffFor(AUDIT_RETENTION_DAYS))).toBe(0);
    expect((await repo.listAudit(50)).entries.length).toBe(1);
  });

  it('the reason survives as long as the entry does', async () => {
    // The row is worth keeping only for the reason on it. A sweep that emptied
    // the field instead of the row would leave the log looking complete and
    // proving nothing.
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(10), () =>
      repo.writeAudit({ staffId: 's1', action: 'view_health', target: 'u1', reason: 'Разбор жалобы' }));
    await repo.pruneAuditLog(cutoffFor(AUDIT_RETENTION_DAYS));
    expect((await repo.listAudit(50)).entries[0].reason).toBe('Разбор жалобы');
  });
});

describe('phone_codes — an abandoned sign-in stops living for ever', () => {
  it('a code asked for and never used goes after 30 days', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(60), () => repo.putPhoneCode({
      phone: '77001112233', codeHash: 'h-old',
      expiresAt: new Date(Date.parse(daysAgo(60)) + 600_000),
    }));
    await withClockAt(daysAgo(2), () => repo.putPhoneCode({
      phone: '77007654321', codeHash: 'h-new',
      expiresAt: new Date(Date.parse(daysAgo(2)) + 600_000),
    }));

    expect(await repo.prunePhoneCodes(cutoffFor(PHONE_CODE_RETENTION_DAYS))).toBe(1);
    // The old number's row is gone entirely — 'none', not 'expired'.
    expect(await repo.usePhoneCode('77001112233', 'h-old', NOW)).toBe('none');
    // The recent one is untouched, and still answers as the row it was.
    expect(await repo.usePhoneCode('77007654321', 'h-new', NOW)).toBe('expired');
  });

  it('is measured from when the code was asked for, not from when it expired', async () => {
    // expires_at is minutes after created_at. Sweeping on expiry would push
    // every deletion thirty days past the wrong instant — a longer window than
    // the one that was decided, silently.
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(PHONE_CODE_RETENTION_DAYS), () => repo.putPhoneCode({
      phone: '77001112233', codeHash: 'h',
      expiresAt: new Date(Date.parse(daysAgo(PHONE_CODE_RETENTION_DAYS)) + 600_000),
    }));
    // Exactly thirty days old: still inside.
    expect(await repo.prunePhoneCodes(cutoffFor(PHONE_CODE_RETENTION_DAYS))).toBe(0);
    expect(await repo.usePhoneCode('77001112233', 'wrong', NOW)).toBe('expired');
  });

  it('never takes a code that is still usable', async () => {
    // A live code is minutes old. If this ever deleted one, a woman waiting on
    // an SMS would be told her code is wrong.
    const repo = createMemoryRepository();
    await repo.putPhoneCode({
      phone: '77001112233', codeHash: 'live', expiresAt: new Date(Date.now() + 600_000),
    });
    expect(await repo.prunePhoneCodes(retentionCutoff(new Date(), PHONE_CODE_RETENTION_DAYS))).toBe(0);
    expect(await repo.usePhoneCode('77001112233', 'live', new Date())).toBe('ok');
  });
});

describe('login attempts — weeks, not years, and BOTH tables', () => {
  it('sweeps user_login_attempts and staff_login_attempts together', async () => {
    const repo = createMemoryRepository();
    // user_login_attempts (the app's phone sign-in)
    await withClockAt(daysAgo(120), () => repo.recordPhoneClaim('77001112233'));
    await withClockAt(daysAgo(2), () => repo.recordPhoneClaim('77001112233'));
    // staff_login_attempts (the back office)
    await withClockAt(daysAgo(120), () => repo.recordLoginAttempt('77073452244', false));
    await withClockAt(daysAgo(2), () => repo.recordLoginAttempt('77073452244', false));

    // Two rows, one from each table. One method because it is one decision:
    // two would let a later edit move one period and forget the other.
    expect(await repo.pruneLoginAttempts(cutoffFor(LOGIN_ATTEMPT_RETENTION_DAYS))).toBe(2);

    const since = new Date(Date.parse(daysAgo(365)));
    expect(await repo.recentPhoneClaims('77001112233', since)).toBe(1);
    expect(await repo.recentFailedLogins('77073452244', since)).toBe(1);
  });

  it('leaves the window rate-limiting actually reads completely alone', async () => {
    // The lock-out window is minutes. If this sweep ever reached into it, five
    // wrong guesses would stop being five wrong guesses.
    const repo = createMemoryRepository();
    for (let i = 0; i < 5; i++) await repo.recordLoginAttempt('77073452244', false);
    await repo.pruneLoginAttempts(retentionCutoff(new Date(), LOGIN_ATTEMPT_RETENTION_DAYS));
    expect(await repo.recentFailedLogins('77073452244', new Date(Date.now() - 900_000))).toBe(5);
  });

  it('exactly 90 days old is still inside the window', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(LOGIN_ATTEMPT_RETENTION_DAYS), () =>
      repo.recordPhoneClaim('77001112233'));
    expect(await repo.pruneLoginAttempts(cutoffFor(LOGIN_ATTEMPT_RETENTION_DAYS))).toBe(0);
    expect(await repo.recentPhoneClaims('77001112233', new Date(Date.parse(daysAgo(365))))).toBe(1);
  });
});

describe('shop_leads — a name and a phone from the landing form', () => {
  it('a lead nobody acted on in a year goes; a recent one stays', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(400), () =>
      repo.recordShopLead({ customerName: 'Айгерім', phone: '+7 700 111 22 33' }));
    await withClockAt(daysAgo(30), () =>
      repo.recordShopLead({ customerName: 'Мадина', phone: '+7 700 765 43 21' }));

    expect(await repo.pruneShopLeads(cutoffFor(SHOP_LEAD_RETENTION_DAYS))).toBe(1);
    const left = await repo.adminShopLeads(50);
    expect(left.map((l) => l.customerName)).toEqual(['Мадина']);
    // The counter the Магазин tab prints counts the whole table, so it has to
    // move with the sweep rather than stay on a number that is no longer true.
    expect(await repo.shopLeadCounts()).toEqual({ total: 1, uncalled: 1 });
  });

  it('exactly 365 days old is still inside the window', async () => {
    const repo = createMemoryRepository();
    await withClockAt(daysAgo(SHOP_LEAD_RETENTION_DAYS), () =>
      repo.recordShopLead({ customerName: 'Айгерім', phone: '+7 700 111 22 33' }));
    expect(await repo.pruneShopLeads(cutoffFor(SHOP_LEAD_RETENTION_DAYS))).toBe(0);
    expect((await repo.adminShopLeads(50)).length).toBe(1);
  });
});

describe('support — three years, measured from the last thing that happened', () => {
  const ticket = (subject: string) =>
    ({ phone: '+7 700 111 22 33', customerName: 'Айгерім', subject, body: 'Текст обращения' });

  it('a thread nobody has touched in three years goes, replies and all', async () => {
    const repo = createMemoryRepository();
    const oldId = await withClockAt(daysAgo(1200), async () => {
      const id = await repo.createSupportTicket(ticket('Старое обращение'));
      await repo.addSupportReply({ ticketId: id, author: 'staff', staffId: 's1', body: 'Ответили' });
      return id;
    });
    const freshId = await withClockAt(daysAgo(30), () =>
      repo.createSupportTicket(ticket('Свежее обращение')));

    expect(await repo.pruneSupportTickets(cutoffFor(SUPPORT_RETENTION_DAYS))).toBe(1);
    expect(await repo.getSupportTicket(oldId)).toBeNull();
    // The thread goes with it, as support_replies ON DELETE CASCADE does.
    expect(await repo.listSupportReplies(oldId)).toEqual([]);
    expect(await repo.getSupportTicket(freshId)).not.toBeNull();
  });

  it('a long conversation does not lose its beginning while its end is live', async () => {
    // The one that would be easy to get wrong: an old ticket row whose thread
    // is still being answered. Sweeping on created_at would delete the opening
    // message of a live dispute — and take every reply with it.
    const repo = createMemoryRepository();
    const id = await withClockAt(daysAgo(1200), () =>
      repo.createSupportTicket(ticket('Спор о доставке')));
    await withClockAt(daysAgo(5), () =>
      repo.addSupportReply({ ticketId: id, author: 'customer', body: 'Всё ещё жду' }));

    expect(await repo.pruneSupportTickets(cutoffFor(SUPPORT_RETENTION_DAYS))).toBe(0);
    expect(await repo.getSupportTicket(id)).not.toBeNull();
    expect((await repo.listSupportReplies(id)).length).toBe(1);
  });

  it('exactly three years since the last activity is still inside the window', async () => {
    const repo = createMemoryRepository();
    const id = await withClockAt(daysAgo(SUPPORT_RETENTION_DAYS), () =>
      repo.createSupportTicket(ticket('Ровно на границе')));
    expect(await repo.pruneSupportTickets(cutoffFor(SUPPORT_RETENTION_DAYS))).toBe(0);
    expect(await repo.getSupportTicket(id)).not.toBeNull();
  });

  it('one thread going does not take the next one with it', async () => {
    const repo = createMemoryRepository();
    const doomed = await withClockAt(daysAgo(1200), () => repo.createSupportTicket(ticket('Старое')));
    const kept = await withClockAt(daysAgo(1200), () => repo.createSupportTicket(ticket('Тоже старое')));
    await withClockAt(daysAgo(1), () =>
      repo.addSupportReply({ ticketId: kept, author: 'staff', staffId: 's1', body: 'Отвечаем' }));

    expect(await repo.pruneSupportTickets(cutoffFor(SUPPORT_RETENTION_DAYS))).toBe(1);
    expect(await repo.getSupportTicket(doomed)).toBeNull();
    expect(await repo.getSupportTicket(kept)).not.toBeNull();
    expect((await repo.listSupportReplies(kept)).length).toBe(1);
  });
});

describe('nothing sweeps what was decided to keep', () => {
  it('an order and its lines survive every sweep, at any age', async () => {
    // RK requires retention of primary accounting documents and nobody here can
    // cite the exact term, so no code deletes one. This is the assertion that
    // stops a future "while we are in here" from adding orders to the schedule.
    const repo = createMemoryRepository();
    const before = (await repo.adminShopOrders(200)).length;
    await sweepAll(repo, NOW);
    expect((await repo.adminShopOrders(200)).length).toBe(before);
  });

  it('a health record survives every sweep — it goes with the account, not a clock', async () => {
    const repo = createMemoryRepository();
    await repo.upsertDayLog(DEMO_USER, {
      date: '2020-01-01', mood: 'ok', symptoms: [], kicks: 0, flow: null, note: 'старая запись',
    });
    await sweepAll(repo, NOW);
    const days = await repo.listDayLogs(DEMO_USER, '2019-01-01', '2030-01-01');
    expect(days.length, 'a diary entry was swept on a clock it has no period for').toBe(1);
  });
});

describe('the whole schedule runs, on its own periods', () => {
  it('every table is swept, each with its own cutoff', async () => {
    const seen: Array<{ table: string; cutoff: string }> = [];
    const spy = (table: string) => async (cutoff: string) => {
      seen.push({ table, cutoff });
      return 0;
    };
    const deps: RetentionDeps = {
      pruneLocationHistory: spy('location_history'),
      pruneGeofenceEvents: spy('geofence_events'),
      pruneSafetyAlerts: spy('safety_alerts'),
      pruneAuditLog: spy('audit_log'),
      prunePhoneCodes: spy('phone_codes'),
      pruneLoginAttempts: spy('login_attempts'),
      pruneShopLeads: spy('shop_leads'),
      pruneSupportTickets: spy('support_tickets'),
    };

    const results = await sweepAll(deps, NOW);
    expect(results.map((r) => r.table)).toEqual(RETENTION_SWEEPS.map((s) => s.table));
    // Each sweep got the cutoff for ITS period. One shared cutoff would be the
    // catastrophic version of this feature: audit's three years applied to
    // location history, or location's ninety days applied to support.
    for (const s of RETENTION_SWEEPS) {
      const hit = seen.find((x) => x.table === s.table);
      expect(hit, `${s.table} was never swept`).toBeDefined();
      expect(hit!.cutoff, `${s.table} swept on the wrong period`).toBe(cutoffFor(s.days));
    }
  });

  it('one table failing does not stop the rest', async () => {
    // The first thing a sick database does is break whichever table happens to
    // be first in the list. Losing seven sweeps to one bad night is how
    // retention quietly stops.
    const ran: string[] = [];
    const ok = (t: string) => async () => { ran.push(t); return 0; };
    const results = await sweepAll(
      {
        pruneLocationHistory: async () => { throw new Error('connection reset'); },
        pruneGeofenceEvents: ok('geofence_events'),
        pruneSafetyAlerts: ok('safety_alerts'),
        pruneAuditLog: ok('audit_log'),
        prunePhoneCodes: ok('phone_codes'),
        pruneLoginAttempts: ok('login_attempts'),
        pruneShopLeads: ok('shop_leads'),
        pruneSupportTickets: ok('support_tickets'),
      },
      NOW,
    );
    expect(ran.length).toBe(7);
    const failed = results.find((r) => r.table === 'location_history')!;
    expect(failed.error).toBe('connection reset');
    // And the failure names the table, or a log line cannot say what broke.
    expect(results.filter((r) => r.error).map((r) => r.table)).toEqual(['location_history']);
  });
});

describe('the server starts all of them', () => {
  it('a built server sweeps every table without anybody asking', async () => {
    // The defect this replaces was never a missing DELETE — it was a DELETE
    // nobody called. Wiring is the whole point, so it is asserted against a
    // real buildServer rather than the scheduler in isolation.
    const repo = createMemoryRepository();
    const swept = new Set<string>();
    const spies: Record<string, string> = {
      pruneLocationHistory: 'location_history',
      pruneGeofenceEvents: 'geofence_events',
      pruneSafetyAlerts: 'safety_alerts',
      pruneAuditLog: 'audit_log',
      prunePhoneCodes: 'phone_codes',
      pruneLoginAttempts: 'login_attempts',
      pruneShopLeads: 'shop_leads',
      pruneSupportTickets: 'support_tickets',
    };
    const watched = new Proxy(repo, {
      get(target, prop: string) {
        if (prop in spies) return async () => { swept.add(spies[prop]); return 0; };
        return (target as unknown as Record<string, unknown>)[prop];
      },
    }) as Repository;

    const app = buildServer(
      {
        repo: watched,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => null,
      },
      { logger: false },
    );
    await app.ready();
    await vi.waitFor(() =>
      expect([...swept].sort()).toEqual(RETENTION_SWEEPS.map((s) => s.table).sort()));
    await app.close();
  });
});

describe('the Postgres half, as far as it can be checked without Postgres', () => {
  /**
   * Every sweep above runs against the in-memory repository, because that is
   * the one a test can drive. pgRepository.ts is the implementation that
   * actually deletes a real family's rows and NOTHING in this suite executes
   * it — the same gap pgSchema.test.ts exists to narrow.
   *
   * So this reads the source. It cannot prove the DELETEs work; it can prove
   * the two mistakes that would be catastrophic and are invisible until they
   * have already happened: a boundary that is `<=` instead of `<` (deleting a
   * day early, every day), and a DELETE aimed at a table that was decided to
   * be KEPT.
   */
  const src = readFileSync(
    fileURLToPath(new URL('../db/pgRepository.ts', import.meta.url)),
    'utf8',
  )
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/^\s*\/\/.*$/gm, ' ');

  const deletes = [...src.matchAll(/DELETE\s+FROM\s+([a-z_][a-z0-9_]*)([^`';]*)/gi)]
    .map((m) => ({ table: m[1].toLowerCase(), tail: m[2] }));

  it('deletes from every table the schedule names', () => {
    // login_attempts is two real tables under one decision; support_replies
    // goes through the ticket's CASCADE rather than a DELETE of its own.
    const expected = [
      'location_history', 'geofence_events', 'safety_alerts', 'audit_log',
      'phone_codes', 'user_login_attempts', 'staff_login_attempts',
      'shop_leads', 'support_tickets',
    ];
    for (const t of expected) {
      expect(deletes.some((d) => d.table === t), `nothing deletes from ${t}`).toBe(true);
    }
  });

  it('never uses <= on a retention cutoff', () => {
    // A row exactly at the period is still inside it. `<=` deletes a day early
    // — quietly, for ever, and in the direction nothing can undo.
    for (const t of ['location_history', 'geofence_events', 'safety_alerts', 'audit_log',
      'phone_codes', 'user_login_attempts', 'staff_login_attempts', 'shop_leads']) {
      const d = deletes.find((x) => x.table === t)!;
      expect(d.tail, `${t} sweeps on <= rather than <`).toContain('< $1');
      expect(d.tail, `${t} sweeps on <=`).not.toContain('<= $1');
    }
  });

  it('sweeps phone_codes on created_at, not on expires_at', () => {
    // A code expires in minutes. Sweeping on expiry measures the thirty days
    // from the wrong instant and silently keeps the row a month longer.
    const d = deletes.find((x) => x.table === 'phone_codes')!;
    expect(d.tail).toContain('created_at');
    expect(d.tail).not.toContain('expires_at');
  });

  it('no DELETE ever aims at an order', () => {
    // The decision that must not be quietly reversed by a later "while we are
    // in here". These are accounting records on a term nobody can cite.
    for (const d of deletes) {
      expect(d.table, 'something deletes an accounting record').not.toMatch(/^shop_order/);
    }
  });
});
