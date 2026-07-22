/**
 * Week-by-week baby-development calendar (ru + kk) — WHO weight/height ranges and
 * the motor / speech / cognition milestones for each week of the first year.
 * Loaded from the SHARED contract (packages/contract/baby_development.json,
 * generated from the MoH development spreadsheet), the same file the app reads
 * and the admin panel renders.
 *
 * Served at GET /child/development (all) and GET /child/development/:week (one).
 * Indicative, WHO-standard reference — never a substitute for a paediatrician,
 * which the [note] carries in both languages.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface ChildDevSkills {
  motor: string;
  speech: string;
  cognition: string;
}
export interface ChildDevWeek {
  week: number;
  weightKg: string;
  heightCm: string;
  ru: ChildDevSkills;
  kk: ChildDevSkills;
}
export interface ChildDevCalendar {
  version: number;
  note: { ru: string; kk: string };
  weeks: ChildDevWeek[];
}

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/baby_development.json', import.meta.url),
);

export const childDevCalendar: ChildDevCalendar = JSON.parse(
  readFileSync(CONTRACT_PATH, 'utf8'),
);

/** The lowest and highest weeks the calendar covers. */
export const firstDevWeek = childDevCalendar.weeks[0]?.week ?? 1;
export const lastDevWeek = childDevCalendar.weeks.at(-1)?.week ?? 52;

/**
 * The milestones for [week], clamped into the covered range so a newborn (week
 * 0) or a past-one-year child still returns the nearest real entry rather than
 * null. Null only if the calendar is empty.
 */
export function devWeekContent(week: number): ChildDevWeek | null {
  if (childDevCalendar.weeks.length === 0) return null;
  const w = Math.max(firstDevWeek, Math.min(lastDevWeek, Math.round(week)));
  return childDevCalendar.weeks.find((x) => x.week === w) ?? null;
}
