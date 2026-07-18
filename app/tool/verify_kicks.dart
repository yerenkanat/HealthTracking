/// Pure-Dart verification of the timed fetal-movement session model.
/// `dart run tool/verify_kicks.dart`
library;

import 'dart:io';
import '../lib/domain/kick_session.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final t0 = DateTime(2026, 7, 15, 9, 0, 0);

  const empty = KickSession();
  _chk('starts at zero, not started', empty.count == 0 && !empty.started);
  _chk('elapsed is zero before first tap', empty.elapsed(t0.add(const Duration(minutes: 5))) == Duration.zero);

  final s1 = empty.tap(t0);
  _chk('first tap → count 1, started', s1.count == 1 && s1.started);
  _chk('first tap stamps startedAt', s1.startedAt == t0);

  final s2 = s1.tap(t0.add(const Duration(seconds: 30)));
  _chk('second tap → count 2', s2.count == 2);
  _chk('startedAt unchanged by later taps', s2.startedAt == t0);
  _chk('elapsed measured from first tap', s2.elapsed(t0.add(const Duration(minutes: 2))) == const Duration(minutes: 2));

  final u1 = s2.undo();
  _chk('undo decrements', u1.count == 1 && u1.started);
  final u0 = u1.undo();
  _chk('undo to zero clears the clock', u0.count == 0 && !u0.started);
  _chk('undo below zero is a no-op', u0.undo().count == 0);

  _chk("format 0:00", formatElapsed(Duration.zero) == '0:00');
  _chk("format 0:05", formatElapsed(const Duration(seconds: 5)) == '0:05');
  _chk("format 2:07", formatElapsed(const Duration(minutes: 2, seconds: 7)) == '2:07');
  _chk("format 12:00", formatElapsed(const Duration(minutes: 12)) == '12:00');
  _chk("format 1:05:09 past an hour", formatElapsed(const Duration(hours: 1, minutes: 5, seconds: 9)) == '1:05:09');
  _chk("negative clamps to 0:00", formatElapsed(const Duration(seconds: -3)) == '0:00');

  // Goal progress.
  _chk('default goal is 10', defaultKickGoal == 10);
  _chk('0 → 0.0', kickGoalFraction(0, 10) == 0.0);
  _chk('5/10 → 0.5', kickGoalFraction(5, 10) == 0.5);
  _chk('10/10 → 1.0', kickGoalFraction(10, 10) == 1.0);
  _chk('over goal clamps to 1.0', kickGoalFraction(14, 10) == 1.0);
  _chk('zero goal safe', kickGoalFraction(3, 0) == 0.0);
  _chk('goal not reached at 9', !kickGoalReached(9, 10));
  _chk('goal reached at 10', kickGoalReached(10, 10));
  _chk('goal reached above', kickGoalReached(12, 10));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
