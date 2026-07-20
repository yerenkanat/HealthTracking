/**
 * CROSS-LANGUAGE CONTRACT (TypeScript side).
 * Asserts the Node implementation (1) uses the canonical thresholds from the
 * shared JSON, and (2) produces the exact verdicts in the golden vector file.
 * The Dart app runs the SAME vectors (app/test/triage_contract_test.dart).
 * If TS and Dart ever diverge, one of the two suites goes red.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  assessTelemetry,
  TRIAGE_THRESHOLDS,
  MAX_SYSTOLIC_OFFSET,
  MAX_DIASTOLIC_OFFSET,
} from '../triage';
import type { BandTelemetry } from '../types';

const contractDir = fileURLToPath(new URL('../../../contract/', import.meta.url));
const thresholds = JSON.parse(readFileSync(`${contractDir}triage_thresholds.json`, 'utf8'));
const vectors = JSON.parse(readFileSync(`${contractDir}triage_vectors.json`, 'utf8'));

describe('thresholds match the shared JSON contract', () => {
  it('BP', () => {
    expect(TRIAGE_THRESHOLDS.BP_SYSTOLIC_EMERGENCY).toBe(thresholds.bloodPressure.systolicEmergency);
    expect(TRIAGE_THRESHOLDS.BP_DIASTOLIC_EMERGENCY).toBe(thresholds.bloodPressure.diastolicEmergency);
    expect(TRIAGE_THRESHOLDS.BP_SYSTOLIC_SEVERE).toBe(thresholds.bloodPressure.systolicSevere);
    expect(TRIAGE_THRESHOLDS.BP_DIASTOLIC_SEVERE).toBe(thresholds.bloodPressure.diastolicSevere);
  });
  it('temp / spo2 / hr', () => {
    expect(TRIAGE_THRESHOLDS.FEVER_EMERGENCY_C).toBe(thresholds.temperatureC.feverEmergency);
    expect(TRIAGE_THRESHOLDS.FEVER_WARNING_C).toBe(thresholds.temperatureC.feverWarning);
    expect(TRIAGE_THRESHOLDS.SPO2_EMERGENCY).toBe(thresholds.spo2Pct.emergency);
    expect(TRIAGE_THRESHOLDS.SPO2_WARNING).toBe(thresholds.spo2Pct.warning);
    expect(TRIAGE_THRESHOLDS.HR_TACHY_WARNING).toBe(thresholds.heartRateBpm.tachyWarning);
    expect(TRIAGE_THRESHOLDS.HR_TACHY_EMERGENCY).toBe(thresholds.heartRateBpm.tachyEmergency);
    expect(TRIAGE_THRESHOLDS.HR_BRADY_WARNING).toBe(thresholds.heartRateBpm.bradyWarning);
    expect(TRIAGE_THRESHOLDS.HR_BRADY_EMERGENCY).toBe(thresholds.heartRateBpm.bradyEmergency);
  });

  it('blood-pressure calibration bounds', () => {
    // These live in two languages, and the server enforces them with no UI in
    // front of it. If one side drifts, the app and the backend disagree about
    // which calibrations are storable — silently.
    expect(MAX_SYSTOLIC_OFFSET).toBe(thresholds.bpCalibration.maxSystolicOffset);
    expect(MAX_DIASTOLIC_OFFSET).toBe(thresholds.bpCalibration.maxDiastolicOffset);
  });

  it('every value in the contract is pinned by an assertion', () => {
    // Adding a value to the JSON and forgetting to check it here would pass
    // silently, which is exactly how drift starts. Mirrors the same guard in
    // app/test/triage_contract_test.dart.
    const pinned = new Set([
      'bloodPressure.systolicEmergency', 'bloodPressure.diastolicEmergency',
      'bloodPressure.systolicSevere', 'bloodPressure.diastolicSevere',
      'temperatureC.feverEmergency', 'temperatureC.feverWarning',
      'spo2Pct.emergency', 'spo2Pct.warning',
      'heartRateBpm.tachyWarning', 'heartRateBpm.tachyEmergency',
      'heartRateBpm.bradyWarning', 'heartRateBpm.bradyEmergency',
      'bpCalibration.maxSystolicOffset', 'bpCalibration.maxDiastolicOffset',
    ]);
    const inContract: string[] = [];
    for (const [section, body] of Object.entries(thresholds)) {
      if (section.startsWith('_') || typeof body !== 'object' || body === null) continue;
      for (const key of Object.keys(body)) {
        if (key.startsWith('_')) continue;
        inContract.push(`${section}.${key}`);
      }
    }
    expect(inContract.filter((k) => !pinned.has(k))).toEqual([]);
  });
});

describe('golden vectors produce identical verdicts', () => {
  for (const c of vectors.cases as Array<any>) {
    it(c.name, () => {
      const t: BandTelemetry = { deviceId: 'x', recordedAt: '2026-07-15T00:00:00.000Z', ...c.input };
      const r = assessTelemetry(t);
      expect(r.severity).toBe(c.severity);
      expect(r.forceEmergencyScreen).toBe(c.forceEmergencyScreen);
      if (c.topCode) expect(r.findings[0]?.code).toBe(c.topCode);
    });
  }
});
