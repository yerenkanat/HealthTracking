/**
 * The immunisation calendar as it is actually served: the shipped contract with
 * the back-office's edits on top.
 *
 * One function, used by `GET /vaccination/schedule`, by the public `/api/v1`
 * mirror and by the admin editor, so the three cannot answer differently about
 * when the second pneumococcal dose is due. The merge itself is pure and lives
 * in overrides.ts; this file only adds the repository call and the failure
 * policy.
 *
 * The failure policy is the point. If the database is unreachable, this returns
 * the CONTRACT — not an error, not an empty schedule. Losing the edits costs a
 * parent the newest wording of one row; losing the schedule costs her the whole
 * vaccination screen, on the one topic in this app where the app's job is to
 * say "take the child to the clinic in March". The same reasoning as the app
 * bundling the calendar, applied one layer up.
 */

import { vaccinationSchedule } from './schedule.js';
import {
  mergeSchedule,
  type ServedVaccinationSchedule,
  type ServedVaccine,
  type VaccinationOverride,
  type VaccinationSettings,
} from './overrides.js';

/** Only the pieces of the repository this needs, so tests can pass a stub. */
export interface VaccinationSource {
  vaccinationOverrides(): Promise<VaccinationOverride[]>;
  vaccinationSettings(): Promise<VaccinationSettings | null>;
}

export async function servedVaccinationSchedule(
  repo: VaccinationSource | undefined,
): Promise<ServedVaccinationSchedule> {
  let overrides: VaccinationOverride[] = [];
  let settings: VaccinationSettings | null = null;
  try {
    // Optional-called rather than assumed: several route tests build the server
    // with a bare `{} as Repository`, and a schedule that 500s because nobody
    // stubbed an override table would be a worse answer than the contract.
    overrides = (await repo?.vaccinationOverrides?.()) ?? [];
  } catch {
    overrides = [];
  }
  try {
    settings = (await repo?.vaccinationSettings?.()) ?? null;
  } catch {
    settings = null;
  }
  return mergeSchedule(vaccinationSchedule, overrides, settings);
}

/** One vaccine of the served schedule, by its `<id>/<dose>` key. */
export function vaccineOf(
  schedule: ServedVaccinationSchedule,
  key: string,
): ServedVaccine | null {
  return schedule.vaccines.find((v) => v.key === key) ?? null;
}
