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
import { assessTelemetry, TRIAGE_THRESHOLDS } from '../triage';
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
    expect(TRIAGE_THRESHOLDS.SPO2_WARNING).toBe(thresholds.spo2Pct.warning);
    expect(TRIAGE_THRESHOLDS.HR_TACHY_EMERGENCY).toBe(thresholds.heartRateBpm.tachyEmergency);
    expect(TRIAGE_THRESHOLDS.HR_BRADY_EMERGENCY).toBe(thresholds.heartRateBpm.bradyEmergency);
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
