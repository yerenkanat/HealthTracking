/// Pure-Dart verification of the weekly-digest roll-up.
/// `dart run tool/verify_weekly_digest.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/sleep.dart';
import '../lib/domain/weekly_digest.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final today = DateTime(2026, 7, 20);
  String k(int daysAgo) => dateKey(today.subtract(Duration(days: daysAgo)));

  final dayLogs = <String, DayLog>{
    k(0): DayLog(date: k(0), mood: Mood.happy), // logged
    k(2): DayLog(date: k(2), symptoms: const {Symptom.cramps}), // logged
    k(4): DayLog(date: k(4)), // empty → not counted
    k(9): DayLog(date: k(9), mood: Mood.sad), // outside window
  };
  final waterLog = <String, int>{
    k(0): 8, // meets goal
    k(1): 5,
    k(3): 10, // meets goal
    k(10): 8, // outside window
  };
  final nights = <SleepSummary>[
    SleepSummary(night: today.subtract(const Duration(days: 1)), deepMin: 90, remMin: 90, lightMin: 240), // 420
    SleepSummary(night: today.subtract(const Duration(days: 3)), deepMin: 60, remMin: 60, lightMin: 180), // 300
    SleepSummary(night: today.subtract(const Duration(days: 12)), deepMin: 60, remMin: 60, lightMin: 180), // outside
  ];

  final d = computeWeeklyDigest(dayLogs, waterLog, nights, today);
  _chk('days logged counts non-empty in window', d.daysLogged == 2);
  _chk('water glasses summed in window', d.waterGlasses == 23); // 8+5+10
  _chk('water goal days', d.waterGoalDays == 2); // 8 and 10
  _chk('sleep nights in window', d.sleepNights == 2);
  _chk('avg sleep minutes', d.avgSleepMin == 360); // (420+300)/2
  _chk('has data', d.hasData);

  final empty = computeWeeklyDigest(const {}, const {}, const [], today);
  _chk('empty digest has no data', !empty.hasData && empty.avgSleepMin == 0 && empty.sleepNights == 0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
