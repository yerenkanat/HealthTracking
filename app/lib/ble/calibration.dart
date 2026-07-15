/// Sensor calibration math — Dart twin of mobile/src/ble/calibration.ts.
/// Pure Dart → unit-testable. Owned by Hardware Integration + OB-GYN.
library;

import 'dart:math' as math;

/// Skin (wrist) temperature → estimated core temperature.
/// T_core = T_skin + Δt, Δt ≈ 3.0°C, tapered near/above core to avoid a fake fever.
double skinToCoreTempC(double skinTempC) {
  const baseOffset = 3.0;
  final taper = skinTempC > 34 ? math.max(0.0, (37 - skinTempC) * 0.15 + 1) : 1.0;
  final core = skinTempC + baseOffset * math.min(1.0, taper);
  final clamped = math.min(42.0, math.max(34.0, core));
  return double.parse(clamped.toStringAsFixed(2));
}

class BpCalibration {
  final double systolicOffset;
  final double diastolicOffset;
  final DateTime calibratedAt;
  const BpCalibration(this.systolicOffset, this.diastolicOffset, this.calibratedAt);
}

class CalibratedBp {
  final int systolic;
  final int diastolic;
  final bool calibrationStale;
  const CalibratedBp(this.systolic, this.diastolic, this.calibrationStale);
}

/// Apply the last weekly cuff calibration (offset = cuff - ppg) to a PPG estimate.
CalibratedBp applyBpCalibration(
  int rawSystolic,
  int rawDiastolic,
  BpCalibration? cal, {
  int maxAgeDays = 8,
  DateTime? now,
}) {
  if (cal == null) {
    return CalibratedBp(rawSystolic, rawDiastolic, true);
  }
  final ageDays =
      (now ?? DateTime.now()).difference(cal.calibratedAt).inHours / 24.0;
  final systolic = (rawSystolic + cal.systolicOffset).round();
  final diastolic = (rawDiastolic + cal.diastolicOffset).round();
  return CalibratedBp(
    _clamp(systolic, 70, 220),
    _clamp(diastolic, 40, 140),
    ageDays > maxAgeDays,
  );
}

({double systolicOffset, double diastolicOffset}) computeBpOffsets(
  int cuffSystolic,
  int cuffDiastolic,
  int ppgSystolic,
  int ppgDiastolic,
) =>
    (
      systolicOffset: (cuffSystolic - ppgSystolic).toDouble(),
      diastolicOffset: (cuffDiastolic - ppgDiastolic).toDouble(),
    );

int _clamp(int v, int lo, int hi) => math.min(hi, math.max(lo, v));

/// Log-distance path-loss model: RSSI → distance (m). txPower = RSSI @ 1m.
double rssiToDistanceM(int rssi, {int txPower = -59, double n = 2.5}) {
  if (rssi == 0) return -1;
  final ratio = (txPower - rssi) / (10 * n);
  return double.parse(math.pow(10, ratio).toStringAsFixed(2));
}
