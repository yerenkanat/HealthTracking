/**
 * The emergency-help list, as edited.
 *
 * Frame 16b «Экстренная помощь» → app screen 37. Nine scenarios that tell a
 * frightened person whether to dial 103 now or call the clinic in the morning,
 * and they shipped as a compiled-in JSON file: fixing «держите ожог под водой
 * 20 минут» meant a backend release and a store rollout.
 *
 * The rule, in one line: **the contract is the baseline, the database is a
 * patch.** Nothing here ever removes a scenario. An override replaces one
 * scenario's fields; drop every row and the served list is byte-for-byte the
 * shipped one again.
 *
 * PURE: contract in, rows in, list out. No repository, no clock, no Fastify —
 * so the merge is exercised by unit tests and by the route tests without a
 * database between them.
 */

import type { EmergencyHelp, EmergencyScenario, EmergencySeverity, EmergencyText } from './help.js';
import type { ReviewableItem } from '../content/medicalReview.js';

/** One edited scenario, as the repository stores it. */
export interface EmergencyHelpOverride {
  id: string;
  severity: EmergencySeverity;
  sort: number;
  ru: EmergencyText;
  kk: EmergencyText;
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
 * rather than a wall: half-written first aid has somewhere to live that is not
 * a private document, and the reader keeps seeing the last text a clinician
 * signed.
 *
 * An override for an id the contract does not have is IGNORED rather than
 * appended. Everything downstream — the app's bundled asset, the panel's list,
 * app/tool/verify_emergency_help_contract.dart — is keyed on the shipped ids,
 * so an invented scenario would appear on a phone that has just fetched and
 * vanish on one that has not. Adding a scenario is a contract change; this
 * table exists to fix wording and triage order without a release, which is a
 * smaller and much safer promise.
 *
 * Sorted by `sort` then `id`: `sort` is editable, so two scenarios can end up
 * sharing a number, and a list whose order depends on which row the database
 * happened to return first would reshuffle itself between reads.
 *
 * The version moves whenever the table moves: `contract.version + Σ rev` over
 * ALL rows, drafts included. Drafting a scenario changes what readers see (the
 * contract shows through again), so it has to count. `rev` only ever grows and
 * rows are never deleted, so the number is monotonic — a client caching by
 * version can trust it.
 */
export function mergeEmergencyHelp(
  base: EmergencyHelp,
  overrides: EmergencyHelpOverride[],
): EmergencyHelp {
  const byId = new Map(overrides.map((o) => [o.id, o]));
  const scenarios: EmergencyScenario[] = base.scenarios.map((s) => {
    const o = byId.get(s.id);
    if (!o || o.draft) return s;
    return {
      id: s.id,
      severity: o.severity,
      sort: o.sort,
      // From the BASELINE, never from the row. `audience` says who a scenario
      // is written for — the app hides «после 20 недель» from a reader who is
      // not expecting — and it is not one of the fields the panel edits. Built
      // from `o` alone this would be undefined, and a wording fix would quietly
      // put pregnancy triage back in front of everybody.
      audience: s.audience,
      ru: { ...o.ru },
      kk: { ...o.kk },
    };
  });
  scenarios.sort((a, b) => (a.sort - b.sort) || a.id.localeCompare(b.id));
  const bump = overrides.reduce((t, o) => t + (Number.isFinite(o.rev) ? o.rev : 0), 0);
  return { version: base.version + bump, tel: base.tel, scenarios };
}

/**
 * A scenario, as the medical-review machinery sees it.
 *
 * content/medicalReview.ts fingerprints `title`, `summary`, `url` and `video`
 * — the shape a timeline card has. A first-aid scenario is not a card, so
 * rather than a second fingerprint function that could drift from the first,
 * the scenario is projected onto that shape ONCE, here, and every rule
 * (`unreviewed`, `carryReview`, `textFingerprint`) then applies unchanged.
 *
 * What matters is that everything a clinician read is inside the projection.
 * The prose obviously is. So is the SEVERITY, carried in `url`: it is the field
 * that decides whether the reader dials an ambulance or waits until morning,
 * and a reviewed scenario quietly downgraded from red to amber afterwards is
 * unreviewed advice under a reviewed headline. `sort` is deliberately NOT in
 * there — reordering the list changes nothing about what any one scenario
 * says, and making a drag of a row revoke a clinician's sign-off is how a rule
 * becomes something everybody works around.
 *
 * `medical: true` unconditionally. Every scenario here is an instruction about
 * a bleeding, unbreathing or unconscious person; there is no non-medical half
 * of this list to exempt.
 */
export function scenarioAsReviewable(
  id: string,
  v: { severity: EmergencySeverity; ru: EmergencyText; kk: EmergencyText; draft: boolean },
): ReviewableItem {
  return {
    id: `emergency-${id}`,
    medical: true,
    draft: v.draft,
    title: { ru: v.ru.title, kk: v.kk.title },
    summary: {
      ru: `${v.ru.what}\n${v.ru.do}`,
      kk: `${v.kk.what}\n${v.kk.do}`,
    },
    url: `severity=${v.severity}`,
  };
}
