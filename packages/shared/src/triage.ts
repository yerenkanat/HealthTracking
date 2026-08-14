/**
 * CANONICAL MEDICAL TRIAGE RULES  —  owned by the OB-GYN specialist.
 *
 * This module is the single source of truth for what counts as a red flag during
 * pregnancy. It is imported BOTH by the mobile app (for instant on-device
 * escalation, even offline) AND by the backend AIGuardrailProcessor (so the LLM
 * can never "talk a user out of" an emergency). The rules here OVERRIDE the AI.
 *
 * Thresholds follow widely published obstetric guidance (ACOG / NICE / WHO). They
 * are intentionally conservative. THIS IS DECISION SUPPORT, NOT A DIAGNOSIS — the
 * emergency path always routes the user to a human clinician / ambulance.
 *
 * Pregnancy note: resting HR normally rises ~10–20 bpm in pregnancy, so tachycardia
 * thresholds are set higher than for the general adult population to avoid alarm
 * fatigue, while genuine danger signs (preeclampsia BP, hypoxia, high fever) stay strict.
 */

import type {
  BandTelemetry,
  TriageFinding,
  TriageResult,
  TriageSeverity,
} from './types';

export const TRIAGE_THRESHOLDS = {
  // Preeclampsia / hypertensive crisis
  BP_SYSTOLIC_EMERGENCY: 140, // mmHg — ACOG gestational hypertension cutoff
  BP_DIASTOLIC_EMERGENCY: 90,
  BP_SYSTOLIC_SEVERE: 160, // severe range → same emergency screen, stronger copy
  BP_DIASTOLIC_SEVERE: 110,

  // Fever
  FEVER_EMERGENCY_C: 38.5, // sudden high fever in pregnancy → urgent review
  FEVER_WARNING_C: 37.8,

  // Hypoxia (sleep SpO2)
  SPO2_EMERGENCY: 90,
  SPO2_WARNING: 95, // spec: warn below 95% during sleep

  // Heart rate (pregnancy-adjusted)
  HR_TACHY_WARNING: 120,
  HR_TACHY_EMERGENCY: 140,
  HR_BRADY_WARNING: 50,
  HR_BRADY_EMERGENCY: 40,
} as const;

/**
 * The widest cuff-vs-PPG disagreement still treated as sensor bias rather than
 * a bad measurement. Beyond this a calibration is REFUSED.
 *
 * Here rather than in the backend because the app enforces the same bounds, and
 * the two must agree: if they drift, the phone and the server disagree about
 * which calibrations are storable, silently. Pinned to
 * packages/contract/triage_thresholds.json by the contract tests on both sides.
 *
 * Why it matters clinically: the offset shifts every later reading, and a large
 * negative one can make genuine hypertension read as normal.
 */
export const MAX_SYSTOLIC_OFFSET = 30;
export const MAX_DIASTOLIC_OFFSET = 20;

const SEVERITY_RANK: Record<TriageSeverity, number> = {
  ok: 0,
  info: 1,
  warning: 2,
  emergency: 3,
};

function maxSeverity(a: TriageSeverity, b: TriageSeverity): TriageSeverity {
  return SEVERITY_RANK[a] >= SEVERITY_RANK[b] ? a : b;
}

/**
 * Pure, synchronous, dependency-free. Safe to run on-device on every telemetry
 * frame. Returns the highest severity found plus the itemized findings.
 */
