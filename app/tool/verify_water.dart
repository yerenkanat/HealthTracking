/// Pure-Dart verification of the daily hydration helpers.
/// `dart run tool/verify_water.dart`
library;

import 'dart:io';
import '../lib/domain/hydration.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('zero count → 0.0', hydrationFraction(0, 8) == 0.0);
  _chk('half → 0.5', hydrationFraction(4, 8) == 0.5);
  _chk('exact goal → 1.0', hydrationFraction(8, 8) == 1.0);
  _chk('over goal clamps to 1.0', hydrationFraction(12, 8) == 1.0);
  _chk('zero goal → 0.0 (no divide-by-zero)', hydrationFraction(3, 0) == 0.0);
  _chk('negative count → 0.0', hydrationFraction(-2, 8) == 0.0);

  _chk('goal not met below', !hydrationGoalMet(7, 8));
  _chk('goal met at target', hydrationGoalMet(8, 8));
  _chk('goal met above', hydrationGoalMet(9, 8));
  _chk('goal never met when goal 0', !hydrationGoalMet(5, 0));

  _chk('clamp below min', clampWaterGoal(1) == minWaterGoal);
  _chk('clamp above max', clampWaterGoal(99) == maxWaterGoal);
  _chk('clamp in range unchanged', clampWaterGoal(10) == 10);
  _chk('default goal is 8', defaultWaterGoal == 8);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
