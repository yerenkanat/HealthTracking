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

  // ---- History summary ----
  final t = DateTime(2026, 7, 15, 10);
  final recs = [
    KickSessionRecord(endedAt: t, count: 12, durationSec: 600), // reached
    KickSessionRecord(endedAt: t, count: 8, durationSec: 900), // not reached
    KickSessionRecord(endedAt: t, count: 10, durationSec: 300), // reached
  ];
  final sum = kickHistorySummary(recs);
  _chk('summary sessions = 3', sum.sessions == 3);
  _chk('summary avg count = 10', sum.avgCount == 10.0);
  _chk('summary avg duration = 600s', sum.avgDuration == const Duration(seconds: 600));
  _chk('summary goal reached = 2', sum.goalReached == 2);
  final emptySum = kickHistorySummary(const <KickSessionRecord>[]);
  _chk('empty summary zeroed', emptySum.sessions == 0 && emptySum.avgCount == 0 && emptySum.goalReached == 0);

  // ---- Ten movements over three hours is not a celebration ----
  //
  // The goal was judged on count alone, so ten movements felt over three hours
  // showed the same "Goal reached 🎉" as ten in twenty minutes — confetti at
  // the exact moment the count-to-ten method exists to notice. Taking much
  // longer than usual to feel ten movements is the thing a mother is asked to
  // report.
  _chk('ten movements in twenty minutes is a goal reached',
      kickGoalReachedPromptly(10, const Duration(minutes: 20)));
  _chk('ten in just under two hours still is',
      kickGoalReachedPromptly(10, const Duration(minutes: 119)));
  _chk('ten over three hours is NOT celebrated',
      !kickGoalReachedPromptly(10, const Duration(hours: 3)));
  _chk('right on the two-hour reference is still counted',
      kickGoalReachedPromptly(10, kickReferenceWindow));
  _chk('a minute past it is not',
      !kickGoalReachedPromptly(10, kickReferenceWindow + const Duration(minutes: 1)));

  // The goal itself is unchanged — she DID record ten movements, and the
  // history must still say so. Only the celebration is withheld.
  _chk('a slow session still counts as reaching the goal',
      kickGoalReached(10, defaultKickGoal));
  _chk('an incomplete session is neither',
      !kickGoalReached(9, defaultKickGoal) &&
          !kickGoalReachedPromptly(9, const Duration(minutes: 10)));

  // A session that has not started cannot have reached anything.
  _chk('zero movements is never a goal',
      !kickGoalReachedPromptly(0, Duration.zero));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
