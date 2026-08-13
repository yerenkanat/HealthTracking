/**
 * The comment that guards a day of her data, made executable.
 *
 * `ingestHandler.ts` filters every wearable field through `plausible(v, lo, hi)`
 * and says above it: "Ranges match the table's CHECK constraints exactly."
 * Nothing enforced that. The bounds are written twice — once in TypeScript and
 * once in SQL — and the two files are edited by different people for different
 * reasons.
 *
 * Drift is not cosmetic here, and it is asymmetric:
 *
 *   - Guard WIDER than the constraint → the value passes `plausible`, reaches
 *     the INSERT, and violates the CHECK. The batch-level catch counts the item
 *     `rejected`, so the app resends the same day, for ever. A single
 *     mis-decoded byte at the BLE edge becomes a permanent retry loop draining
 *     the battery of the watch it is trying to read.
 *   - A constrained column with NO guard is the same failure with no warning at
 *     all, which is why this file checks that direction too. Adding a column
 *     with a CHECK and forgetting the guard is the easy mistake — the SQL looks
 *     complete on its own.
 *   - Guard NARROWER than the constraint is the quiet one: no error anywhere,
 *     the metric is simply dropped and the day is stored without it. Nobody
 *     finds out, because "we do not know what it was" is exactly what a missing
 *     value already means.
 *
 * Both sides are PARSED rather than restated. A test that hard-codes 50 and 260
 * in a third place would just be a third thing to drift.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const HANDLER = join(__dirname, '..', 'routes', 'ingestHandler.ts');
const MIGRATIONS = join(__dirname, '..', '..', 'db', 'migrations');

type Bounds = { lo: number; hi: number };

/**
 * Which column each guarded field is written to. Deliberately explicit: the
 * names do NOT convert mechanically (`heartRateAvg` → `hr_avg`,
 * `batteryPercent` → `battery_pct`), and a generated mapping that guessed wrong
 * would compare a field against some other column's constraint and report
 * agreement. It is also the point of review — adding a field forces a line
 * here, and the test below fails until it is added.
 */
const COLUMN_OF: Record<string, string> = {
  stress: 'stress',
  breathRate: 'breath_rate',
  batteryPercent: 'battery_pct',
  heartRateAvg: 'hr_avg',
  heartRateMin: 'hr_min',
  heartRateMax: 'hr_max',
  spo2Avg: 'spo2_avg',
  spo2Min: 'spo2_min',
  systolicAvg: 'systolic_avg',
  diastolicAvg: 'diastolic_avg',
  tempAvgTenths: 'temp_avg_tenths',
  bloodSugarTenths: 'blood_sugar_tenths',
};

/** Every `plausible(w.field, lo, hi)` the ingest handler applies. */
function guards(): Map<string, Bounds> {
  const src = readFileSync(HANDLER, 'utf8');
  const out = new Map<string, Bounds>();
  for (const m of src.matchAll(/plausible\(\s*w\.(\w+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)/g)) {
    out.set(m[1], { lo: Number(m[2]), hi: Number(m[3]) });
  }
  return out;
}

/**
 * Every `col BETWEEN lo AND hi` that applies to `wearable_days`.
 *
 * Scoped per STATEMENT, not per file: a migration touching several tables must
 * not lend another table's bounds to this one. Later migrations win, because
 * 042 drops and re-adds constraints 040 created — reading the files in name
 * order reproduces what the database actually ended up with.
 */
function constraints(): Map<string, Bounds> {
  const out = new Map<string, Bounds>();
  for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = readFileSync(join(MIGRATIONS, file), 'utf8');
    for (const stmt of sql.split(';')) {
      if (!/wearable_days/.test(stmt)) continue;
      for (const m of stmt.matchAll(/(\w+)\s+BETWEEN\s+(-?\d+)\s+AND\s+(-?\d+)/gi)) {
        out.set(m[1], { lo: Number(m[2]), hi: Number(m[3]) });
      }
    }
  }
  return out;
}

describe('wearable bounds: the guard and the constraint are one decision', () => {
  // A regex that silently matched nothing would make every assertion below pass
  // by vacuity — the failure mode this whole file exists to prevent.
  it('actually parsed both sides', () => {
    expect(guards().size, 'no plausible() calls found — the parse broke, not the code').toBeGreaterThan(8);
    expect(constraints().size, 'no CHECK bounds found — the parse broke, not the schema').toBeGreaterThan(8);
  });

  it('guards every field against its own column, with identical bounds', () => {
    const g = guards();
    const c = constraints();
    const mismatches: string[] = [];

    for (const [field, bounds] of g) {
      const column = COLUMN_OF[field];
      if (!column) {
        mismatches.push(`${field}: guarded but not named in COLUMN_OF — which column does it reach?`);
        continue;
      }
      const check = c.get(column);
      if (!check) {
        // Not a failure by itself: defence in depth in code with no constraint
        // behind it is legal. It is reported so the asymmetry is a decision.
        continue;
      }
      if (check.lo !== bounds.lo || check.hi !== bounds.hi) {
        mismatches.push(
          `${field} → ${column}: guard ${bounds.lo}–${bounds.hi}, CHECK ${check.lo}–${check.hi}` +
            (bounds.lo < check.lo || bounds.hi > check.hi
              ? ' — WIDER than the constraint: this value passes the guard and fails the INSERT, and the app resends that day for ever'
              : ' — narrower than the constraint: the metric is dropped silently'),
        );
      }
    }
    expect(mismatches, mismatches.join('\n')).toEqual([]);
  });

  it('leaves no constrained column unguarded', () => {
    const guarded = new Set([...guards().keys()].map((f) => COLUMN_OF[f]).filter(Boolean));
    const unguarded = [...constraints().keys()].filter((col) => !guarded.has(col));
    expect(
      unguarded,
      `constrained in SQL but never filtered before the INSERT: ${unguarded.join(', ')}. ` +
        'A value outside the CHECK will fail the write and the client will resend the same day for ever. ' +
        'Add a plausible() call with the same bounds.',
    ).toEqual([]);
  });

  it('names a column for every guard, and guards every column it names', () => {
    // Keeps COLUMN_OF honest in both directions: a stale entry for a field that
    // no longer exists would silently stop checking a real column.
    const fields = [...guards().keys()].sort();
    expect(Object.keys(COLUMN_OF).sort()).toEqual(fields);
  });
});
