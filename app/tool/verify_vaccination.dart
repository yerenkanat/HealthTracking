/// Pure-Dart verification of the vaccination schedule.
/// `dart run tool/verify_vaccination.dart`
///
/// As with the development table, most of this checks the DATA. A wrong age
/// here is not a cosmetic bug: it is a parent arriving at the polyclinic in the
/// wrong month, or not arriving at all.
library;

import 'dart:io';
import '../lib/domain/vaccination.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The table is coherent ----
  {
    _chk('there is a schedule', kzSchedule.length > 10);
    _chk('it is dated, so a stale build is identifiable', scheduleRevision.isNotEmpty);

    _chk('no negative ages', kzSchedule.every((v) => v.atMonth >= 0));
    _chk('no empty ids', kzSchedule.every((v) => v.id.trim().isNotEmpty));

    // Authored in age order. scheduleByAge relies on insertion order, so a
    // vaccine inserted in the wrong place would silently reorder the screen.
    var ordered = true;
    for (var i = 1; i < kzSchedule.length; i++) {
      if (kzSchedule[i].atMonth < kzSchedule[i - 1].atMonth) ordered = false;
    }
    _chk('the table is authored in age order', ordered);

    // Doses of one vaccine must be numbered 1..n without gaps or repeats, or
    // the UI shows "доза 2" twice and no "доза 1".
    final byId = <String, List<int>>{};
    for (final v in kzSchedule) {
      if (v.dose != null) (byId[v.id] ??= []).add(v.dose!);
    }
    var dosesSane = true;
    byId.forEach((id, doses) {
      final sorted = [...doses]..sort();
      if (sorted.toSet().length != sorted.length) dosesSane = false; // repeat
      for (var i = 0; i < sorted.length; i++) {
        // DTP dose 4 is the booster of the pentavalent series, so a series may
        // legitimately start above 1 — what must not happen is a repeat or a
        // gap WITHIN one id.
        if (i > 0 && sorted[i] != sorted[i - 1] + 1) dosesSane = false;
      }
    });
    _chk('dose numbers within a vaccine run consecutively', dosesSane);

    // A single-dose vaccine must not also appear with a dose number.
    var mixed = false;
    final ids = kzSchedule.map((v) => v.id).toSet();
    for (final id in ids) {
      final entries = kzSchedule.where((v) => v.id == id);
      final withDose = entries.where((v) => v.dose != null).length;
      if (withDose != 0 && withDose != entries.length) mixed = true;
    }
    _chk('a vaccine is either dosed or single, never both', !mixed);

    // Two identical (id, dose) pairs would be the same injection scheduled
    // twice.
    final keys = kzSchedule.map((v) => '${v.id}/${v.dose}').toList();
    _chk('no vaccine is scheduled twice', keys.toSet().length == keys.length);
  }

  // ---- Status ----
  {
    final at2 = kzSchedule.firstWhere((v) => v.atMonth == 2);
    _chk('before its month: upcoming', vaccineStatus(at2, 1) == VaccineStatus.upcoming);
    _chk('on its month: due', vaccineStatus(at2, 2) == VaccineStatus.due);
    _chk('a few weeks late is still due, not missed',
        vaccineStatus(at2, 3) == VaccineStatus.due);
    _chk('well past: passed', vaccineStatus(at2, 5) == VaccineStatus.passed);

    // Birth doses are due from day one.
    final birth = kzSchedule.firstWhere((v) => v.atMonth == 0);
    _chk('birth doses are due at birth', vaccineStatus(birth, 0) == VaccineStatus.due);
  }

  // ---- What is due, and what is next ----
  {
    _chk('a newborn has birth doses due', vaccinesDue(0).isNotEmpty);
    _chk('and everything due really is due',
        vaccinesDue(4).every((v) => vaccineStatus(v, 4) == VaccineStatus.due));

    // The next visit is a VISIT — every vaccine at that age, because they are
    // given together. Naming one of three would have a parent arrive expecting
    // one injection.
    final next = nextVisit(0);
    _chk('the next visit is grouped by age', next.every((v) => v.atMonth == next.first.atMonth));
    _chk('and it is the soonest age ahead', next.first.atMonth == 2);
    _chk('at two months, three things are given together', nextVisit(0).length == 3);

    _chk('months until the next visit', monthsUntilNextVisit(0) == 2);
    _chk('and it counts down', monthsUntilNextVisit(1) == 1);
  }
  {
    // Past the end of the schedule there is nothing to promise.
    final last = kzSchedule.map((v) => v.atMonth).reduce((a, b) => a > b ? a : b);
    _chk('after the last vaccine there is no next visit', nextVisit(last + 1).isEmpty);
    _chk('and no countdown to invent', monthsUntilNextVisit(last + 1) == null);
    _chk('nothing is upcoming for an older child',
        kzSchedule.every((v) => vaccineStatus(v, last + 12) != VaccineStatus.upcoming));
  }

  // ---- Grouping ----
  {
    final byAge = scheduleByAge();
    _chk('grouping loses nothing',
        byAge.values.fold<int>(0, (n, l) => n + l.length) == kzSchedule.length);
    _chk('groups come out in age order',
        byAge.keys.toList().toString() == (byAge.keys.toList()..sort()).toString());
    _chk('the birth visit holds more than one vaccine', (byAge[0] ?? []).length >= 2);
  }

  // ---- The schedule covers the ages the app talks about ----
  {
    // The development calendar runs to about three years; the vaccination
    // schedule should not stop long before a parent stops looking.
    final ages = kzSchedule.map((v) => v.atMonth).toSet();
    _chk('the first year is covered', ages.where((a) => a <= 12).length >= 4);
    _chk('the second year is covered', ages.any((a) => a > 12 && a <= 24));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
