/**
 * QA Automation Engineer: the triage rules are safety-critical, so they get the
 * strictest tests. These lock the OB-GYN's thresholds against regression.
 */

import { describe, it, expect } from 'vitest';
import { assessTelemetry } from '../triage';
import type { BandTelemetry } from '../types';

const base: BandTelemetry = { deviceId: 'd1', recordedAt: '2026-07-15T00:00:00.000Z' };

describe('assessTelemetry — preeclampsia BP', () => {
  it('forces emergency at systolic 140', () => {
    const r = assessTelemetry({ ...base, systolicMmHg: 140, diastolicMmHg: 85 });
    expect(r.forceEmergencyScreen).toBe(true);
    expect(r.findings[0].code).toBe('PREECLAMPSIA_BP');
  });
  it('forces emergency at diastolic 90 even with normal systolic', () => {
    const r = assessTelemetry({ ...base, systolicMmHg: 118, diastolicMmHg: 90 });
    expect(r.severity).toBe('emergency');
  });
  it('escalates severe range 160/110', () => {
    const r = assessTelemetry({ ...base, systolicMmHg: 165, diastolicMmHg: 112 });
    expect(r.findings[0].code).toBe('PREECLAMPSIA_BP_SEVERE');
  });
  it('stays ok at 118/76', () => {
    const r = assessTelemetry({ ...base, systolicMmHg: 118, diastolicMmHg: 76 });
    expect(r.forceEmergencyScreen).toBe(false);
    expect(r.severity).toBe('ok');
  });
});

describe('assessTelemetry — fever / hypoxia / HR', () => {
  it('emergency on a THERMOMETER reading >= 38.5', () => {
    // The one temperature path this product may escalate on, and it is
    // unchanged. See docs/CLINICAL-REVIEW-WATCH.md ruling 4: a patch that
    // lowers manual entry to `warning` is a rejection of that review.
    const r = assessTelemetry({ ...base, coreTempC: 38.6, source: 'manual' });
    expect(r.severity).toBe('emergency');
    expect(r.findings[0].code).toBe('HIGH_FEVER');
  });
  it('warning on a thermometer reading >= 37.8', () => {
    const r = assessTelemetry({ ...base, coreTempC: 37.9, source: 'manual' });
    expect(r.severity).toBe('warning');
    expect(r.findings[0].code).toBe('LOW_FEVER');
  });
  it('warning on low SpO2 during sleep, info while awake', () => {
    expect(assessTelemetry({ ...base, spo2Pct: 93, duringSleep: true }).severity).toBe('warning');
    expect(assessTelemetry({ ...base, spo2Pct: 93, duringSleep: false }).severity).toBe('info');
  });
  it('emergency on severe hypoxia < 90', () => {
    expect(assessTelemetry({ ...base, spo2Pct: 88 }).severity).toBe('emergency');
  });
  it('pregnancy-adjusted HR: 118 resting is not yet a warning', () => {
    expect(assessTelemetry({ ...base, heartRateBpm: 118 }).severity).toBe('ok');
  });
  it('HR >= 140 is an emergency', () => {
    expect(assessTelemetry({ ...base, heartRateBpm: 145 }).severity).toBe('emergency');
  });
});

