/**
 * The pregnancy calendar, as edited.
 *
 * Frame 14a «40 недель» + 14b «Редактор недели». The week-by-week calendar is
 * the only content every pregnant user of this app sees, and it shipped as a
 * compiled-in JSON file: fixing a typo in week 22 meant a release. This module
 * is the seam that makes it editable without giving up the property that made
 * the file worth having — a phone with no signal still opens week 22.
 *
 * The rule, in one line: **the contract is the baseline, the database is a
 * patch.** Nothing here ever removes a week. An override replaces a week's
 * fields; drop every row and the served calendar is byte-for-byte the shipped
 * one again.
 *
 * PURE: contract in, rows in, calendar out. No repository, no clock, no
 * Fastify — so the merge is exercised by unit tests and by the route tests
 * without a database between them.
 */

import type { PregnancyCalendar, PregnancyWeek, PregnancyWeekText } from './weeks.js';
import type { ReviewableItem } from '../content/medicalReview.js';

/** One edited week, as the repository stores it. */
export interface PregnancyWeekOverride {
  week: number;
  /** Null means "leave the contract's value alone" — see [mergeWeeks]. */
  lengthCm: string | null;
  hcg: string | null;
  ru: PregnancyWeekText;
  kk: PregnancyWeekText;
  /** Work in progress: stored, never served. */
  draft: boolean;
  review: { by: string; at: string; fingerprint: string } | null;
  /** Save counter; the served version is contract + Σ rev. */
  rev: number;
  updatedAt: string;
  updatedBy: string | null;
}

/**
 * Contract + overrides, in the shape the app and the panel already read.
 *
 * Drafts are skipped. That is what makes the medical-review rule workable
 * rather than a wall: half-written advice about a pregnancy has somewhere to
 * live that is not a private document, and the reader keeps seeing the last
 * text a clinician signed.
 *
 * `lengthCm` and `hcg` fall back to the contract when the override leaves them
 * null. An editor who rewrites the prose of week 22 has not thereby asserted
 * that the baby is no longer 27 cm long, and blanking those two chips because
 * a form field was empty is exactly the kind of silent data loss this whole
 * table exists to avoid. Prose is different — `ru` and `kk` are always
 * complete in a stored row, because the route will not accept a partial one.
 *
 * The version moves whenever the table moves: `contract.version + Σ rev` over
 * ALL rows, drafts included. Drafting a week changes what readers see (the
 * contract shows through again), so it has to count. `rev` only ever grows and
 * rows are never deleted, so the number is monotonic — a client caching by
 * version can trust it.
 */
export function mergeWeeks(
  base: PregnancyCalendar,
  overrides: PregnancyWeekOverride[],
): PregnancyCalendar {
  const byWeek = new Map(overrides.map((o) => [o.week, o]));
  const weeks: PregnancyWeek[] = base.weeks.map((w) => {
    const o = byWeek.get(w.week);
    if (!o || o.draft) return w;
    return {
      week: w.week,
      lengthCm: o.lengthCm ?? w.lengthCm,
      hcg: o.hcg ?? w.hcg,
      ru: { ...o.ru },
      kk: { ...o.kk },
    };
  });
  const bump = overrides.reduce((t, o) => t + (Number.isFinite(o.rev) ? o.rev : 0), 0);
  return { version: base.version + bump, weeks };
}

/**
 * A week, as the medical-review machinery sees it.
 *
 * content/medicalReview.ts fingerprints `title`, `summary`, `url` and `video`
 * — the shape a timeline card has. A calendar week is not a card, so rather
 * than a second fingerprint function that could drift from the first, the week
 * is projected onto that shape ONCE, here, and every rule
 * (`unreviewed`, `carryReview`, `textFingerprint`) then applies unchanged.
 *
 * What matters is that everything a clinician read is inside the projection.
 * The prose obviously is. So are `lengthCm` and hCG, carried in `url`: those
 * two chips are the numeric half of the advice, and a reviewed page whose hCG
 * range was edited afterwards is unreviewed advice under a reviewed headline.
 * `url` is a free string to the fingerprint, and using it this way keeps the
 * numbers inside the signature instead of beside it.
 *
 * `medical: true` unconditionally. Every week of this calendar tells a
 * pregnant woman what is happening to her body and when to act — there is no
 * non-medical half of it to exempt.
 *
 * `base` is the contract's week, and passing it is what makes the signature
 * describe what a READER sees rather than what a row happens to hold. A stored
 * null means "leave the contract's number alone" ([mergeWeeks]), so a row with
 * `lengthCm: null` and a row with `lengthCm: '27,8'` put the same 27,8 on the
 * same phone — and must therefore fingerprint the same. Without the fallback
 * they do not, and the panel, which reads the MERGED value out of
 * `GET /admin/pregnancy/weeks` and posts it back, can never reproduce the
 * signature a clinician just gave: every publish comes back 409 «stale», every
 * re-approval recomputes the same unreachable null-based fingerprint, and the
 * week is unpublishable for good.
 */
export function weekAsReviewable(
  week: number,
  v: {
    lengthCm: string | null;
    hcg: string | null;
    ru: PregnancyWeekText;
    kk: PregnancyWeekText;
    draft: boolean;
  },
  base?: { lengthCm: string; hcg: string } | null,
): ReviewableItem {
  return {
    id: `week-${week}`,
    medical: true,
    draft: v.draft,
    title: { ru: v.ru.baby, kk: v.kk.baby },
    summary: {
      ru: `${v.ru.you}\n${v.ru.recommend}`,
      kk: `${v.kk.you}\n${v.kk.recommend}`,
    },
    url: `len=${v.lengthCm ?? base?.lengthCm ?? ''};hcg=${v.hcg ?? base?.hcg ?? ''}`,
  };
}

/**
 * Which gestational week a due date puts a mother in, today.
 *
 * The same arithmetic as the dashboard's stage histogram: forty weeks minus
 * the whole weeks still to run, clamped into 1..40. Whole DAYS on both sides —
 * comparing a yyyy-MM-dd parsed as UTC midnight against a local `new Date()`
 * lands a mother one week out, and a count that is a week out is worse than no
 * count, because it blesses an answer the database never gave.
 *
 * Null when she is not pregnant as far as this record knows: no due date, or
 * one already past. An overdue mother is deliberately not counted into week 40
 * — she is no longer someone an edit to week 40 reaches first, and quietly
 * folding her in would inflate the number the editor is asked to trust.
 */
export function gestationalWeekOn(dueDate: string, todayUtcMs: number): number | null {
  const [y, m, d] = dueDate.slice(0, 10).split('-').map(Number);
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return null;
  const due = Date.UTC(y, m - 1, d);
  if (due < todayUtcMs) return null;
  const daysLeft = Math.round((due - todayUtcMs) / 86_400_000);
  return Math.max(1, Math.min(40, 40 - Math.floor(daysLeft / 7)));
}

/** Today at UTC midnight, from a clock's local calendar date. */
export function utcMidnightOf(now: Date): number {
  return Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
}
