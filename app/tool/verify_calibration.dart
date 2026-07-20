/// Pure-Dart verification of the sensor calibration math (skin→core temp, PPG
/// blood-pressure calibration, RSSI→distance). `dart run tool/verify_calibration.dart`
library;

import 'dart:io';
import '../lib/ble/calibration.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- skin → core temperature ----
  final core = skinToCoreTempC(34.0);
  _chk('skin 34 → core above skin', core > 34.0);
  _chk('skin→core clamps to <= 42', skinToCoreTempC(41.0) <= 42.0);
  _chk('skin→core clamps to >= 34', skinToCoreTempC(20.0) >= 34.0);

  // The thresholds this estimate is judged against, from packages/shared
  // triage.ts. A skin temperature reachable by an ordinary warm wrist must not
  // cross either — an earlier version turned a 35.5°C wrist into a 38.5°C core
  // and raised the pregnancy high-fever emergency on a healthy woman in bed.
  const feverWarningC = 37.8;
  const feverEmergencyC = 38.5;
  _chk('a resting wrist reads as a normal core', () {
    final c = skinToCoreTempC(33.0);
    return c > 36.4 && c < 37.2;
  }());
  _chk('a wrist warmed by bedding is not a fever',
      skinToCoreTempC(35.5) < feverWarningC);
  _chk('a warm room is not a fever either', skinToCoreTempC(35.0) < feverWarningC);
  _chk('no ordinary wrist reaches the emergency threshold',
      skinToCoreTempC(36.0) < feverEmergencyC);
  // ...but a genuinely hot wrist must still be able to raise one, or the
  // measurement would be useless in the other direction.
  _chk('a genuinely hot wrist still reaches emergency',
      skinToCoreTempC(38.5) >= feverEmergencyC);
  _chk('warmer skin always means warmer core',
      skinToCoreTempC(34.0) < skinToCoreTempC(35.0) &&
          skinToCoreTempC(35.0) < skinToCoreTempC(36.0));
  // Core is regulated; it must not swing as widely as the skin it came from.
  _chk('core moves less than skin does',
      (skinToCoreTempC(36.0) - skinToCoreTempC(32.0)) < 4.0);

  // ---- BP offsets (offset = cuff - ppg) ----
  final o = computeBpOffsets(128, 82, 120, 78);
  _chk('systolic offset = 8', o.systolicOffset == 8);
  _chk('diastolic offset = 4', o.diastolicOffset == 4);
  _chk('a plausible calibration is accepted', o.accepted);
  final oNeg = computeBpOffsets(115, 74, 120, 78);
  _chk('negative offsets', oNeg.systolicOffset == -5 && oNeg.diastolicOffset == -4);
  _chk('a plausible negative calibration is accepted too', oNeg.accepted);

  // An offset far too large to be sensor bias is refused rather than stored.
  // The dangerous direction is the negative one: it would subtract from every
  // later reading and hide the hypertension this app exists to catch.
  final wayLow = computeBpOffsets(60, 40, 165, 105);
  _chk('a wildly low cuff reading is refused', !wayLow.accepted);
  _chk('a refusal explains itself', (wayLow.rejectedBecause ?? '').isNotEmpty);
  _chk('a refusal carries no offsets to apply by accident',
      wayLow.systolicOffset == 0 && wayLow.diastolicOffset == 0);
  final wayHigh = computeBpOffsets(240, 140, 120, 78);
  _chk('a wildly high cuff reading is refused', !wayHigh.accepted);

  // The boundary itself is accepted, so a real but large sensor bias still
  // calibrates — the check is against nonsense, not against being unusual.
  _chk('exactly the maximum systolic gap is accepted',
      computeBpOffsets(150, 78, 120, 78).accepted);
  _chk('one past it is not', !computeBpOffsets(151, 78, 120, 78).accepted);
  _chk('exactly the maximum diastolic gap is accepted',
      computeBpOffsets(120, 98, 120, 78).accepted);
  _chk('one past it is not', !computeBpOffsets(120, 99, 120, 78).accepted);

  // ---- apply calibration ----
  final cal = BpCalibration(8, -3, DateTime.parse('2026-07-14T00:00:00Z'));
  final applied = applyBpCalibration(120, 78, cal, now: DateTime.parse('2026-07-15T00:00:00Z'));
  _chk('applied systolic 120+8 = 128', applied.systolic == 128);
  _chk('applied diastolic 78-3 = 75', applied.diastolic == 75);
  _chk('fresh calibration not stale', !applied.calibrationStale);

  final stale = applyBpCalibration(120, 78, cal, now: DateTime.parse('2026-07-30T00:00:00Z'));
  _chk('old calibration flagged stale', stale.calibrationStale);

  final none = applyBpCalibration(140, 90, null);
  _chk('no calibration → passthrough + stale', none.systolic == 140 && none.calibrationStale);

  // clamps
  final clamped = applyBpCalibration(300, 200, BpCalibration(0, 0, DateTime.parse('2026-07-15T00:00:00Z')),
      now: DateTime.parse('2026-07-15T00:00:00Z'));
  _chk('applied BP clamps to sane range', clamped.systolic == 220 && clamped.diastolic == 140);

  // ---- RSSI → distance ----
  _chk('rssi == txPower → ~1m', (rssiToDistanceM(-59, txPower: -59) - 1.0).abs() < 0.01);
  _chk('weaker rssi → farther', rssiToDistanceM(-79, txPower: -59) > rssiToDistanceM(-69, txPower: -59));
  _chk('rssi 0 → invalid', rssiToDistanceM(0) == -1);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
