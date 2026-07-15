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
  it('emergency on fever >= 38.5', () => {
    expect(assessTelemetry({ ...base, coreTempC: 38.6 }).severity).toBe('emergency');
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

describe('assessTelemetry — worst-of severity', () => {
  it('reports emergency when any single finding is emergency', () => {
    const r = assessTelemetry({ ...base, spo2Pct: 96, heartRateBpm: 122, systolicMmHg: 142 });
    expect(r.severity).toBe('emergency');
    expect(r.findings.length).toBeGreaterThanOrEqual(2);
  });
});
