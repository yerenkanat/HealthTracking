/**
 * The emergency-help list as it is actually served: the shipped contract with
 * the back office's edits on top.
 *
 * One function, used by `GET /emergency-help` and by the admin editor, so the
 * two cannot answer differently about what «сильное кровотечение» tells
 * somebody to do. The merge itself is pure and lives in overrides.ts; this file
 * only adds the repository call and the failure policy.
 *
 * The failure policy is the point. If the database is unreachable, this returns
 * the CONTRACT — not an error, not an empty list. Losing the edits costs a
 * reader the newest wording of one scenario; losing the list costs her the
 * screen, at the moment she opened it because a child cannot breathe. The same
 * reasoning as the app bundling the asset, applied one layer up.
 */

import { emergencyHelp, type EmergencyHelp } from './help.js';
import { mergeEmergencyHelp, type EmergencyHelpOverride } from './overrides.js';

/** Only the piece of the repository this needs, so tests can pass a stub. */
export interface EmergencyOverrideSource {
  emergencyHelpOverrides(): Promise<EmergencyHelpOverride[]>;
}

export async function servedEmergencyHelp(
  repo: EmergencyOverrideSource | undefined,
): Promise<EmergencyHelp> {
  let overrides: EmergencyHelpOverride[] = [];
  try {
    // Optional-called rather than assumed: several route tests build the server
    // with a bare `{} as Repository`, and a first-aid screen that 500s because
    // nobody stubbed an override table would be a worse answer than the
    // contract.
    overrides = (await repo?.emergencyHelpOverrides?.()) ?? [];
  } catch {
    overrides = [];
  }
  return mergeEmergencyHelp(emergencyHelp, overrides);
}
