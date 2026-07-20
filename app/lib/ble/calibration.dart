/// Sensor calibration math — Dart twin of mobile/src/ble/calibration.ts.
/// Pure Dart → unit-testable. Owned by Hardware Integration + OB-GYN.
library;

import 'dart:math' as math;

/// Skin (wrist) temperature → estimated core temperature.
///
/// The body holds core temperature nearly constant while letting skin swing
/// widely — a wrist sits several degrees below core in a cool room and climbs
/// close to it under a duvet, all at an unchanged core. So this maps a wide
/// skin range onto a narrow core range, anchored at a resting wrist of 33°C
/// reading as 36.8°C core.
///
/// The previous form added a flat +3.0°C with a taper that, on the numbers,
/// never engaged below a 37°C wrist: a 35.5°C wrist — ordinary under bedding —
/// came out as 38.5°C and tripped the pregnancy high-fever emergency. The
/// direction of the fix matters more than its exact slope: a warm wrist must
/// read as a warm wrist, not as a medical emergency.
///
/// This is an ESTIMATE from a consumer sensor, not a thermometer. It is fit to
/// spot a trend, and it should not be the sole basis for an urgent claim.
double skinToCoreTempC(double skinTempC) {
  // A resting wrist and the core it corresponds to.
  const skinRef = 33.0;
  const coreRef = 36.8;

  // How much of a skin swing carries through to core. Well below 1.0 because
  // most of a skin change is the body regulating, not core actually moving.
  // Chosen so an ordinary warm wrist — 35.5°C under bedding — stays under the
  // 37.8°C raised-temperature warning, while a genuinely hot wrist can still
  // reach the 38.5°C emergency. Both directions are pinned by assertions in
  // tool/verify_calibration.dart against the thresholds in shared/triage.ts.
  const sensitivity = 0.35;

  final core = coreRef + (skinTempC - skinRef) * sensitivity;
  final clamped = math.min(42.0, math.max(34.0, core));
  return double.parse(clamped.toStringAsFixed(2));
}

class BpCalibration {
  final double systolicOffset;
  final double diastolicOffset;
  final DateTime calibratedAt;
  const BpCalibration(this.systolicOffset, this.diastolicOffset, this.calibratedAt);

  Map<String, dynamic> toJson() => {
        'systolicOffset': systolicOffset,
        'diastolicOffset': diastolicOffset,
        'calibratedAt': calibratedAt.toIso8601String(),
      };

  factory BpCalibration.fromJson(Map<String, dynamic> j) => BpCalibration(
        (j['systolicOffset'] as num).toDouble(),
        (j['diastolicOffset'] as num).toDouble(),
        DateTime.parse(j['calibratedAt'] as String),
      );
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

/// The widest cuff-vs-PPG disagreement that is still plausibly sensor bias.
///
/// Beyond this the two are not measuring the same thing — a cuff on the wrong
/// arm, a number read off the wrong line, a digit typo. Encoding such a gap as
/// an offset would silently distort every later reading.
const maxSystolicOffset = 30.0;
const maxDiastolicOffset = 20.0;

/// Offsets derived from a cuff reading, or a refusal.
///
/// A refusal exists because the alternative is worse than useless: an offset of
/// -60 makes a genuine 165/105 — severe hypertension, a preeclampsia sign — read
/// as 105/85 and raise nothing. Silence there is the most dangerous outcome this
/// code can produce, so an implausible calibration is rejected and the user is
/// asked to measure again.
class BpOffsets {
  final double systolicOffset;
  final double diastolicOffset;

  /// Null when the calibration was accepted; otherwise why it was not.
  final String? rejectedBecause;

  const BpOffsets(this.systolicOffset, this.diastolicOffset, {this.rejectedBecause});

  bool get accepted => rejectedBecause == null;
}

/// Derive the offsets to store from a fresh cuff reading (offset = cuff − ppg).
///
/// Rejects a disagreement too wide to be sensor bias rather than trusting it.
BpOffsets computeBpOffsets(
  int cuffSystolic,
  int cuffDiastolic,
  int ppgSystolic,
  int ppgDiastolic,
) {
  final sys = (cuffSystolic - ppgSystolic).toDouble();
  final dia = (cuffDiastolic - ppgDiastolic).toDouble();
  if (sys.abs() > maxSystolicOffset || dia.abs() > maxDiastolicOffset) {
    return BpOffsets(0, 0,
        rejectedBecause: 'cuff and sensor disagree by '
            '${sys.abs().round()}/${dia.abs().round()} mmHg, too far apart to be calibration');
  }
  return BpOffsets(sys, dia);
}

int _clamp(int v, int lo, int hi) => math.min(hi, math.max(lo, v));

/// Log-distance path-loss model: RSSI → distance (m). txPower = RSSI @ 1m.
double rssiToDistanceM(int rssi, {int txPower = -59, double n = 2.5}) {
  if (rssi == 0) return -1;
  final ratio = (txPower - rssi) / (10 * n);
  return double.parse(math.pow(10, ratio).toStringAsFixed(2));
}
