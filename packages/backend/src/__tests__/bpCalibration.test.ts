/**
 * Blood-pressure calibration offsets.
 *
 * These offsets shift every later reading, and those readings feed preeclampsia
 * triage. The route sits behind no UI of its own, so the bounds enforced here
 * are the only thing standing between a typo and a distorted reading history.
 */

import { describe, it, expect } from 'vitest';
import {
  computeBpOffsets,
  MAX_SYSTOLIC_OFFSET,
  MAX_DIASTOLIC_OFFSET,
} from '../health/bpCalibration';

describe('computeBpOffsets', () => {
  it('derives offset = cuff - ppg for a plausible reading', () => {
    const o = computeBpOffsets(128, 82, 120, 78);
    expect(o).toMatchObject({ systolicOffset: 8, diastolicOffset: 4, rejectedBecause: null });
  });

  it('accepts a negative offset, which is an ordinary sensor bias', () => {
    const o = computeBpOffsets(115, 74, 120, 78);
    expect(o.rejectedBecause).toBeNull();
    expect(o.systolicOffset).toBe(-5);
  });

  it('refuses a cuff reading far below the sensor', () => {
    // The dangerous direction: a large negative offset subtracts from every
    // later reading and can hide genuine hypertension entirely.
    const o = computeBpOffsets(60, 40, 165, 105);
    expect(o.rejectedBecause).toBeTruthy();
  });

  it('refuses a cuff reading far above the sensor', () => {
    expect(computeBpOffsets(240, 140, 120, 78).rejectedBecause).toBeTruthy();
  });

  it('zeroes the offsets on a refusal so they cannot be applied by accident', () => {
    const o = computeBpOffsets(60, 40, 165, 105);
    expect(o.systolicOffset).toBe(0);
    expect(o.diastolicOffset).toBe(0);
  });

  it('accepts exactly the maximum gap and refuses one past it', () => {
    // The check is against nonsense, not against being unusual — a real but
    // large sensor bias must still be able to calibrate.
    expect(computeBpOffsets(120 + MAX_SYSTOLIC_OFFSET, 78, 120, 78).rejectedBecause).toBeNull();
    expect(computeBpOffsets(121 + MAX_SYSTOLIC_OFFSET, 78, 120, 78).rejectedBecause).toBeTruthy();
    expect(computeBpOffsets(120, 78 + MAX_DIASTOLIC_OFFSET, 120, 78).rejectedBecause).toBeNull();
    expect(computeBpOffsets(120, 79 + MAX_DIASTOLIC_OFFSET, 120, 78).rejectedBecause).toBeTruthy();
  });

  it('agrees with the Dart implementation on the bounds', () => {
    // app/lib/ble/calibration.dart carries the same two constants; if one side
    // moves, the app and the server would disagree about what is storable.
    expect(MAX_SYSTOLIC_OFFSET).toBe(30);
    expect(MAX_DIASTOLIC_OFFSET).toBe(20);
  });
});
