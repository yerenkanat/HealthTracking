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
