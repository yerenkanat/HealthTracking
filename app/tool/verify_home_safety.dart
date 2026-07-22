/// Pure-Dart verification of the home-safety checklist.
/// `dart run tool/verify_home_safety.dart`
library;

import 'dart:io';
import '../lib/domain/home_safety.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  {
    _chk('there is a checklist', homeSafetyTasks.length >= 12);
    _chk('every task has a non-empty id', homeSafetyTasks.every((t) => t.id.trim().isNotEmpty));
    final ids = homeSafetyTasks.map((t) => t.id).toList();
    _chk('ids are unique', ids.toSet().length == ids.length);

    for (final s in SafetyStage.values) {
      _chk('the ${s.name} stage has tasks', homeSafetyTasks.any((t) => t.stage == s));
    }
    _chk('birth-stage tasks start at month 0', homeSafetyTasks.where((t) => t.stage == SafetyStage.birth).every((t) => t.fromMonth == 0));
    _chk('stages get later', stageFromMonth(SafetyStage.birth) < stageFromMonth(SafetyStage.rolling));
    _chk('and later still', stageFromMonth(SafetyStage.crawling) < stageFromMonth(SafetyStage.standing));

    _chk('safe sleep is a birth task', ids.contains('safe_sleep_space'));
    _chk('a stair gate is a crawling task',
        homeSafetyTasks.any((t) => t.id == 'stair_gates' && t.stage == SafetyStage.crawling));
    _chk('anchoring furniture is a standing task',
        homeSafetyTasks.any((t) => t.id == 'furniture_anchored' && t.stage == SafetyStage.standing));
  }

  // ---- Relevance grows with age ----
  {
    // A newborn sees only the birth tasks.
    final nb = tasksForAge(0);
    _chk('a newborn sees the birth tasks', nb.isNotEmpty);
    _chk('and NOT the stair gate yet', !nb.any((t) => t.id == 'stair_gates'));

    // A crawler sees birth + rolling + crawling, not standing.
    final crawler = tasksForAge(7).map((t) => t.id).toSet();
    _chk('a crawler sees outlet covers', crawler.contains('outlet_covers'));
    _chk('a crawler sees the stair gate', crawler.contains('stair_gates'));
    _chk('a crawler does NOT yet see furniture anchoring', !crawler.contains('furniture_anchored'));

    // An older baby sees everything.
    _chk('a one-year-old sees every task', tasksForAge(12).length == homeSafetyTasks.length);

    // Relevance is monotonic — the list only grows.
    var ok = true;
    for (var m = 0; m < 24; m++) {
      if (tasksForAge(m + 1).length < tasksForAge(m).length) ok = false;
    }
    _chk('the list never shrinks as the child grows', ok);
  }

  // ---- Progress maths ----
  {
    _chk('nothing done is zero at any age', homeSafetyDoneCount(const {}, 12) == 0);
    _chk('and the fraction is zero', homeSafetyFraction(const {}, 12) == 0);

    // A tick for a not-yet-relevant task does not count.
    _chk('a tick for a future task does not count now',
        homeSafetyDoneCount({'stair_gates'}, 1) == 0);
    _chk('but it counts once the age is reached',
        homeSafetyDoneCount({'stair_gates'}, 8) == 1);

    // A stale id is ignored.
    _chk('a stale tick is ignored', homeSafetyDoneCount({'a_task_removed_later'}, 12) == 0);

    final allRelevant = {for (final t in tasksForAge(12)) t.id};
    _chk('everything relevant done is a full fraction', homeSafetyFraction(allRelevant, 12) == 1.0);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
