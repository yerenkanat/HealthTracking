/**
 * How much of the calendar has actually happened — frame 15's coverage column.
 *
 * ONE THING TO KNOW BEFORE READING ANY NUMBER THIS FILE PRODUCES:
 *
 *   these figures are **self-reported by mothers in the app**. `child_vaccines`
 *   holds a row because a parent tapped a circle on the vaccination screen.
 *   Nothing in this product reads a polyclinic record, and nothing ever has.
 *
 * So «76 % по пневмококку» here is not national coverage, is not comparable to
 * a Ministry of Health figure, and cannot be quoted as one. It is the share of
 * parents using this app who have ticked that injection off. That is still
 * worth knowing — a dose nobody ticks is either not being given or not being
 * recorded, and both are findable — but the panel labels every one of these
 * numbers «по отметкам мам», and so does this module's output.
 *
 * PURE: a schedule and two histograms in, coverage out. No repository, no
 * clock — the ages are computed by the store, which is the only place that
 * knows what "today" means for a `date` column.
 */

import type { ServedVaccinationSchedule } from './overrides.js';

/**
 * The raw material, aggregated by the store so neither implementation has to
 * ship one row per child.
 *
 * Histograms rather than rows because the thresholds are not knowable in SQL:
 * `atMonth` is contract-plus-overrides and the catch-up window is editable, so
 * the store cannot answer "how many children are past due for pcv/2" without
 * the merge. It answers "how many children are N months old" and "how many
 * N-month-olds have ticked pcv/2" instead, and the arithmetic happens here,
 * over whatever the merge currently says.
 */
export interface VaccinationCoverageData {
  /** Children with a date of birth, by completed age in months. */
  childAges: Array<{ ageMonths: number; n: number }>;
  /** Children who have ticked a vaccine, by key and by the child's age now. */
  ticks: Array<{ key: string; ageMonths: number; n: number }>;
  /**
   * Children with NO date of birth. They cannot be placed on the calendar at
   * all, so they are outside every figure below — reported separately rather
   * than folded into a denominator they would silently depress.
   */
  childrenWithoutDob: number;
}

/** Where one child sits relative to one vaccine. Mirrors the app's VaccineStatus. */
export type VaccineStatusAt = 'upcoming' | 'due' | 'passed';

/**
 * The same three-way split as `vaccineStatus()` in
 * app/lib/domain/vaccination.dart, including its boundaries: `due` runs to the
 * end of the window inclusive, and `passed` starts strictly after it.
 *
 * Deliberately identical rather than approximately so. The panel's «просрочено»
 * column and the app's «стоит наверстать» list are the same claim shown to two
 * different people, and a coverage denominator drawn one month wider than the
 * app's catch-up list would have staff chasing parents whose own screen still
 * says «пора».
 */
export function statusAt(ageMonths: number, atMonth: number, windowMonths: number): VaccineStatusAt {
  if (ageMonths < atMonth) return 'upcoming';
  if (ageMonths <= atMonth + windowMonths) return 'due';
  return 'passed';
}

export interface VaccineCoverage {
  key: string;
  id: string;
  atMonth: number;
  dose: number | null;
  ru: string;
  /** Children old enough that this injection is past its catch-up window. */
  due: number;
  /** ...of whom the mother has ticked it. */
  done: number;
  /** done/due as a percentage, or null when nobody is old enough yet. */
  pct: number | null;
  /** Children not yet at this age — who a change to `atMonth` reaches first. */
  notYet: number;
}

export interface VaccinationCoverageReport {
  /** Children with a date of birth: the population every figure is drawn from. */
  children: number;
  /** ...and the ones that had to be left out, said out loud. */
  childrenWithoutDob: number;
  dueWindowMonths: number;
  vaccines: VaccineCoverage[];
}

/** Total of a histogram over the buckets a predicate accepts. */
function sum(buckets: Array<{ ageMonths: number; n: number }>, keep: (age: number) => boolean): number {
  let t = 0;
  for (const b of buckets) if (keep(b.ageMonths)) t += b.n;
  return t;
}

/**
 * Coverage for every vaccine the schedule currently serves.
 *
 * The denominator is children whose status is `passed` — the injection's age
 * AND its catch-up window have both gone by, so it is one a parent should
 * already have recorded. Children for whom it is still `due` are excluded on
 * purpose: their own screen says «пора», not «наверстать», and counting them as
 * a miss would print a coverage figure that drops every time a cohort has a
 * birthday.
 *
 * The numerator is drawn from the same set. A tick from a child too young to be
 * in the denominator is not counted, so the percentage cannot exceed 100 —
 * which it otherwise would, the moment one organised parent ticked a shot off
 * early.
 */
