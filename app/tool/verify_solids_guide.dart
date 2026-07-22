/// Pure-Dart verification of the starting-solids guide.
/// `dart run tool/verify_solids_guide.dart`
library;

import 'dart:io';
import '../lib/domain/solids_guide.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Anchors ----
  {
    _chk('start is around six months', solidsStartMonth == 6);
    _chk('not before four months', solidsNotBeforeMonth == 4);
    _chk('the not-before floor is not after the start', solidsNotBeforeMonth <= solidsStartMonth);
    _chk('the window opens at the floor', solidsFromMonth == solidsNotBeforeMonth);
    _chk('the window is a real range', solidsFromMonth < solidsToMonth);
  }

  // ---- Lists ----
  {
    _chk('there are readiness signs', readinessSigns.length >= 3);
    _chk('readiness ids are unique', readinessSigns.toSet().length == readinessSigns.length);

    _chk('there are foods to avoid', avoidFoods.length >= 3);
    _chk('avoid ids are unique', avoidFoods.toSet().length == avoidFoods.length);
    _chk('honey is on the avoid list', avoidFoods.contains('honey'));
    _chk('choking hazards are on the avoid list', avoidFoods.contains('choking'));

    _chk('there are stages', solidsStages.length >= 3);
    final ids = solidsStages.map((s) => s.id).toList();
    _chk('stage ids are unique', ids.toSet().length == ids.length);
    _chk('no stage window is inside-out', solidsStages.every((s) => s.fromMonth <= s.toMonth));
    _chk('no stage starts before the start month', solidsStages.every((s) => s.fromMonth >= solidsStartMonth));
  }

  // ---- Stages by age ----
  {
    // At six months: first foods and the allergen note, not the family-food
    // stage.
    final m6 = stagesForMonth(6).map((s) => s.id).toSet();
    _chk('six months shows first foods', m6.contains('first_foods'));
    _chk('six months shows the allergen note', m6.contains('allergens'));
    _chk('six months does NOT show chopped family food yet', !m6.contains('family'));

    // At ten months: family food and allergens, not the very first purees.
    final m10 = stagesForMonth(10).map((s) => s.id).toSet();
    _chk('ten months shows family food', m10.contains('family'));
    _chk('ten months no longer shows first foods', !m10.contains('first_foods'));

    // Across the window every month resolves to at least one stage.
    var covered = true;
    for (var m = solidsStartMonth; m <= solidsToMonth; m++) {
      if (stagesForMonth(m).isEmpty) covered = false;
    }
    _chk('every month from start to window end has a stage', covered);
  }

  // ---- Window & countdown ----
  {
    _chk('a three-month-old is not yet in the window', !isSolidsWindow(3));
    _chk('a four-month-old is in the window', isSolidsWindow(4));
    _chk('a fourteen-month-old is at the window edge', isSolidsWindow(14));
    _chk('a fifteen-month-old is past it', !isSolidsWindow(15));

    _chk('at four months, two months until solids', monthsUntilSolids(4) == 2);
    _chk('at six months, no countdown — arrived', monthsUntilSolids(6) == null);
    _chk('past six months, still no countdown', monthsUntilSolids(9) == null);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
