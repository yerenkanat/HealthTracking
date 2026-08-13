/**
 * WHY an emergency fired — recovered from the reading that fired it.
 *
 * Both repositories returned `code: 'EMERGENCY'`, a literal, for every row in
 * the live feed. The panel prints `detail || code`, so frame 19 read
 *
 *     Aigerim S. · EMERGENCY · 02:14
 *     Madina K.  · EMERGENCY · 02:31
 *
 * on the one screen whose whole job is telling a duty operator which of the two
 * to ring first. A severe-range blood pressure and a sleeping SpO2 of 89 are
 * different phone calls.
 *
 * The reason is NOT stored — `pregnancy_health_metrics` keeps the vitals and the
 * winning severity, not the finding — so it is recomputed here from the columns
 * that are stored, with `assessTelemetry`: the SAME function that classified the
 * row at ingest. That is a re-derivation, not a guess. A row whose stored vitals
 * no longer explain its severity (nulls, or a severity written by a path that
 * predates a threshold change) returns `code: ''`, and the panel says the reason
 * was not kept rather than inventing one.
 *
 * Shared by pgRepository and memoryRepository on purpose. Two implementations of
 * "what does this emergency mean" would drift, and the fake would then agree
 * with tests instead of with production.
 */
import { assessTelemetry } from '@fcs/shared';
import type { TriageFinding } from '@fcs/shared';

/** The stored columns this derivation is allowed to look at. */
export interface StoredReading {
  heartRateBpm?: number | null;
  spo2Pct?: number | null;
  systolicMmHg?: number | null;
  diastolicMmHg?: number | null;
  coreTempC?: number | null;
  duringSleep?: boolean | null;
}

export interface EmergencyReason {
  /**
   * The triage finding code — `PREECLAMPSIA_BP_SEVERE`, `HYPOXIA_SEVERE`, … —
   * or '' when the stored reading explains nothing. Never a placeholder.
   */
  code: string;
  /** Which stored metric crossed: `systolicMmHg` | `coreTempC` | … or null. */
  metric: string | null;
  /** The value that crossed, in the metric's own unit. */
  value: number | null;
  /** The threshold it crossed, from TRIAGE_THRESHOLDS. */
  threshold: number | null;
  /** Both halves of the pair, because a blood pressure is read as 162/108. */
  systolic: number | null;
  diastolic: number | null;
  /** SpO2 below 95 means one thing asleep and another awake; triage uses it. */
  duringSleep: boolean;
}

const n = (v: number | null | undefined): number | null =>
  typeof v === 'number' && Number.isFinite(v) ? v : null;

/**
 * The finding to show. Highest severity wins; among equals, the first one
 * `assessTelemetry` produced — which is its own clinical ordering (blood
 * pressure, fever, oxygen, heart rate), not an arbitrary one.
 */
function pick(findings: TriageFinding[]): TriageFinding | null {
  const rank: Record<string, number> = { emergency: 3, warning: 2, info: 1, ok: 0 };
  let best: TriageFinding | null = null;
  for (const f of findings) {
    if (!best || rank[f.severity] > rank[best.severity]) best = f;
  }
  return best;
}

export function emergencyReason(r: StoredReading): EmergencyReason {
  const systolic = n(r.systolicMmHg);
  const diastolic = n(r.diastolicMmHg);
  const duringSleep = r.duringSleep === true;
  const empty: EmergencyReason = {
    code: '', metric: null, value: null, threshold: null, systolic, diastolic, duringSleep,
  };

  const t: Parameters<typeof assessTelemetry>[0] = { deviceId: '', recordedAt: '' };
  const hr = n(r.heartRateBpm); if (hr !== null) t.heartRateBpm = hr;
  const spo2 = n(r.spo2Pct); if (spo2 !== null) t.spo2Pct = spo2;
  if (systolic !== null) t.systolicMmHg = systolic;
  if (diastolic !== null) t.diastolicMmHg = diastolic;
  const temp = n(r.coreTempC); if (temp !== null) t.coreTempC = temp;
  t.duringSleep = duringSleep;

  // `source` is deliberately NOT set, and must stay unset.
  //
  // assessTelemetry branches on it for temperature — a manual thermometer
  // reading may escalate, a device estimate may not — and provenance is not a
  // stored column: `pregnancy_health_metrics` keeps core_temp_c and nothing
  // about how it was taken. device_id IS NULL does not stand in for it either;
  // an unrecognised band writes NULL there too. Passing a guess would make
  // Postgres and the in-memory repository disagree about what an old row means,
  // and the panel names the temperature finding in wording that claims neither.
  const finding = pick(assessTelemetry(t).findings);
  if (!finding) return empty;
  return {
    code: finding.code,
    metric: finding.metric ?? null,
    value: n(finding.value),
    threshold: n(finding.threshold),
    systolic,
    diastolic,
    duringSleep,
  };
}
