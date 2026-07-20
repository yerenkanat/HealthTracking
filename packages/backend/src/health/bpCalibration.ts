/**
 * Server-side BP calibration helper. Derives the offsets to persist when the user
 * enters a fresh weekly cuff reading (offset = cuff - ppg). Mirrors the Dart
 * app/lib/ble/calibration.dart so app and server agree on the correction.
 */

/**
 * The widest cuff-vs-PPG disagreement that is still plausibly sensor bias.
 * Beyond this the two are not measuring the same thing, and storing the gap as
 * an offset would distort every later reading — including the ones preeclampsia
 * triage depends on. Mirrors maxSystolicOffset/maxDiastolicOffset in Dart.
 */
export const MAX_SYSTOLIC_OFFSET = 30;
export const MAX_DIASTOLIC_OFFSET = 20;

export interface BpOffsets {
  systolicOffset: number;
  diastolicOffset: number;
  /** Null when accepted; otherwise why the calibration was refused. */
  rejectedBecause: string | null;
}

export function computeBpOffsets(
  cuffSystolic: number,
  cuffDiastolic: number,
  ppgSystolic: number,
  ppgDiastolic: number,
): BpOffsets {
  const systolicOffset = cuffSystolic - ppgSystolic;
  const diastolicOffset = cuffDiastolic - ppgDiastolic;
  // Refusing beats storing: an offset of -60 would make a genuine 165/105 read
  // as 105/85 and raise nothing at all.
  if (
    Math.abs(systolicOffset) > MAX_SYSTOLIC_OFFSET ||
    Math.abs(diastolicOffset) > MAX_DIASTOLIC_OFFSET
  ) {
    return {
      systolicOffset: 0,
      diastolicOffset: 0,
      rejectedBecause:
        `cuff and sensor disagree by ${Math.abs(systolicOffset)}/${Math.abs(diastolicOffset)} mmHg, ` +
        'too far apart to be calibration',
    };
  }
  return { systolicOffset, diastolicOffset, rejectedBecause: null };
}
