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

describe('growth accounting', () => {
  // A flat MAU can be a stable base or heavy churn hidden behind heavy
  // acquisition. Only this split tells them apart, and they call for opposite
  // responses — so each bucket is pinned to a worked example.
  it('sorts actives into new, returning and resurrected', () => {
    const users = [
      user('newcomer', 10), // signed up inside the period
      user('regular', 90), // active in both periods
      user('lapsed', 90), // active long ago, back now
      user('gone', 90), // active last period only
    ];
    const events = [
      ev('newcomer', 5),
      ev('regular', 5),
      ev('regular', 40), // previous period too
      ev('lapsed', 3),
      ev('lapsed', 75), // before the previous period began
      ev('gone', 40),
    ];
    const g = run(users, events).growth;
    expect(g.new).toBe(1);
    expect(g.returning).toBe(1);
    expect(g.resurrected).toBe(1);
    expect(g.churned).toBe(1);
    expect(g.periodDays).toBe(30);
  });

  it('the three inbound buckets add up to the current period actives', () => {
    const users = Array.from({ length: 12 }, (_, i) => user(`u${i}`, i * 7));
    const events = users.flatMap((u, i) => [ev(u.id, i * 2), ev(u.id, 35 + i)]);
    const m = run(users, events);
    const g = m.growth;
    expect(g.new + g.returning + g.resurrected).toBe(m.mau);
  });

  it('net is the change in actives between the two periods', () => {
    // One user active only now, two active only before.
    const users = [user('a', 90), user('b', 90), user('c', 90)];
    const g = run(users, [ev('a', 2), ev('b', 40), ev('c', 40)]).growth;
    expect(g.churned).toBe(2);
    expect(g.net).toBe(1 - 2);
    expect(g.churnRate).toBe(1); // both of the previous period's actives left
  });

  it('reports no churn rather than a divide-by-zero on an empty history', () => {
    const g = run([user('a', 1)], [ev('a', 0)]).growth;
    expect(g.churnRate).toBe(0);
    expect(g.churned).toBe(0);
  });
});

describe('module adoption', () => {
  // Counts of USERS, not events. Telemetry arrives on a timer whether or not
  // anyone opens the app, so an event-weighted mix says which module is
  // noisiest and calls it the most used.
  it('counts users per module, not their event volume', () => {
    const users = [user('a', 40), user('b', 40)];
    const events = [
      ...Array.from({ length: 500 }, () => ev('a', 1, 'telemetry')),
      ev('a', 1, 'chat'),
      ev('b', 1, 'chat'),
    ];
    const m = run(users, events);
    expect(m.adoption.telemetry.users).toBe(1);
    expect(m.adoption.chat.users).toBe(2);
    // The mix still reports the volume — it is just not what adoption means.
    expect(m.engagement.eventMix.telemetry).toBe(500);
  });

  it('expresses reach as a share of the active base', () => {
    const users = [user('a', 40), user('b', 40), user('c', 40), user('d', 40)];
    const m = run(users, [ev('a', 1, 'sos'), ev('b', 1), ev('c', 1), ev('d', 1)]);
    expect(m.mau).toBe(4);
    expect(m.adoption.sos.share).toBe(0.25);
  });

  it('names every module even when one is unused, rather than omitting it', () => {
    const m = run([user('a', 40)], [ev('a', 1)]);
    expect(m.adoption.emergency).toEqual({ users: 0, share: 0 });
  });
});

describe('activation funnel', () => {
  it('each stage is a subset of the one above it', () => {
    const users = Array.from({ length: 20 }, (_, i) => user(`u${i}`, 30));
    // u0..u9 activated; of those u0..u4 have three active days; u0..u2 recent.
    const events = [
      ...Array.from({ length: 10 }, (_, i) => ev(`u${i}`, 20)),
      ...Array.from({ length: 5 }, (_, i) => [ev(`u${i}`, 19), ev(`u${i}`, 18)]).flat(),
      ...Array.from({ length: 3 }, (_, i) => ev(`u${i}`, 1)),
    ];
    const f = run(users, events).funnel;
    expect(f.map((s) => s.key)).toEqual(['signed_up', 'activated', 'habit', 'retained']);
    const n = f.map((s) => s.users);
    expect(n).toEqual([20, 10, 5, 3]);
    for (let i = 1; i < n.length; i++) expect(n[i]).toBeLessThanOrEqual(n[i - 1]);
  });

  it('excludes accounts younger than a week', () => {
    // Someone who signed up this morning has not failed to form a habit.
    // Counting them makes every good acquisition day look like a regression.
    const users = [user('old', 30), user('yesterday', 1)];
    const f = run(users, [ev('old', 5)]).funnel;
    expect(f[0].users).toBe(1);
    expect(f[1].ofPrevious).toBe(1);
  });

  it('reports zero conversion rather than NaN when nobody is eligible yet', () => {
    const f = run([user('fresh', 0)], []).funnel;
    expect(f[0].users).toBe(0);
    expect(f.every((s) => Number.isFinite(s.ofPrevious) && Number.isFinite(s.ofCohort))).toBe(true);
  });
});

describe('trend series', () => {
  it('the rolling week smooths the sawtooth DAU has', () => {
    const users = [user('a', 40), user('b', 40)];
    // Active on two days three days apart: DAU is spiky, the rolling week is not.
    const m = run(users, [ev('a', 5), ev('b', 2)]);
    const last = m.wauSeries[m.wauSeries.length - 1];
    expect(last.value).toBe(2); // both fall inside the trailing 7 days
    expect(m.dauSeries[m.dauSeries.length - 1].value).toBe(0);
    expect(m.wauSeries).toHaveLength(m.dauSeries.length);
    expect(last.date).toBe(dayKey(NOW));
  });

  it('the rolling week agrees with the WAU headline on the last point', () => {
    const users = Array.from({ length: 8 }, (_, i) => user(`u${i}`, 40));
    const m = run(users, users.map((u, i) => ev(u.id, i)));
    expect(m.wauSeries[m.wauSeries.length - 1].value).toBe(m.wau);
  });

  it('the retention curve starts at signup day and agrees with the headlines', () => {
    const users = Array.from({ length: 10 }, (_, i) => user(`u${i}`, 40));
    const events = users.flatMap((u) => [ev(u.id, 40), ev(u.id, 39), ev(u.id, 33)]);
    const m = run(users, events);
    expect(m.retentionCurve).toHaveLength(31);
    expect(m.retentionCurve[0].day).toBe(0);
    expect(m.retentionCurve[0].rate).toBe(1); // everyone acts on signup day
    expect(m.retentionCurve[1]).toMatchObject(m.retention.d1);
    expect(m.retentionCurve[7]).toMatchObject(m.retention.d7);
    expect(m.retentionCurve[30]).toMatchObject(m.retention.d30);
  });

  it('carries the cohort size at every point, so a small-N spike is visible', () => {
    const m = run([user('a', 3)], [ev('a', 3)]);
    // Day 30 has not arrived for this account, so its cohort is empty — and a
    // rate of 0 off a cohort of 0 must not read as a collapse.
    expect(m.retentionCurve[30]).toEqual({ day: 30, rate: 0, cohort: 0 });
    expect(m.retentionCurve[0].cohort).toBe(1);
  });
});
