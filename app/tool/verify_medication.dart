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
  // 3 complete days in the window. The denominator is 6 days, not 7: an
  // unfinished today is left out, exactly as adherenceStreak leaves it out.
  // Counting it charged her for doses the day had not yet reached.
  final rate = adherenceRate(meds, full, today, days: 7)!;
  _chk('adherence rate over the window', (rate - (9 / 18)).abs() < 1e-9);
  _chk('rate never exceeds 1', adherenceRate(meds, finished, today, days: 1)! <= 1.0);
  _chk('no meds → null rate', adherenceRate(const [], full, today) == null);

  // ---- History ----
  final hist = adherenceHistory(meds, full, today, days: 5);
  _chk('history length matches the window', hist.length == 5);
  _chk('history is oldest-first', hist.first.day.isBefore(hist.last.day));
  _chk('history ends on today', hist.last.day == today);
  _chk('planned uses the current regimen', hist.every((d) => d.planned == 3));
  _chk('a complete day reads 3/3', hist[hist.length - 2].taken == 3); // yesterday
  _chk('today (untouched) reads 0/3', hist.last.taken == 0);
  _chk('history with no meds is all zero',
      adherenceHistory(const [], full, today, days: 3).every((d) => d.planned == 0 && d.taken == 0));

  // ---- Totals + JSON ----
  _chk('total doses logged', totalDosesLogged(full) == 9);
  _chk('empty log totals zero', totalDosesLogged(const {}) == 0);
  final logRt = medLogFromJson(medLogToJson(full));
  _chk('log round-trips', dosesTaken(logRt, ago(1), 'm2') == 2);

  // ---- An unfinished today must not read as a missed today ----
  //
  // The rate counted today's full plan in the denominator from midnight, so at
  // nine in the morning a woman who has never missed a dose saw 86% — climbing
  // back to 100% only by bedtime. Every day opened by telling her she was
  // slipping. adherenceStreak already refused to penalise an unfinished day;
  // the rate simply did not do the same.
  {
    final today = DateTime(2026, 7, 21);
    DateTime ago(int d) => today.subtract(Duration(days: d));
    const iron = Medication(id: 'iron', name: 'Iron', perDay: 3);
    final meds = [iron];

    // Six perfect days behind her, nothing taken yet today.
    var log = <String, Map<String, int>>{};
    for (var d = 1; d <= 6; d++) {
      for (var i = 0; i < 3; i++) {
        log = takeDose(log, ago(d), iron);
      }
    }
    _chk('a perfect record reads as perfect first thing in the morning',
        adherenceRate(meds, log, today) == 1.0);

    // Part-way through today — still not counted against her.
    var partial = takeDose(log, today, iron);
    _chk('one of three taken today does not lower it',
        adherenceRate(meds, partial, today) == 1.0);

    // Finishing today counts immediately, rather than waiting for midnight.
    partial = takeDose(takeDose(partial, today, iron), today, iron);
    _chk('completing today keeps it perfect', adherenceRate(meds, partial, today) == 1.0);

    // A genuinely missed day still shows. This is the whole point of the
    // number, and it must not have been softened away.
    var missed = <String, Map<String, int>>{};
    for (var d = 1; d <= 6; d++) {
      if (d == 3) continue; // missed entirely
      for (var i = 0; i < 3; i++) {
        missed = takeDose(missed, ago(d), iron);
      }
    }
    final r = adherenceRate(meds, missed, today)!;
    _chk('a missed day still lowers the rate', r > 0.8 && r < 0.9);

    // A partially missed day counts partially.
    var half = <String, Map<String, int>>{};
    for (var d = 1; d <= 6; d++) {
      final n = d == 2 ? 1 : 3;
      for (var i = 0; i < n; i++) {
        half = takeDose(half, ago(d), iron);
      }
    }
    _chk('a partly missed day counts partly',
        adherenceRate(meds, half, today)! < 1.0);

    // Nothing logged at all. Those past days WERE planned and WERE missed, so
    // 0% is the honest answer — leaving today out must not soften a real miss
    // into "no data". (My first draft of this asserted null and was wrong.)
    _chk('a completely unlogged week reads as 0%, not "no data"',
        adherenceRate(meds, const {}, today) == 0.0);
    // Null is reserved for nothing PLANNED, which is a different statement.
    _chk('no medications at all reports nothing',
        adherenceRate(const [], const {}, today) == null);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
