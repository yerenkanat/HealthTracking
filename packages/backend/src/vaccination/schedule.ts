/**
 * Childhood immunisation schedule (Kazakhstan) — loaded from the SHARED contract
 * (packages/contract/vaccination_schedule.json), the same file the Dart app
 * asserts against and the admin panel renders. One source of truth so a parent
 * is never told a different schedule in the app than staff see.
 *
 * Served at GET /vaccination/schedule; dueAtMonth() derives which vaccines fall
 * due around a child's age for the admin child view.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export interface Vaccine {
  id: string;
  atMonth: number;
  dose?: number;
  ru: string;
}
export interface VaccinationSchedule {
  version: number;
  dueWindowMonths: number;
  vaccines: Vaccine[];
}

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/vaccination_schedule.json', import.meta.url),
);

export const vaccinationSchedule: VaccinationSchedule = JSON.parse(
  readFileSync(CONTRACT_PATH, 'utf8'),
);

/** Vaccines whose scheduled age has arrived but is still within the catch-up
 * window — i.e. "due now" around [ageMonths]. Mirrors the app's vaccinesDue. */
export function dueAtMonth(ageMonths: number): Vaccine[] {
  const w = vaccinationSchedule.dueWindowMonths;
  return vaccinationSchedule.vaccines.filter(
    (v) => ageMonths >= v.atMonth && ageMonths <= v.atMonth + w,
  );
}

/** All vaccines already scheduled on or before [ageMonths] — the ones that
 * SHOULD have been given by now (for a coverage/overdue view). */
export function dueByMonth(ageMonths: number): Vaccine[] {
  return vaccinationSchedule.vaccines.filter((v) => v.atMonth <= ageMonths);
}
