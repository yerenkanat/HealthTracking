/// Pure-Dart verification of the journey totals roll-up.
/// `dart run tool/verify_journey.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/journey_stats.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final dayLogs = <String, DayLog>{
    '2026-07-01': const DayLog(date: '2026-07-01', mood: Mood.happy, note: 'first scan'),
    '2026-07-02': const DayLog(date: '2026-07-02', symptoms: {Symptom.cramps}),
    '2026-07-03': const DayLog(date: '2026-07-03'), // empty → not counted
    '2026-07-04': const DayLog(date: '2026-07-04', note: 'felt great'),
  };
  final periodDays = <DateTime>{
    for (var i = 0; i < 5; i++) DateTime(2026, 6, 1).add(Duration(days: i)),
    for (var i = 0; i < 5; i++) DateTime(2026, 6, 29).add(Duration(days: i)),
  };
  final waterLog = {'2026-07-01': 8, '2026-07-02': 5};

  final t = computeJourneyTotals(
    dayLogs: dayLogs,
    periodDays: periodDays,
    kickSessions: 3,
    contractionSessions: 1,
    appointments: 2,
    weightEntries: 4,
    waterLog: waterLog,
  );
  _chk('days logged counts non-empty', t.daysLogged == 3);
  _chk('notes counts noted days', t.notes == 2);
  _chk('cycles = distinct period starts', t.cyclesTracked == 2);
  _chk('kick sessions passthrough', t.kickSessions == 3);
  _chk('contraction sessions passthrough', t.contractionSessions == 1);
  _chk('appointments passthrough', t.appointments == 2);
  _chk('weight entries passthrough', t.weightEntries == 4);
  _chk('water glasses summed', t.waterGlasses == 13);
  _chk('has any', t.hasAny);

  final empty = computeJourneyTotals(
    dayLogs: const {}, periodDays: const {}, kickSessions: 0, contractionSessions: 0,
    appointments: 0, weightEntries: 0, waterLog: const {},
  );
  _chk('empty has nothing', !empty.hasAny && empty.daysLogged == 0 && empty.waterGlasses == 0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