export function coverageOf(
  schedule: ServedVaccinationSchedule,
  data: VaccinationCoverageData,
): VaccinationCoverageReport {
  const w = schedule.dueWindowMonths;
  const ticksByKey = new Map<string, Array<{ ageMonths: number; n: number }>>();
  for (const t of data.ticks) {
    const list = ticksByKey.get(t.key) ?? [];
    list.push({ ageMonths: t.ageMonths, n: t.n });
    ticksByKey.set(t.key, list);
  }

  return {
    children: sum(data.childAges, () => true),
    childrenWithoutDob: data.childrenWithoutDob,
    dueWindowMonths: w,
    vaccines: schedule.vaccines.map((v) => {
      const past = (age: number) => statusAt(age, v.atMonth, w) === 'passed';
      const due = sum(data.childAges, past);
      const done = sum(ticksByKey.get(v.key) ?? [], past);
      return {
        key: v.key,
        id: v.id,
        atMonth: v.atMonth,
        dose: v.dose ?? null,
        ru: v.ru,
        due,
        done,
        // Null, not 0, when nobody is old enough. «0 %» on a vaccine no child
        // in the database has reached yet reads as a catastrophe rather than as
        // "not applicable", and it is the kind of number that ends up in a
        // slide deck.
        pct: due > 0 ? Math.round((done / due) * 100) : null,
        notYet: sum(data.childAges, (age) => age < v.atMonth),
      };
    }),
  };
}

export interface VaccineImpact {
  key: string;
  atMonth: number;
  /** Children with a date of birth — the population below is drawn from it. */
  total: number;
  /** Children younger than this vaccine's age: the ones an edit reaches first. */
  notYet: number;
  /** Children already past its catch-up window when the change lands. */
  passed: number;
  /**
   * How many children's status actually CHANGES if `atMonth` moves to the
   * proposed value. Null when no proposal was supplied.
   */
  reclassified: number | null;
  proposedAtMonth: number | null;
}

/**
 * What moving one vaccine's age would do — the «затронет N детей» line.
 *
 * Two different numbers, because they answer two different questions and the
 * panel shows both:
 *
 *   `notYet` — children who have not reached this age yet. These are the ones
 *   for whom the edit is simply the schedule, arriving in the future. It is the
 *   figure that says how much of the user base an edit is FOR.
 *
 *   `reclassified` — children whose row on this vaccine flips between
 *   «предстоит», «пора» and «стоит наверстать» the instant the change is
 *   published. This is the one that costs something: a parent who saw «пора» on
 *   Tuesday opens the app on Wednesday and is told she is late. Moving the
 *   pneumococcal booster by a month can silently put thousands of children into
 *   a catch-up list overnight, and nobody should be able to do that without the
 *   count in front of them.
 */
export function impactOf(
  schedule: ServedVaccinationSchedule,
  data: VaccinationCoverageData,
  key: string,
  proposedAtMonth: number | null,
): VaccineImpact | null {
  const v = schedule.vaccines.find((x) => x.key === key);
  if (!v) return null;
  const w = schedule.dueWindowMonths;
  return {
    key,
    atMonth: v.atMonth,
    total: sum(data.childAges, () => true),
    notYet: sum(data.childAges, (age) => age < v.atMonth),
    passed: sum(data.childAges, (age) => statusAt(age, v.atMonth, w) === 'passed'),
    reclassified: proposedAtMonth == null
      ? null
      : sum(data.childAges, (age) =>
        statusAt(age, v.atMonth, w) !== statusAt(age, proposedAtMonth, w)),
    proposedAtMonth,
  };
}

/**
 * The same question for a vaccine that does not exist yet (frame 15a).
 *
 * A brand-new injection at month N lands on every child already past N as
 * «стоит наверстать» — which is a real thing to know before publishing it, and
 * cannot be asked of [impactOf] because the key is not in the schedule.
 */
export function impactOfNew(
  schedule: ServedVaccinationSchedule,
  data: VaccinationCoverageData,
  atMonth: number,
): VaccineImpact {
  const w = schedule.dueWindowMonths;
  return {
    key: '',
    atMonth,
    total: sum(data.childAges, () => true),
    notYet: sum(data.childAges, (age) => age < atMonth),
    passed: sum(data.childAges, (age) => statusAt(age, atMonth, w) === 'passed'),
    // Everybody already at or past the new age changes status, because before
    // this vaccine existed they had no status on it at all.
    reclassified: sum(data.childAges, (age) => age >= atMonth),
    proposedAtMonth: atMonth,
  };
}
