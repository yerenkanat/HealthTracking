/**
 * The emergency-help scenarios (ru + kk) — app screen 37 «Экстренная помощь»,
 * admin frame 16b.
 *
 * Loaded from the SHARED contract (packages/contract/emergency_help.json), the
 * same file the app bundles as an asset and the admin panel edits. Served at
 * GET /emergency-help, with the back office's edits merged on top — see
 * emergency/served.ts.
 *
 * This is the text somebody reads while deciding whether to call an ambulance.
 * Two consequences run through the whole module:
 *
 *   - it is bundled, not fetched. The one moment this screen is opened is the
 *     one moment a phone may be in a village with no signal.
 *   - `severity` is not decoration. 'red' means dial 103 now and 'amber' means
 *     call the clinic today; the app paints the border-left from it, so a
 *     scenario whose severity is wrong is a scenario that tells somebody to
 *     wait.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** 'red' — call 103 now. 'amber' — call the doctor today. Nothing else. */
export type EmergencySeverity = 'red' | 'amber';

export interface EmergencyText {
  /** What she recognises herself by — the row's headline. */
  title: string;
  /** «Что происходит?» — the signs, in plain words. */
  what: string;
  /** What to do about it, and what not to do. */
  do: string;
}

/**
 * Who a scenario is written for.
 *
 * 'pregnancy' means its own text only applies while she is expecting («после 20
 * недель»); the app hides those from a reader who is not. A clinical property
 * of the scenario, so it comes from the contract and the back office cannot
 * edit it — see mergeEmergencyHelp, which carries it over from the baseline.
 * Absent is 'all', because hiding first aid is the one failure this must not
 * cause.
 */
export type EmergencyAudience = 'all' | 'pregnancy';

export interface EmergencyScenario {
  id: string;
  severity: EmergencySeverity;
  /** Reading order; red before amber in the shipped file. */
  sort: number;
  audience?: EmergencyAudience;
  ru: EmergencyText;
  kk: EmergencyText;
}

export interface EmergencyHelp {
  version: number;
  /** The ambulance number, from the contract rather than a literal in the UI. */
  tel: string;
  scenarios: EmergencyScenario[];
}

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/emergency_help.json', import.meta.url),
);

export const emergencyHelp: EmergencyHelp = JSON.parse(readFileSync(CONTRACT_PATH, 'utf8'));

/** The shipped scenario behind an id, if the contract has one. */
export function contractScenario(id: string): EmergencyScenario | null {
  return emergencyHelp.scenarios.find((s) => s.id === id) ?? null;
}
