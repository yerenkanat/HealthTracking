/**
 * Week-by-week pregnancy calendar (ru + kk) — baby development, what the mother
 * feels, and recommendations, per gestational week. Loaded from the SHARED
 * contract (packages/contract/pregnancy_weeks.json, generated from the MoH
 * calendar spreadsheet), the same file the app reads and the admin panel renders.
 *
 * Served at GET /pregnancy/weeks (all) and GET /pregnancy/weeks/:week (one), and
 * used to show a mother's current-week content in the admin patient drawer.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface PregnancyWeekText {
  baby: string;
  you: string;
  recommend: string;
}
export interface PregnancyWeek {
  week: number;
  lengthCm: string;
  hcg: string;
  ru: PregnancyWeekText;
  kk: PregnancyWeekText;
}
export interface PregnancyCalendar {
  version: number;
  weeks: PregnancyWeek[];
}

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/pregnancy_weeks.json', import.meta.url),
);

export const pregnancyCalendar: PregnancyCalendar = JSON.parse(
  readFileSync(CONTRACT_PATH, 'utf8'),
);

/** The lowest and highest weeks the calendar covers. */
export const firstWeek = pregnancyCalendar.weeks[0]?.week ?? 1;
export const lastWeek = pregnancyCalendar.weeks.at(-1)?.week ?? 42;

/**
 * The content for [week], clamped into the covered range so an early or overdue
 * week still returns the nearest real entry rather than null. Null only if the
 * calendar is empty.
 */
export function weekContent(week: number): PregnancyWeek | null {
  if (pregnancyCalendar.weeks.length === 0) return null;
  const w = Math.max(firstWeek, Math.min(lastWeek, Math.round(week)));
  return pregnancyCalendar.weeks.find((x) => x.week === w) ?? null;
}
