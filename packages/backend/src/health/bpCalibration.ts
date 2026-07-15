/**
 * Server-side BP calibration helper. Derives the offsets to persist when the user
 * enters a fresh weekly cuff reading (offset = cuff - ppg). Mirrors the Dart
 * app/lib/ble/calibration.dart so app and server agree on the correction.
 */

export function computeBpOffsets(
  cuffSystolic: number,
  cuffDiastolic: number,
  ppgSystolic: number,
  ppgDiastolic: number,
): { systolicOffset: number; diastolicOffset: number } {
  return {
    systolicOffset: cuffSystolic - ppgSystolic,
    diastolicOffset: cuffDiastolic - ppgDiastolic,
  };
}
