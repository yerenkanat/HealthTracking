/// Pure-Dart verification of manual vitals validation.
/// `dart run tool/verify_manual_vitals.dart`
library;

import 'dart:io';
import '../lib/domain/manual_vitals.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Ranges ----
  _chk('resting HR in range', inVitalRange(VitalField.heartRate, 62));
  _chk('HR typo rejected', !inVitalRange(VitalField.heartRate, 620));
  _chk('HR lower bound inclusive', inVitalRange(VitalField.heartRate, 20));
  _chk('spo2 caps at 100', inVitalRange(VitalField.spo2, 100) && !inVitalRange(VitalField.spo2, 101));
  _chk('temperature accepts decimals', inVitalRange(VitalField.temperature, 36.6));
  _chk('temperature typo rejected', !inVitalRange(VitalField.temperature, 366));

  // Dangerous-but-real values must still be accepted — triage judges them,
  // validation only guards against typos.
  _chk('hypertensive crisis is plausible', inVitalRange(VitalField.systolic, 190));
  _chk('severe hypoxia is plausible', inVitalRange(VitalField.spo2, 82));
  _chk('high fever is plausible', inVitalRange(VitalField.temperature, 40.5));

  // ---- Whole-reading validation ----
  _chk('empty reading rejected', validateVitals(const ManualVitals()).contains(VitalsError.empty));
  _chk('temperature alone is fine', vitalsAreValid(const ManualVitals(temperature: 36.8)));
  _chk('HR alone is fine', vitalsAreValid(const ManualVitals(heartRate: 70)));
  _chk('full reading is fine', vitalsAreValid(const ManualVitals(heartRate: 70, spo2: 98, systolic: 118, diastolic: 76, temperature: 36.6)));

  _chk('out-of-range flagged', validateVitals(const ManualVitals(heartRate: 900)).contains(VitalsError.outOfRange));

  // Blood pressure is a pair.
  _chk('systolic alone rejected',
      validateVitals(const ManualVitals(systolic: 120)).contains(VitalsError.bloodPressurePartial));
  _chk('diastolic alone rejected',
      validateVitals(const ManualVitals(diastolic: 80)).contains(VitalsError.bloodPressurePartial));
  _chk('both together accepted', vitalsAreValid(const ManualVitals(systolic: 120, diastolic: 80)));

  // Transposition: "120/80" typed as "80/120".
  _chk('diastolic above systolic rejected',
      validateVitals(const ManualVitals(systolic: 80, diastolic: 120)).contains(VitalsError.diastolicNotBelowSystolic));
  _chk('equal values rejected',
      validateVitals(const ManualVitals(systolic: 100, diastolic: 100)).contains(VitalsError.diastolicNotBelowSystolic));
  _chk('narrow but valid gap accepted', vitalsAreValid(const ManualVitals(systolic: 101, diastolic: 100)));

  _chk('isEmpty is true for a blank reading', const ManualVitals().isEmpty);
  _chk('isEmpty is false with one field', !const ManualVitals(spo2: 97).isEmpty);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