export function assessTelemetry(t: BandTelemetry): TriageResult {
  const findings: TriageFinding[] = [];
  const T = TRIAGE_THRESHOLDS;

  // --- Blood pressure (preeclampsia) -------------------------------------
  if (typeof t.systolicMmHg === 'number' || typeof t.diastolicMmHg === 'number') {
    const sys = t.systolicMmHg ?? 0;
    const dia = t.diastolicMmHg ?? 0;

    if (sys >= T.BP_SYSTOLIC_SEVERE || dia >= T.BP_DIASTOLIC_SEVERE) {
      findings.push({
        code: 'PREECLAMPSIA_BP_SEVERE',
        severity: 'emergency',
        metric: sys >= T.BP_SYSTOLIC_SEVERE ? 'systolicMmHg' : 'diastolicMmHg',
        value: sys >= T.BP_SYSTOLIC_SEVERE ? sys : dia,
        threshold: sys >= T.BP_SYSTOLIC_SEVERE ? T.BP_SYSTOLIC_SEVERE : T.BP_DIASTOLIC_SEVERE,
        message:
          'Severe-range blood pressure detected. This can signal severe preeclampsia. Seek emergency care now.',
      });
    } else if (sys >= T.BP_SYSTOLIC_EMERGENCY || dia >= T.BP_DIASTOLIC_EMERGENCY) {
      findings.push({
        code: 'PREECLAMPSIA_BP',
        severity: 'emergency',
        metric: sys >= T.BP_SYSTOLIC_EMERGENCY ? 'systolicMmHg' : 'diastolicMmHg',
        value: sys >= T.BP_SYSTOLIC_EMERGENCY ? sys : dia,
        threshold: sys >= T.BP_SYSTOLIC_EMERGENCY ? T.BP_SYSTOLIC_EMERGENCY : T.BP_DIASTOLIC_EMERGENCY,
        message:
          'High blood pressure detected — a warning sign of preeclampsia. Contact your doctor immediately.',
      });
    }
  }

  // --- Fever -------------------------------------------------------------
  //
  // BRANCHES ON PROVENANCE, and the twin in app/lib/core/triage.dart does the
  // same. See docs/CLINICAL-REVIEW-WATCH.md, "Device temperature — closed
  // 2026-08-13": no device path may raise `emergency`, not because a wrist
  // sensor is imprecise but because the error source the conversion would have
  // to correct for — the room, the bedding, the strap — is not one of its
  // inputs. That error is systematic, not transient, so a repeat reading
  // confirms it rather than filtering it out.
  //
  // `source` absent means a device: the historical case, and the one that must
  // not escalate. A thermometer reading typed in ('manual') is UNCHANGED, at
  // full emergency weight — it is the one temperature this product is entitled
  // to escalate on, and the device branch's job is to route her to it.
  if (typeof t.coreTempC === 'number') {
    if (t.source !== 'manual') {
      if (t.coreTempC >= T.FEVER_WARNING_C) {
        findings.push({
          // MUST NOT end in 'FEVER': the app's emergencyFamily() sweeps
          // anything matching endsWith('FEVER') into the escalation gate, so
          // the name is load-bearing rather than cosmetic.
          code: 'DEVICE_TEMP_HIGH',
          severity: 'warning',
          metric: 'coreTempC',
          value: t.coreTempC,
          threshold: T.FEVER_WARNING_C,
          message:
            'The device estimated a raised temperature. A wrist sensor cannot tell a fever from a warm room. Take your temperature with a thermometer and enter it here; call your doctor today if it is raised or you feel unwell.',
        });
      }
    } else if (t.coreTempC >= T.FEVER_EMERGENCY_C) {
      findings.push({
        code: 'HIGH_FEVER',
        severity: 'emergency',
        metric: 'coreTempC',
        value: t.coreTempC,
        threshold: T.FEVER_EMERGENCY_C,
        message: 'High fever detected during pregnancy. Urgent medical review is needed.',
      });
    } else if (t.coreTempC >= T.FEVER_WARNING_C) {
      findings.push({
        code: 'LOW_FEVER',
        severity: 'warning',
        metric: 'coreTempC',
        value: t.coreTempC,
        threshold: T.FEVER_WARNING_C,
        message: 'Raised temperature. Rest, hydrate, and monitor. Call your clinic if it climbs.',
      });
    }
  }

  // --- SpO2 (sleep hypoxia) ---------------------------------------------
  if (typeof t.spo2Pct === 'number') {
    if (t.spo2Pct < T.SPO2_EMERGENCY) {
      findings.push({
        code: 'HYPOXIA_SEVERE',
        severity: 'emergency',
        metric: 'spo2Pct',
        value: t.spo2Pct,
        threshold: T.SPO2_EMERGENCY,
        message: 'Very low blood oxygen detected. Seek emergency care now.',
      });
    } else if (t.spo2Pct < T.SPO2_WARNING) {
      findings.push({
        code: 'HYPOXIA_SLEEP',
        severity: t.duringSleep ? 'warning' : 'info',
        metric: 'spo2Pct',
        value: t.spo2Pct,
        threshold: T.SPO2_WARNING,
        message:
          'Blood oxygen dipped below 95% during sleep. If this repeats, discuss sleep-disordered breathing with your doctor.',
      });
    }
  }

  // --- Heart rate (pregnancy-adjusted) ----------------------------------
  if (typeof t.heartRateBpm === 'number') {
    const hr = t.heartRateBpm;
    if (hr >= T.HR_TACHY_EMERGENCY || hr <= T.HR_BRADY_EMERGENCY) {
      findings.push({
        code: hr >= T.HR_TACHY_EMERGENCY ? 'TACHYCARDIA_SEVERE' : 'BRADYCARDIA_SEVERE',
        severity: 'emergency',
        metric: 'heartRateBpm',
        value: hr,
        threshold: hr >= T.HR_TACHY_EMERGENCY ? T.HR_TACHY_EMERGENCY : T.HR_BRADY_EMERGENCY,
        message: 'Dangerous heart rate detected. Seek urgent medical help.',
      });
    } else if (hr >= T.HR_TACHY_WARNING || hr <= T.HR_BRADY_WARNING) {
      findings.push({
        code: hr >= T.HR_TACHY_WARNING ? 'TACHYCARDIA' : 'BRADYCARDIA',
        severity: 'warning',
        metric: 'heartRateBpm',
        value: hr,
        threshold: hr >= T.HR_TACHY_WARNING ? T.HR_TACHY_WARNING : T.HR_BRADY_WARNING,
        message: 'Your heart rate is outside the expected range while resting. Sit down and re-measure.',
      });
    }
  }

  const severity = findings.reduce<TriageSeverity>(
    (acc, f) => maxSeverity(acc, f.severity),
    'ok',
  );

  // findings[0] must be the WORST finding, not the earliest branch.
  //
  // The Dart twin's docstring has always described `findings[0]` as "the top
  // finding surfaced in UI/push", and until this sort it was simply the first
  // branch that matched. That turned dangerous once DEVICE_TEMP_HIGH — a
  // WARNING — joined the fever block, which runs before oxygen: a sample with a
  // band temperature of 37.9 and an SpO2 of 82 came out `severity: 'emergency'`
  // with `findings[0]` a warning about the temperature. The app hands
  // `findings[0]` to its confirmation gate, which then asked about the wrong
  // reading and suppressed the hypoxia emergency screen.
  //
  // `.sort()` IS specified as stable in ES2019+, so equal severities keep the
  // clinical branch order (blood pressure, fever, oxygen, heart rate) — which
  // is what keeps `findings[0]` identical to the Dart twin, whose own sort has
  // to carry the index explicitly because Dart's `List.sort` is not stable.
  const ranked = [...findings].sort(
    (a, b) => SEVERITY_RANK[b.severity] - SEVERITY_RANK[a.severity],
  );

  return {
    severity,
    findings: ranked,
    forceEmergencyScreen: severity === 'emergency',
  };
}
