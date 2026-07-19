/// Pure-Dart verification of the medication/supplement domain.
/// `dart run tool/verify_medication.dart`
library;

import 'dart:io';
import '../lib/domain/medication.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  const folic = Medication(id: 'm1', name: 'Folic acid', dose: '400 mcg');
  const iron = Medication(id: 'm2', name: 'Iron', dose: '27 mg', perDay: 2);
  final meds = [folic, iron];
  final today = DateTime(2026, 7, 20);
  DateTime ago(int d) => today.subtract(Duration(days: d));

  // ---- Model ----
  _chk('perDay defaults to 1', folic.perDay == 1);
  _chk('perDay clamps low', Medication.clampPerDay(0) == 1);
  _chk('perDay clamps high', Medication.clampPerDay(99) == maxDosesPerDay);
  _chk('copyWith clamps', folic.copyWith(perDay: 50).perDay == maxDosesPerDay);
  final rt = Medication.fromJson(iron.toJson());
  _chk('round-trip fields', rt.id == 'm2' && rt.name == 'Iron' && rt.dose == '27 mg' && rt.perDay == 2);
  _chk('round-trip omits empty dose', !const Medication(id: 'x', name: 'N').toJson().containsKey('dose'));

  // ---- Taking doses ----
  MedLog log = {};
  log = takeDose(log, today, folic);
  _chk('dose recorded', dosesTaken(log, today, 'm1') == 1);
  log = takeDose(log, today, folic);
  _chk('caps at perDay', dosesTaken(log, today, 'm1') == 1);
  log = takeDose(log, today, iron);
  _chk('second med tracked separately', dosesTaken(log, today, 'm2') == 1);
  _chk('untouched day is zero', dosesTaken(log, ago(1), 'm1') == 0);

  // ---- Progress / completion ----
  var p = dayProgress(meds, log, today);
  _chk('progress counts planned doses', p.planned == 3); // 1 + 2
  _chk('progress counts taken', p.taken == 2);
  _chk('not complete yet', !dayComplete(meds, log, today));
  log = takeDose(log, today, iron);
  _chk('complete when all taken', dayComplete(meds, log, today));
  _chk('no meds → never complete', !dayComplete(const [], log, today));

  // ---- Undo ----
  log = undoDose(log, today, 'm2');
  _chk('undo decrements', dosesTaken(log, today, 'm2') == 1);
  _chk('undo breaks completion', !dayComplete(meds, log, today));
  var cleared = undoDose(undoDose(undoDose(log, today, 'm2'), today, 'm1'), today, 'm1');
  _chk('undo never goes negative', dosesTaken(cleared, today, 'm1') == 0);
  _chk('emptied day is dropped', !cleared.containsKey('2026-07-20'));

  // ---- Streak ----
  MedLog full = {};
  for (var i = 1; i <= 3; i++) {
    full = takeDose(full, ago(i), folic);
    full = takeDose(takeDose(full, ago(i), iron), ago(i), iron);
  }
  _chk('streak counts complete days', adherenceStreak(meds, full, today) == 3);
  _chk('unfinished today does not break it', adherenceStreak(meds, takeDose(full, today, folic), today) == 3);
  final finished = takeDose(takeDose(takeDose(full, today, folic), today, iron), today, iron);
  _chk('finished today extends it', adherenceStreak(meds, finished, today) == 4);
  var gap = Map<String, Map<String, int>>.from(full)..remove('2026-07-18'); // ago(2)
  _chk('a missed day ends it', adherenceStreak(meds, gap, today) == 1);
  _chk('no meds → no streak', adherenceStreak(const [], full, today) == 0);

  // ---- Adherence rate ----
  // 3 complete days out of a 7-day window = 9 of 21 planned doses.
  final rate = adherenceRate(meds, full, today, days: 7)!;
  _chk('adherence rate over the window', (rate - (9 / 21)).abs() < 1e-9);
  _chk('rate never exceeds 1', adherenceRate(meds, finished, today, days: 1)! <= 1.0);
  _chk('no meds → null rate', adherenceRate(const [], full, today) == null);

  // ---- Totals + JSON ----
  _chk('total doses logged', totalDosesLogged(full) == 9);
  _chk('empty log totals zero', totalDosesLogged(const {}) == 0);
  final logRt = medLogFromJson(medLogToJson(full));
  _chk('log round-trips', dosesTaken(logRt, ago(1), 'm2') == 2);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
