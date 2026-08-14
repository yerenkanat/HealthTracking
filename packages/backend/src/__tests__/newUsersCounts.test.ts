/**
 * «Новые аккаунты» — сегодня, за 7 дней, за 30.
 *
 * pgRepository has counted all three since the snapshot was written; the memory
 * repository hard-coded them to 0, so the one number a campaign is judged by on
 * its first day could not be produced, demoed or tested without Postgres. A
 * fake that answers 0 to a question the real one answers reads as a working
 * feature nobody is using.
 *
 * These pin the DEFINITIONS the SQL uses, so the two cannot drift:
 *   - «сегодня» is from midnight, not "the last 24 hours";
 *   - 7 and 30 days are rolling windows off the snapshot's own instant;
 *   - the windows are nested, so today's arrival is in all three;
 *   - seed data is not an arrival.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;
beforeEach(() => { repo = createMemoryRepository(); });

const users = (asOf: string) => repo.dashboardSnapshot(asOf).then((s) => s.users);

describe('who arrived, and when', () => {
  it('counts a sign-up today in all three windows', async () => {
    const before = await users(new Date().toISOString());
    expect(before.newToday, 'the demo account is seed data, not an arrival').toBe(0);

    await repo.createUserWithPhone({ phone: '77010000001', displayName: 'Айгерім' });

    const after = await users(new Date().toISOString());
    expect(after.newToday).toBe(1);
    expect(after.new7d).toBe(1);
    expect(after.new30d).toBe(1);
    expect(after.total).toBe(before.total + 1);
  });

  it('does not count her on a snapshot taken before she existed', async () => {
    await repo.createUserWithPhone({ phone: '77010000002', displayName: 'Сәуле' });
    // A month ago nobody had signed up yet, and a count that ignores the
    // snapshot's own instant would report her as having arrived that day.
    const back = await users('2026-07-01T10:00:00.000Z');
    expect(back.newToday).toBe(0);
    expect(back.new30d).toBe(0);
  });

  it('leaves «сегодня» empty on a snapshot dated tomorrow, and keeps her in 7 days', async () => {
    await repo.createUserWithPhone({ phone: '77010000003', displayName: 'Мадина' });
    const tomorrow = new Date(Date.now() + 26 * 3_600_000).toISOString();
    const u = await users(tomorrow);
    // Midnight, not "24 hours ago": somebody who signed up yesterday evening is
    // not part of today's arrivals.
    expect(u.newToday).toBe(0);
    expect(u.new7d).toBe(1);
    expect(u.new30d).toBe(1);
  });

  it('never reports more newcomers than accounts', async () => {
    await repo.createUserWithPhone({ phone: '77010000004', displayName: 'Айнұр' });
    const u = await users(new Date().toISOString());
    expect(u.new30d).toBeLessThanOrEqual(u.total);
    expect(u.newToday).toBeLessThanOrEqual(u.new7d);
    expect(u.new7d).toBeLessThanOrEqual(u.new30d);
  });
});
