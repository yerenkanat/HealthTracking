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

  // Weekly series + streak.
  final today = DateTime(2026, 7, 15);
  final log = <String, int>{
    '2026-07-15': 8, // today met
    '2026-07-14': 9, // met
    '2026-07-13': 8, // met
    '2026-07-12': 3, // missed
    '2026-07-11': 8, // met (but streak already broken above)
    '2026-07-09': 8, // gap on the 10th
  };
  final week = lastNDays(log, today, 7);
  _chk('7 days returned', week.length == 7);
  _chk('oldest-first', week.first.day == DateTime(2026, 7, 9) && week.last.day == DateTime(2026, 7, 15));
  _chk('missing day is 0', week[1].glasses == 0); // 2026-07-10
  _chk('today glasses', week.last.glasses == 8);

  _chk('streak counts back to first miss', waterStreak(log, today, 8) == 3); // 15,14,13
  _chk('streak zero goal safe', waterStreak(log, today, 0) == 0);

  // Today not yet met → streak counted from yesterday.
  final log2 = {'2026-07-15': 2, '2026-07-14': 8, '2026-07-13': 8};
  _chk('pending today counts from yesterday', waterStreak(log2, today, 8) == 2);
  // Empty log → no streak.
  _chk('empty → 0 streak', waterStreak(const {}, today, 8) == 0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
