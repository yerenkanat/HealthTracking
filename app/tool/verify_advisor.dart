/// Pure-Dart verification of the HealthAdvisor (data-grounded advice from band data).
/// `dart run tool/verify_advisor.dart`
library;

import 'dart:io';
import '../lib/domain/health_advisor.dart';
import '../lib/domain/health_series.dart';
import '../lib/domain/sleep.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

DateTime _t(int m) => DateTime.utc(2026, 7, 15, 8, m);
bool _has(List<Advisory> a, String code) => a.any((x) => x.code == code);

void main() {
  // ---- Too little data → gathering ----
  final few = [HealthSample(at: _t(0), heartRate: 72)];
  final g = generateAdvisories(few);
  _chk('few samples → ADV_GATHERING only', g.length == 1 && g.first.code == 'ADV_GATHERING');

  // ---- All-normal → steady/reassuring, no watch ----
  final normal = [
    for (var i = 0; i < 6; i++)
      HealthSample(at: _t(i), heartRate: 72 + (i.isEven ? 0 : 1), spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.6),
  ];
  final n = generateAdvisories(normal);
  _chk('normal → ADV_ALL_STEADY', _has(n, 'ADV_ALL_STEADY'));
  _chk('normal → no watch tone', n.every((a) => a.tone != AdviceTone.watch));
  _chk('normal → BP steady advisory', _has(n, 'ADV_BP_STEADY'));
  _chk('normal → temp steady', _has(n, 'ADV_TEMP_STEADY'));
  _chk('normal → spo2 steady', _has(n, 'ADV_SPO2_STEADY'));

  // ---- restful sleep (all sleep, no dips) ----
  final sleep = [
    for (var i = 0; i < 5; i++)
      HealthSample(at: _t(i), heartRate: 60, spo2: 97, duringSleep: true, systolic: 116, diastolic: 74, coreTemp: 36.6),
  ];
  _chk('sleep samples, no dips → ADV_SLEEP_OK', _has(generateAdvisories(sleep), 'ADV_SLEEP_OK'));

  // ---- Elevated BP (below emergency) → watch ----
  final bp = [
    for (var i = 0; i < 5; i++)
      HealthSample(at: _t(i), heartRate: 74, spo2: 97, systolic: 138, diastolic: 86, coreTemp: 36.7),
  ];
  final b = generateAdvisories(bp);
  _chk('systolic 138 → ADV_BP_ELEVATED (watch)', _has(b, 'ADV_BP_ELEVATED'));
  _chk('watch advisory is first', b.first.tone == AdviceTone.watch);

  // ---- Rising HR trend ----
  final hr = [
    HealthSample(at: _t(0), heartRate: 68), HealthSample(at: _t(1), heartRate: 70),
    HealthSample(at: _t(2), heartRate: 72), HealthSample(at: _t(3), heartRate: 84),
    HealthSample(at: _t(4), heartRate: 86), HealthSample(at: _t(5), heartRate: 88),
  ];
  _chk('rising HR → ADV_HR_RISING', _has(generateAdvisories(hr), 'ADV_HR_RISING'));

  // ---- SpO2 dip during sleep ----
  final spo2 = [
    for (var i = 0; i < 5; i++)
      HealthSample(at: _t(i), heartRate: 60, spo2: i == 2 ? 92 : 97, duringSleep: true, systolic: 118, diastolic: 74),
  ];
  _chk('sleep SpO2 92 → ADV_SPO2_SLEEP_DIP', _has(generateAdvisories(spo2), 'ADV_SPO2_SLEEP_DIP'));

  // ---- Elevated temperature ----
  final temp = [
    for (var i = 0; i < 5; i++)
      HealthSample(at: _t(i), heartRate: 78, systolic: 118, diastolic: 76, coreTemp: i == 4 ? 37.9 : 36.8),
  ];
  _chk('temp 37.9 → ADV_TEMP_ELEVATED', _has(generateAdvisories(temp), 'ADV_TEMP_ELEVATED'));

  // ---- Sleep advisories (nightly summary) ----
  final steady = [
    for (var i = 0; i < 5; i++)
      HealthSample(at: _t(i), heartRate: 74, spo2: 98, systolic: 118, diastolic: 76, coreTemp: 36.7),
  ];
  final shortNight = SleepSummary(night: DateTime(2026, 7, 15), deepMin: 30, remMin: 40, lightMin: 170, awakeMin: 60); // 4h
  _chk('short sleep → ADV_SLEEP_SHORT', _has(generateAdvisories(steady, lastNight: shortNight), 'ADV_SLEEP_SHORT'));
  final goodNight = SleepSummary(night: DateTime(2026, 7, 15), deepMin: 90, remMin: 100, lightMin: 270, awakeMin: 30); // 7h40
  _chk('good sleep → ADV_SLEEP_GOOD', _has(generateAdvisories(steady, lastNight: goodNight), 'ADV_SLEEP_GOOD'));
  _chk('no lastNight → no ADV_SLEEP_SHORT', !_has(generateAdvisories(steady), 'ADV_SLEEP_SHORT'));

  // ---- Multi-night sleep trend ----
  SleepSummary short(int day) =>
      SleepSummary(night: DateTime(2026, 7, day), deepMin: 30, remMin: 40, lightMin: 160, awakeMin: 60); // ~3h50
  SleepSummary ok(int day) =>
      SleepSummary(night: DateTime(2026, 7, day), deepMin: 90, remMin: 100, lightMin: 270, awakeMin: 30); // 7h40
  final threeShort = [short(15), short(14), short(13)];
  _chk('three short nights → ADV_SLEEP_DEBT',
      _has(generateAdvisories(steady, lastNight: shortNight, recentNights: threeShort), 'ADV_SLEEP_DEBT'));
  _chk('the debt trend replaces the single-night short note',
      !_has(generateAdvisories(steady, lastNight: shortNight, recentNights: threeShort), 'ADV_SLEEP_SHORT'));
  _chk('two short nights is not yet a trend',
      !_has(generateAdvisories(steady, recentNights: [short(15), short(14)]), 'ADV_SLEEP_DEBT'));
  _chk('a good night in the run breaks the trend',
      !_has(generateAdvisories(steady, recentNights: [short(15), ok(14), short(13)]), 'ADV_SLEEP_DEBT'));
  _chk('order does not matter — newest three are taken',
      _has(generateAdvisories(steady, recentNights: [short(13), short(15), short(14), ok(10)]), 'ADV_SLEEP_DEBT'));

  // ---- Hydration ----
  _chk('goal met → ADV_HYDRATED', _has(generateAdvisories(steady, waterCount: 8, waterGoal: 8), 'ADV_HYDRATED'));
  _chk('evening + behind → ADV_HYDRATE_LOW (watch)',
      _has(generateAdvisories(steady, waterCount: 2, waterGoal: 8, hour: 20), 'ADV_HYDRATE_LOW'));
  _chk('morning + behind → no nudge',
      !_has(generateAdvisories(steady, waterCount: 2, waterGoal: 8, hour: 9), 'ADV_HYDRATE_LOW'));
  _chk('evening but over half → no nudge',
      !_has(generateAdvisories(steady, waterCount: 5, waterGoal: 8, hour: 20), 'ADV_HYDRATE_LOW'));
  _chk('no water tracked → no hydration advisory',
      !_has(generateAdvisories(steady), 'ADV_HYDRATED') && !_has(generateAdvisories(steady), 'ADV_HYDRATE_LOW'));
  _chk('medical watch still ranks before hydration nudge',
      generateAdvisories(bp, waterCount: 1, waterGoal: 8, hour: 20).first.code == 'ADV_BP_ELEVATED');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
