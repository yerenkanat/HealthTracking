/// Pure-Dart verification of the Kazakhstan antenatal-care schedule.
/// `dart run tool/verify_antenatal_protocol.dart`
///
/// This is a government clinical protocol turned into an algorithm, so the
/// things that matter are the ones a clinic would be audited on: the eight
/// visits exist and sit in the right weeks, the dated screening windows open
/// and close where the protocol says, and the safety-critical items live on the
/// visit they belong to (anti-D at the third visit / 28–30 weeks; the anomaly
/// scan in the 19–21 window; the glucose test at 24–28). A wrong window here
/// would tell a woman a screening is still ahead of her when it has already
/// closed.
library;

import 'dart:io';
import '../lib/domain/antenatal_protocol.dart';
import '../lib/domain/cycle_log.dart' show gestationFor;

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The eight-visit plan is coherent ----
  {
    _chk('there are at least 8 visits', antenatalVisits.length >= 8);
    _chk('visits are numbered 1..8 in order', () {
      for (var i = 0; i < antenatalVisits.length; i++) {
        if (antenatalVisits[i].number != i + 1) return false;
      }
      return true;
    }());
    _chk('no visit window is inside-out',
        antenatalVisits.every((v) => v.fromWeek <= v.toWeek));
    _chk('no visit runs past week 40', antenatalVisits.every((v) => v.toWeek <= 40));
    _chk('the first visit is not before week 10', antenatalVisits.first.fromWeek >= 10);
    _chk('visit windows do not overlap and advance in time', () {
      for (var i = 1; i < antenatalVisits.length; i++) {
        if (antenatalVisits[i].fromWeek <= antenatalVisits[i - 1].toWeek) return false;
      }
      return true;
    }());
    _chk('every visit has at least one item',
        antenatalVisits.every((v) => v.items.isNotEmpty));
    _chk('every item has a non-empty id',
        antenatalVisits.every((v) => v.items.every((it) => it.id.trim().isNotEmpty)));
    _chk('no visit lists the same item twice', antenatalVisits.every((v) {
      final ids = v.items.map((it) => it.id).toList();
      return ids.toSet().length == ids.length;
    }));
    _chk('every category is represented somewhere', () {
      final cats = {for (final v in antenatalVisits) ...v.items.map((it) => it.category)};
      return cats.length == AntenatalCategory.values.length;
    }());
  }

  // ---- The visits sit where the protocol puts them ----
  {
    int fromOf(int n) => antenatalVisits[n - 1].fromWeek;
    int toOf(int n) => antenatalVisits[n - 1].toWeek;
    _chk('visit 1 is 10–12 weeks', fromOf(1) == 10 && toOf(1) == 12);
    _chk('visit 2 is 16–20 weeks', fromOf(2) == 16 && toOf(2) == 20);
    _chk('visit 3 is 26–28 weeks', fromOf(3) == 26 && toOf(3) == 28);
    _chk('visit 4 is at 30 weeks', fromOf(4) == 30 && toOf(4) == 30);
    _chk('visit 5 is at 34 weeks', fromOf(5) == 34);
    _chk('visit 6 is at 36 weeks', fromOf(6) == 36);
    _chk('visit 7 is at 38 weeks', fromOf(7) == 38);
    _chk('visit 8 is at 40 weeks (up to 40+6)', fromOf(8) == 40);
  }

  // ---- Safety-critical items are on the right visit ----
  {
    bool visitHas(int n, String id) =>
        antenatalVisits[n - 1].items.any((it) => it.id == id);

    _chk('the dating scan is at visit 1', visitHas(1, 'us_dating'));
    _chk('blood type & rhesus is drawn at visit 1', visitHas(1, 'blood_type_rh'));
    _chk('folic acid is started at visit 1', visitHas(1, 'folic_acid'));
    _chk('the anomaly scan is at visit 2', visitHas(2, 'us_anomaly'));
    _chk('fundal height begins at visit 2 (from 20 weeks)', visitHas(2, 'fundal_height'));
    _chk('the glucose-tolerance test is at visit 3', visitHas(3, 'ogtt'));
    _chk('anti-D is at visit 3 (28–30 weeks)', visitHas(3, 'anti_d'));
    _chk('the fetal heartbeat is auscultated from visit 3', visitHas(3, 'fetal_heartbeat'));
    _chk('maternity leave is issued at visit 4 (30 weeks)', visitHas(4, 'maternity_leave'));
    _chk('the growth scan is at visit 4 (30–32 weeks)', visitHas(4, 'us_growth'));
    _chk('presentation is checked from visit 6', visitHas(6, 'fetal_position'));
    _chk('the post-term / 41-week talk is at visit 8', visitHas(8, 'hospital_41w'));

    // Blood pressure and urine protein are the every-visit staples once they
    // begin — a lapse in either is how pre-eclampsia is missed.
    _chk('blood pressure is measured at every visit',
        antenatalVisits.every((v) => v.items.any((it) => it.id == 'bp_pulse')));
    _chk('urine protein is checked at visits 2..8',
        antenatalVisits.skip(1).every((v) => v.items.any((it) => it.id == 'urine_protein')));
  }

  // ---- Risk-scoped items are flagged, universal ones are not ----
  {
    AntenatalItem itemOf(int n, String id) =>
        antenatalVisits[n - 1].items.firstWhere((it) => it.id == id);
    _chk('aspirin is a risk-group item', itemOf(1, 'aspirin').risk);
    _chk('anti-D is a risk-group item', itemOf(3, 'anti_d').risk);
    _chk('OGTT is a risk-group item', itemOf(3, 'ogtt').risk);
    _chk('folic acid is universal, not risk-scoped', !itemOf(1, 'folic_acid').risk);
    _chk('blood pressure is universal', !itemOf(1, 'bp_pulse').risk);
    _chk('the dating scan is universal', !itemOf(1, 'us_dating').risk);
  }

  // ---- The dated screening windows ----
  {
    AntenatalWindow winOf(String id) => antenatalWindows.firstWhere((w) => w.id == id);
    _chk('window ids are unique',
        antenatalWindows.map((w) => w.id).toSet().length == antenatalWindows.length);
    _chk('no window is inside-out', antenatalWindows.every((w) => w.fromWeek <= w.toWeek));
    _chk('the dating scan window is 11–13 weeks',
        winOf('us_dating').fromWeek == 11 && winOf('us_dating').toWeek == 13);
    _chk('the anomaly scan window is 19–21 weeks',
        winOf('us_anomaly').fromWeek == 19 && winOf('us_anomaly').toWeek == 21);
    _chk('the growth scan window is 30–32 weeks',
        winOf('us_growth').fromWeek == 30 && winOf('us_growth').toWeek == 32);
    _chk('the OGTT window is 24–28 weeks',
        winOf('ogtt').fromWeek == 24 && winOf('ogtt').toWeek == 28);
    _chk('the anti-D window is 28–30 weeks',
        winOf('anti_d').fromWeek == 28 && winOf('anti_d').toWeek == 30);
    _chk('OGTT and anti-D windows are risk-scoped',
        winOf('ogtt').risk && winOf('anti_d').risk);
  }

  // ---- The "what now" algorithm ----
  {
    // Before the first visit: nothing is due, but the first visit is next.
    _chk('at week 6 no visit is due', visitAtWeek(6) == null);
    _chk('at week 6 the next visit is visit 1', nextVisitAfter(6)?.number == 1);
    _chk('at week 6 currentOrNext is visit 1', currentOrNextVisit(6)?.number == 1);

    // Inside a window: that visit is due.
    _chk('at week 11 visit 1 is due', visitAtWeek(11)?.number == 1);
    _chk('at week 27 visit 3 is due', visitAtWeek(27)?.number == 3);
    _chk('at week 30 visit 4 is due', visitAtWeek(30)?.number == 4);

    // Between windows: none due, the following visit is next.
    _chk('at week 22 no visit is due', visitAtWeek(22) == null);
    _chk('at week 22 the next visit is visit 3', nextVisitAfter(22)?.number == 3);
    _chk('at week 32 the next visit is visit 5', nextVisitAfter(32)?.number == 5);

    // After the last visit window there is no next visit — term has come.
    _chk('past week 40 there is no next visit', nextVisitAfter(41) == null);
    _chk('past week 40 currentOrNext is null', currentOrNextVisit(41) == null);
  }

  // ---- Windows-open-at and progress ----
  {
    final w12 = windowsOpenAt(12).map((w) => w.id).toSet();
    _chk('at week 12 the dating scan window is open', w12.contains('us_dating'));
    _chk('at week 12 the anomaly window is not yet open', !w12.contains('us_anomaly'));

    final w20 = windowsOpenAt(20).map((w) => w.id).toSet();
    _chk('at week 20 the anomaly window is open', w20.contains('us_anomaly'));

    final w28 = windowsOpenAt(28).map((w) => w.id).toSet();
    _chk('at week 28 both OGTT and anti-D windows are open',
        w28.contains('ogtt') && w28.contains('anti_d'));

    _chk('nothing is open at week 6', windowsOpenAt(6).isEmpty);

    _chk('no visits are counted complete before week 12', visitsCompletedBy(11) == 0);
    _chk('two visits are complete by week 20', visitsCompletedBy(20) == 2);
    _chk('all eight are complete by week 40', visitsCompletedBy(40) == 8);
  }

  // visitOpensOn: a visit's window opens (40 − fromWeek) weeks before the EDD.
  {
    final due = DateTime(2026, 12, 31);
    final v1 = antenatalVisits.firstWhere((v) => v.number == 1); // fromWeek 10
    final v3 = antenatalVisits.firstWhere((v) => v.number == 3); // fromWeek 26
    final v8 = antenatalVisits.firstWhere((v) => v.number == 8); // fromWeek 40
    _chk('visit 1 (wk 10) opens 30 weeks before the due date',
        visitOpensOn(v1, due) == due.subtract(const Duration(days: 30 * 7)));
    _chk('visit 3 (wk 26) opens 14 weeks before the due date',
        visitOpensOn(v3, due) == due.subtract(const Duration(days: 14 * 7)));
    _chk('visit 8 (wk 40) opens on the due date',
        visitOpensOn(v8, due) == DateTime(due.year, due.month, due.day));
    _chk('the booked date lands on the visit\'s own gestational week',
        gestationFor(due, visitOpensOn(v3, due))!.week == v3.fromWeek);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
