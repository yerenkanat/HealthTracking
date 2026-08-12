/**
 * The calendar as it is actually served: the shipped contract with the
 * back-office's edits on top.
 *
 * One function, used by `GET /pregnancy/weeks`, by the public `/api/v1` mirror
 * and by the admin editor, so the three cannot answer differently about what
 * week 22 says. The merge itself is pure and lives in overrides.ts; this file
 * only adds the repository call and the failure policy.
 *
 * The failure policy is the point. If the database is unreachable, this returns
 * the CONTRACT — not an error, not an empty calendar. Losing the edits costs a
 * reader the newest wording of week 22; losing the calendar costs her the page.
 * The same reasoning as the app bundling the asset, applied one layer up.
 */

import { pregnancyCalendar, type PregnancyCalendar, type PregnancyWeek } from './weeks.js';
import { mergeWeeks, type PregnancyWeekOverride } from './overrides.js';

/** Only the piece of the repository this needs, so tests can pass a stub. */
export interface OverrideSource {
  pregnancyWeekOverrides(): Promise<PregnancyWeekOverride[]>;
}

export async function servedCalendar(repo: OverrideSource | undefined): Promise<PregnancyCalendar> {
  let overrides: PregnancyWeekOverride[] = [];
  try {
    // Optional-called rather than assumed: several route tests build the server
    // with a bare `{} as Repository`, and a calendar that 500s because nobody
    // stubbed an override table would be a worse answer than the contract.
    overrides = (await repo?.pregnancyWeekOverrides?.()) ?? [];
  } catch {
    overrides = [];
  }
  return mergeWeeks(pregnancyCalendar, overrides);
}

/**
 * One week of the served calendar, clamped into the covered range so an early
 * or overdue week still returns the nearest real entry. Null only if the
 * calendar is empty. Same contract as `weekContent`, over merged data.
 */
export function weekOf(calendar: PregnancyCalendar, week: number): PregnancyWeek | null {
  if (calendar.weeks.length === 0) return null;
  const lo = calendar.weeks[0].week;
  const hi = calendar.weeks[calendar.weeks.length - 1].week;
  const w = Math.max(lo, Math.min(hi, Math.round(week)));
  return calendar.weeks.find((x) => x.week === w) ?? null;
}
