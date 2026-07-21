import { describe, it, expect } from 'vitest';
import { computeBiMetrics, dayKey, type BiEvent, type BiUser } from '../analytics/biMetrics.js';

const NOW = new Date('2026-07-21T14:30:00Z');
const day = (offset: number) => new Date(Date.UTC(2026, 6, 21) + offset * 86400000).toISOString();

function user(id: string, daysAgo: number): BiUser {
  return { id, createdAt: day(-daysAgo) };
}
function ev(userId: string, daysAgo: number, kind: BiEvent['kind'] = 'telemetry'): BiEvent {
  return { userId, at: day(-daysAgo), kind };
}
const run = (users: BiUser[], events: BiEvent[]) =>
  computeBiMetrics({ users, events, devices: { total: 0, online: 0 }, now: NOW });

describe('active-user windows', () => {
  const users = [user('a', 40), user('b', 40), user('c', 40), user('d', 40)];

  it('counts DAU as distinct users active today, not events', () => {
    const m = run(users, [ev('a', 0), ev('a', 0), ev('a', 0), ev('b', 0)]);
    expect(m.dau).toBe(2);
  });

  it('windows are inclusive of today and of the far edge', () => {
    // 6 days ago is the seventh day counting today, so it is inside WAU.
    expect(run(users, [ev('a', 6)]).wau).toBe(1);
    expect(run(users, [ev('a', 7)]).wau).toBe(0);
    expect(run(users, [ev('a', 29)]).mau).toBe(1);
    expect(run(users, [ev('a', 30)]).mau).toBe(0);
  });

  it('a user active on several days counts once per window', () => {
    const m = run(users, [ev('a', 0), ev('a', 3), ev('a', 20)]);
    expect(m.dau).toBe(1);
    expect(m.wau).toBe(1);
    expect(m.mau).toBe(1);
  });

  it('stickiness is DAU/MAU', () => {
    const m = run(users, [ev('a', 0), ev('b', 5), ev('c', 20), ev('d', 25)]);
    expect(m.dau).toBe(1);
    expect(m.mau).toBe(4);
    expect(m.stickiness).toBe(0.25);
  });

  it('divides by zero without producing NaN or Infinity', () => {
    const m = run([], []);
    expect(m.stickiness).toBe(0);
    expect(m.activeRate).toBe(0);
    expect(m.engagement.eventsPerActiveUser).toBe(0);
    expect(m.retention.d7.rate).toBe(0);
    expect(Number.isFinite(m.stickiness)).toBe(true);
  });

  it('ignores events from users with no signup record', () => {
    // Counting a ghost in DAU while retention cannot place them in a cohort
    // makes two numbers on the same screen disagree.
    const m = run([user('a', 10)], [ev('a', 0), ev('ghost', 0)]);
    expect(m.dau).toBe(1);
    expect(m.mau).toBe(1);
  });

  it('ignores unparseable timestamps rather than throwing', () => {
    const m = run([user('a', 10)], [{ userId: 'a', at: 'not-a-date', kind: 'telemetry' }]);
    expect(m.dau).toBe(0);
  });
});

describe('UTC day bucketing', () => {
  it('buckets late-evening and early-morning UTC events into their own days', () => {
    const users = [user('a', 5)];
    const m = computeBiMetrics({
      users,
      events: [
        { userId: 'a', at: '2026-07-21T23:59:00Z', kind: 'telemetry' },
        { userId: 'a', at: '2026-07-20T00:01:00Z', kind: 'telemetry' },
      ],
      devices: { total: 0, online: 0 },
      now: NOW,
    });
    expect(m.dau).toBe(1);
    const series = Object.fromEntries(m.dauSeries.map((p) => [p.date, p.value]));
    expect(series['2026-07-21']).toBe(1);
    expect(series['2026-07-20']).toBe(1);
    expect(series['2026-07-19']).toBe(0);
  });

  it('dayKey pads month and day', () => {
    expect(dayKey(new Date('2026-01-05T10:00:00Z'))).toBe('2026-01-05');
  });
});

describe('series', () => {
  it('returns one point per day, oldest first, ending today', () => {
    const m = run([user('a', 40)], [ev('a', 0)]);
    expect(m.dauSeries).toHaveLength(30);
    expect(m.dauSeries[29].date).toBe('2026-07-21');
    expect(m.dauSeries[0].date).toBe('2026-06-22');
    expect(m.signupSeries).toHaveLength(30);
  });

  it('fills quiet days with zero rather than omitting them', () => {
    // A sparkline that skips empty days compresses a gap into a flat line and
    // hides the outage it is there to reveal.
    const m = run([user('a', 40)], [ev('a', 0), ev('a', 10)]);
    expect(m.dauSeries.every((p) => typeof p.value === 'number')).toBe(true);
    expect(m.dauSeries.filter((p) => p.value === 0).length).toBe(28);
  });
});

