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

  // ---- BP offsets (offset = cuff - ppg) ----
  final o = computeBpOffsets(128, 82, 120, 78);
  _chk('systolic offset = 8', o.systolicOffset == 8);
  _chk('diastolic offset = 4', o.diastolicOffset == 4);
  final oNeg = computeBpOffsets(115, 74, 120, 78);
  _chk('negative offsets', oNeg.systolicOffset == -5 && oNeg.diastolicOffset == -4);

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