describe('assessTelemetry — a temperature a device estimated', () => {
  // The server re-runs these rules and pushes on the first crossing, with no
  // equivalent of the app's confirmation gate. If this branch is wrong here, a
  // warm duvet sends a pregnant woman a "seek care now" push at 3 a.m.
  it('warns and never escalates, whatever the number', () => {
    const r = assessTelemetry({ ...base, coreTempC: 38.6, source: 'band' });
    expect(r.severity).toBe('warning');
    expect(r.forceEmergencyScreen).toBe(false);
    expect(r.findings[0].code).toBe('DEVICE_TEMP_HIGH');
    expect(assessTelemetry({ ...base, coreTempC: 41, source: 'band' }).severity).toBe('warning');
  });

  it('treats an ABSENT source as a device — the historical case', () => {
    const r = assessTelemetry({ ...base, coreTempC: 38.6 });
    expect(r.forceEmergencyScreen).toBe(false);
    expect(r.findings[0].code).toBe('DEVICE_TEMP_HIGH');
  });

  it('says nothing at all below the threshold', () => {
    const r = assessTelemetry({ ...base, coreTempC: 36.9, source: 'band' });
    expect(r.severity).toBe('ok');
    expect(r.findings).toHaveLength(0);
  });

  it('uses a code that does not end in FEVER', () => {
    // The app's emergencyFamily() groups by endsWith('FEVER') and feeds that
    // family to the escalation gate. The name is load-bearing.
    const code = assessTelemetry({ ...base, coreTempC: 39, source: 'band' }).findings[0].code;
    expect(code.endsWith('FEVER')).toBe(false);
  });

  it('changed nothing else: a device 165/112 still escalates', () => {
    expect(
      assessTelemetry({ ...base, systolicMmHg: 165, diastolicMmHg: 112, source: 'band' })
        .forceEmergencyScreen,
    ).toBe(true);
  });
});

describe('assessTelemetry — worst-of severity', () => {
  it('reports emergency when any single finding is emergency', () => {
    const r = assessTelemetry({ ...base, spo2Pct: 96, heartRateBpm: 122, systolicMmHg: 142 });
    expect(r.severity).toBe('emergency');
    expect(r.findings.length).toBeGreaterThanOrEqual(2);
  });
});

/**
 * `findings[0]` is the WORST finding, not the earliest branch.
 *
 * The Dart twin's docstring has always called `findings[0]` "the top finding
 * surfaced in UI/push", and it was branch order. That became dangerous when
 * DEVICE_TEMP_HIGH — a WARNING — joined the fever block, which runs before
 * oxygen: the app hands `findings[0]` to its confirmation gate, so a warning
 * about a wrist temperature was asked about instead of a severe hypoxia, and
 * the emergency screen did not open.
 *
 * Pinned on BOTH sides because these are behavioural twins: a rule that holds
 * in Dart and not in TypeScript means the handset and the server disagree about
 * what the top finding is, which is the same defect wearing a server hat.
 */
describe('assessTelemetry — the top finding', () => {
  it('ranks an emergency above a warning that fired in an earlier branch', () => {
    const r = assessTelemetry({
      ...base,
      coreTempC: 37.9, // warning tier, fever block runs first
      spo2Pct: 82, // severe hypoxia, checked later
      source: 'band',
    } as BandTelemetry);

    expect(r.severity).toBe('emergency');
    expect(r.forceEmergencyScreen).toBe(true);
    expect(r.findings[0].severity).toBe('emergency');
    // The warning is demoted, never dropped — it is still a true finding.
    expect(r.findings.map((f) => f.code)).toContain('DEVICE_TEMP_HIGH');
  });

  it('leaves the clinical branch order intact among equal severities', () => {
    // Blood pressure is checked before heart rate and both are emergencies.
    // `Array.prototype.sort` is stable in ES2019+, which is what preserves
    // this; the Dart twin has to carry the index explicitly because its
    // `List.sort` is not stable. If these two ever disagree, the twins have
    // silently diverged on which finding is "the" one.
    const r = assessTelemetry({
      ...base,
      systolicMmHg: 170,
      diastolicMmHg: 115,
      heartRateBpm: 145,
    } as BandTelemetry);

    const codes = r.findings.map((f) => f.code);
    const bp = codes.findIndex((c) => c.startsWith('PREECLAMPSIA'));
    const hr = codes.findIndex((c) => c.includes('TACHY'));
    expect(bp).toBeGreaterThanOrEqual(0);
    expect(hr).toBeGreaterThanOrEqual(0);
    expect(bp).toBeLessThan(hr);
  });
});
