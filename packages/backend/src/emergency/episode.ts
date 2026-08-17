/**
 * ONE ALERT PER EPISODE — the server's half of the rule the phone already holds.
 *
 * WHAT WAS WRONG, measured rather than reasoned about
 * ---------------------------------------------------
 * `ingestTelemetry` re-runs `assessTelemetry` on every reading and calls
 * `sendEmergencyPush` whenever the verdict is `emergency`. There is no state
 * between readings, so five band frames one minute apart at 145/95 produced
 * FIVE emergency pushes — each one `critical: true`, on the `medical_critical`
 * channel, `bypassDnd`, with the APNs critical sound. Verified by driving five
 * items through `handleIngestBatch` before this module existed:
 * `{telemetryCount: 5, emergencies: 5}` and five calls to the push spy.
 *
 * The band samples continuously and the batcher drains an offline queue in one
 * flush (`maxBatch` 500), so a woman whose true pressure sits over the line for
 * an hour is alarmed once per frame, and a phone that reconnects after an
 * offline spell fires the whole backlog at her in one second. That is the
 * alarm fatigue `app/lib/domain/emergency_confirmation.dart` names in its own
 * header — «alarm fatigue is how the real emergency gets ignored» — arriving
 * through a channel the app's gate does not reach.
 *
 * WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT DO
 * ----------------------------------------------------
 * It suppresses REPEATS of an alert already raised. It never withholds a first
 * one. That distinction is the whole design, and it is what keeps this inside
 * the absorber corollary in docs/CLINICAL-REVIEW-WATCH.md — «gate the
 * positives, never the warnings». No crossing that would have produced the
 * first push of an episode produces less than it did before; the second through
 * Nth carry no information the first did not, since the copy, the category, the
 * destination screen and the triage code are identical by construction
 * (`emergencyCopy` in notifications/push.ts reads only `findings[0].code`).
 *
 * IT IS NOT A PORT OF `EmergencyConfirmation`, and must not become one.
 * The phone's gate answers a different question — may we act on ONE sensor
 * estimate — and its answer to "not yet" is not silence: it is an in-app
 * «take another reading» prompt (`app_controller.awaitingRepeat`). The server
 * has no such middle branch. Its only choices are the critical push or nothing,
 * so a server-side copy of that gate would substitute SILENCE where the
 * approved policy substitutes a prompt — a strictly stronger gate than the one
 * the clinical gate signed off, applied to a warning. Whether that trade is
 * acceptable is a clinical question, not an engineering one, and it is recorded
 * as an open question rather than answered here.
 *
 * PURE. No database, no clock, no Fastify — the caller supplies the stored rows
 * and the instant, exactly as `gate.ts` takes `minuteOfDay` rather than reading
 * a clock.
 */

import { assessTelemetry } from '@fcs/shared';
import type { BandTelemetry } from '@fcs/shared';

/**
 * The longest gap across which two crossings are still the SAME episode.
 *
 * NOT A NEW NUMBER. It is `EmergencyConfirmation.window` from
 * `app/lib/domain/emergency_confirmation.dart` — «How long a crossing stays
 * pending. Past this it is treated as a one-off.» — which is precisely this
 * quantity read from the other end: on the phone, two crossings more than this
 * far apart are not one persisting condition, because the first has expired.
 * Reusing it means the phone and the server agree about where one episode ends
 * and the next begins, and `episodeWindow.test.ts` parses the Dart source and
 * fails if either side moves.
 *
 * No threshold is invented here and none is needed: WHICH readings count as
 * emergencies is still decided entirely by `assessTelemetry`.
 */
export const EMERGENCY_EPISODE_WINDOW_MS = 30 * 60 * 1000;

/**
 * Which measurement a triage code is about — the twin of `emergencyFamily()` in
 * `app/lib/domain/emergency_confirmation.dart`, character for character in its
 * rules.
 *
 * Grouped rather than compared code-for-code so that a reading which crosses
 * the ordinary threshold and then the severe one counts as the same condition
 * persisting, rather than as a second episode: 145/95 followed by 165/115 is
 * one preeclampsia, and alerting twice for it is the storm this module exists
 * to stop.
 *
 * The `endsWith('FEVER')` rule is load-bearing on both sides and is why the
 * device-temperature code is named `DEVICE_TEMP_HIGH` — see the comment on it
 * in packages/shared/src/triage.ts. An unrecognised code stands alone, which is
 * the safe default: a new code nobody has classified gets its own episode and
 * is therefore never suppressed by an unrelated one.
 */
