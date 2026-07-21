/**
 * A deterministic synthetic user base for the in-memory repository.
 *
 * The memory repo exists so the backend boots with no Postgres, and it models
 * exactly one user — which is fine for the app but leaves the admin overview
 * showing "1 user, 0% retention" and nothing to review. Real endpoints and keys
 * are not wired yet, so this is the test data the dashboard is developed
 * against.
 *
 * Deterministic on purpose. A dashboard whose numbers change on every reload is
 * impossible to check a chart against, and impossible to write a test for. The
 * generator below is a seeded LCG, so the same day always produces the same
 * population.
 *
 * NOT used when DATABASE_URL is set: the pg repository computes these metrics
 * from real rows.
 */

import type { BiEvent, BiEventKind, BiUser } from './biMetrics.js';

/**
 * Numerical Recipes LCG. Small, dependency-free, and stable across Node
 * versions — Math.random would make every reload disagree with the last.
 */
function lcg(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(1664525, s) + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

export interface SyntheticPopulation {
  users: BiUser[];
  events: BiEvent[];
  devices: { total: number; online: number };
}

/**
 * Build a population of [userCount] accounts acquired over [historyDays].
 *
 * The shape is meant to be plausible rather than flattering: signups grow
 * slowly, a third of accounts churn within a fortnight, and daily activity is
 * higher midweek. If the demo data looked perfect, nobody would notice the
 * dashboard rendering a bad number as though it were a good one.
 */
export function buildSyntheticPopulation(
  now: Date,
  { userCount = 260, historyDays = 90, seed = 20260721 } = {},
): SyntheticPopulation {
  const rnd = lcg(seed);
  const users: BiUser[] = [];
  const events: BiEvent[] = [];
  const dayMs = 86400000;
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());

  for (let i = 0; i < userCount; i++) {
    // Signups skewed towards recent days — what a growing product looks like.
    // The exponent is 1.35 rather than 2: squaring piled a tenth of the whole
    // base onto today, and since a user is nearly always active on the day
    // they sign up, that produced a DAU spike at the right edge of every chart
    // that looked like a launch rather than an artefact of the generator.
    const daysAgo = Math.floor(historyDays * rnd() ** 1.35);
    const signup = today - daysAgo * dayMs + Math.floor(rnd() * dayMs);
    const id = `synthetic-${i.toString().padStart(4, '0')}`;
    users.push({ id, createdAt: new Date(signup).toISOString() });

    // How long they stayed, and how often they opened the app while they did.
    const churnRoll = rnd();
    const lifespan =
      churnRoll < 0.33 ? Math.floor(rnd() * 14) : Math.floor(14 + rnd() * (daysAgo + 7));
    const intensity = 0.25 + rnd() * 0.6; // share of days they show up

    for (let d = 0; d <= Math.min(lifespan, daysAgo); d++) {
      const dayStart = today - (daysAgo - d) * dayMs;
      if (dayStart > today) break;
      const weekday = new Date(dayStart).getUTCDay();
      const weekendDrag = weekday === 0 || weekday === 6 ? 0.7 : 1;
      if (rnd() > intensity * weekendDrag) continue;

      // A day of use is several readings plus the occasional other action.
      const readings = 1 + Math.floor(rnd() * 6);
      for (let r = 0; r < readings; r++) {
        events.push({
          userId: id,
          at: new Date(dayStart + Math.floor(rnd() * dayMs)).toISOString(),
          kind: 'telemetry',
        });
      }
      const extra: Array<[BiEventKind, number]> = [
        ['location', 0.45],
        ['chat', 0.12],
        ['alert', 0.06],
        ['emergency', 0.004],
        ['sos', 0.002],
      ];
      for (const [kind, p] of extra) {
        if (rnd() < p) {
          events.push({
            userId: id,
            at: new Date(dayStart + Math.floor(rnd() * dayMs)).toISOString(),
            kind,
          });
        }
      }
    }
  }

  const devicesTotal = Math.floor(userCount * 0.62);
  return {
    users,
    events,
    devices: { total: devicesTotal, online: Math.floor(devicesTotal * 0.71) },
  };
}