describe('growth', () => {
  it('counts signups in each window', () => {
    const users = [user('a', 0), user('b', 3), user('c', 6), user('d', 8), user('e', 40)];
    const m = run(users, []);
    expect(m.totalUsers).toBe(5);
    expect(m.newUsers.today).toBe(1);
    expect(m.newUsers.d7).toBe(3); // 0, 3, 6 days ago
    expect(m.newUsers.d30).toBe(4); // adds the one from 8 days ago
  });
});

describe('retention', () => {
  it('counts a user as retained when active on exactly day N after signup', () => {
    // signed up 10 days ago, active the next day → retained at D1
    const m = run([user('a', 10)], [ev('a', 9)]);
    expect(m.retention.d1).toEqual({ rate: 1, cohort: 1 });
  });

  it('does not count activity on a different day as day-N retention', () => {
    const m = run([user('a', 10)], [ev('a', 5)]);
    expect(m.retention.d1.rate).toBe(0);
    expect(m.retention.d7.rate).toBe(0);
  });

  it('excludes users whose day N has not arrived yet from the cohort', () => {
    // Signed up 3 days ago: eligible for D1, not for D7 or D30. Counting them
    // in the D7 denominator would show retention falling every time signups
    // rise — the exact opposite of what happened.
    const m = run([user('a', 3)], [ev('a', 2)]);
    expect(m.retention.d1).toEqual({ rate: 1, cohort: 1 });
    expect(m.retention.d7.cohort).toBe(0);
    expect(m.retention.d30.cohort).toBe(0);
  });

  it('aggregates across cohorts', () => {
    const users = [user('a', 10), user('b', 20), user('c', 30), user('d', 40)];
    // a and b come back on their day 7; c and d do not.
    const m = run(users, [ev('a', 3), ev('b', 13)]);
    expect(m.retention.d7.cohort).toBe(4);
    expect(m.retention.d7.rate).toBe(0.5);
  });

  it('reports the cohort size alongside the rate', () => {
    // 100% off a cohort of one is noise; the dashboard must be able to say so.
    const m = run([user('a', 40)], [ev('a', 39)]);
    expect(m.retention.d1.rate).toBe(1);
    expect(m.retention.d1.cohort).toBe(1);
  });

  it('a user active every day is retained at every checkpoint', () => {
    const events = Array.from({ length: 41 }, (_, i) => ev('a', i));
    const m = run([user('a', 40)], events);
    expect(m.retention.d1.rate).toBe(1);
    expect(m.retention.d7.rate).toBe(1);
    expect(m.retention.d30.rate).toBe(1);
  });
});

describe('engagement and safety', () => {
  it('averages events and active days over MAU', () => {
    const m = run([user('a', 40), user('b', 40)], [ev('a', 0), ev('a', 1), ev('b', 0)]);
    expect(m.mau).toBe(2);
    expect(m.engagement.eventsPerActiveUser).toBe(1.5);
    expect(m.engagement.activeDaysPerUser).toBe(1.5);
  });

  it('breaks events down by kind', () => {
    const m = run([user('a', 40)], [ev('a', 0, 'chat'), ev('a', 1, 'chat'), ev('a', 2, 'alert')]);
    expect(m.engagement.eventMix.chat).toBe(2);
    expect(m.engagement.eventMix.alert).toBe(1);
    expect(m.engagement.eventMix.telemetry).toBe(0);
  });

  it('counts alerts and emergencies in the 7-day window, SOS for all time', () => {
    const m = run(
      [user('a', 60)],
      [ev('a', 1, 'alert'), ev('a', 40, 'alert'), ev('a', 2, 'emergency'), ev('a', 50, 'sos')],
    );
    expect(m.safety.alerts7d).toBe(1);
    expect(m.safety.emergencies7d).toBe(1);
    expect(m.safety.sosAllTime).toBe(1);
  });

  it('does not let engagement averages count events outside the window', () => {
    const m = run([user('a', 60)], [ev('a', 0), ev('a', 45)]);
    expect(m.engagement.eventsPerActiveUser).toBe(1);
  });
});