export function emergencyFamily(code: string | null | undefined): string | null {
  if (!code) return null;
  if (code.startsWith('PREECLAMPSIA_BP')) return 'bp';
  if (code.endsWith('FEVER')) return 'fever';
  if (code.startsWith('HYPOXIA')) return 'spo2';
  if (code.startsWith('TACHY') || code.startsWith('BRADY')) return 'hr';
  return code;
}

/**
 * A stored reading that triage already called an emergency, as the repository
 * returns it.
 *
 * `manual` is not a column. It is `device_id IS NULL` spoken out loud, the same
 * rule `listManualVitals` states — and it has to be carried, because
 * `assessTelemetry`'s fever branch reads `source` and a row replayed without it
 * would be judged as a device reading. See docs/CLINICAL-REVIEW-WATCH.md, "The
 * verdict has one regression path".
 */
export interface StoredEmergencyReading {
  recordedAt: string;
  manual: boolean;
  coreTempC: number | null;
  heartRateBpm: number | null;
  spo2Pct: number | null;
  systolicMmHg: number | null;
  diastolicMmHg: number | null;
  duringSleep: boolean;
}

/**
 * The family a stored row's emergency was about.
 *
 * Re-runs the SAME `assessTelemetry` over the SAME values rather than guessing
 * from which columns are populated. A row with a raised temperature and a
 * collapsed SpO2 has one top finding, and the shared module's `findings[0]`
 * sort is what decides which — the phone hands `findings[0]` to its gate and
 * the push carries `findings[0].code`, so anything else here would group by a
 * finding nobody was ever told about.
 *
 * Returns null when the replay finds no emergency at all: a row stored as
 * `emergency` under an older rule set (a device temperature, before the
 * 2026-08-13 ruling) must not go on suppressing today's alerts.
 */
export function familyOfStored(r: StoredEmergencyReading): string | null {
  const t: BandTelemetry = {
    deviceId: r.manual ? '' : 'stored',
    recordedAt: r.recordedAt,
    ...(r.manual ? { source: 'manual' as const } : {}),
    ...(r.coreTempC != null ? { coreTempC: r.coreTempC } : {}),
    ...(r.heartRateBpm != null ? { heartRateBpm: r.heartRateBpm } : {}),
    ...(r.spo2Pct != null ? { spo2Pct: r.spo2Pct } : {}),
    ...(r.systolicMmHg != null ? { systolicMmHg: r.systolicMmHg } : {}),
    ...(r.diastolicMmHg != null ? { diastolicMmHg: r.diastolicMmHg } : {}),
    duringSleep: r.duringSleep,
  };
  const verdict = assessTelemetry(t);
  if (!verdict.forceEmergencyScreen) return null;
  return emergencyFamily(verdict.findings[0]?.code);
}

/**
 * Has this family already been alerted, within the window around [atIso]?
 *
 * ORDER-INDEPENDENT ON PURPOSE. The comparison is on `|Δt|`, not "earlier
 * than", because readings do not always reach us in the order they were taken:
 * a batch requeued after a lost response, or two handsets on one account, can
 * present 09:05 before 09:00. Keyed on arrival order, that pair alerts twice —
 * each reading being the first one the server happens to see. Keyed on the
 * absolute gap, one of them raises the episode and the other joins it,
 * whichever lands first.
 *
 * A row whose timestamp will not parse is IGNORED rather than treated as
 * matching. The bias has to be toward sending: a corrupt stored timestamp must
 * never be able to silence a live emergency.
 */
export function episodeAlreadyAlerted(
  family: string | null,
  atIso: string,
  stored: readonly StoredEmergencyReading[],
): boolean {
  if (!family) return false;
  const at = Date.parse(atIso);
  if (!Number.isFinite(at)) return false;
  for (const row of stored) {
    // The reading being judged is in the table by now — it was inserted before
    // the push decision, so that a crash between the two loses the alert rather
    // than the reading. Skipping it by timestamp is exact: the table's
    // uniqueness constraint is (user_id, device_id, recorded_at).
    if (row.recordedAt === atIso) continue;
    const t = Date.parse(row.recordedAt);
    if (!Number.isFinite(t)) continue;
    if (Math.abs(t - at) > EMERGENCY_EPISODE_WINDOW_MS) continue;
    if (familyOfStored(row) === family) return true;
  }
  return false;
}
