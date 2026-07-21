/// Pure-Dart verification of pregnancy milestones (non-medical timeline markers).
/// `dart run tool/verify_milestones.dart`
library;

import 'dart:io';
import '../lib/domain/pregnancy_milestones.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('week 0 → first trimester', currentMilestone(0).code == 'MS_FIRST_TRIMESTER');
  _chk('week 12 → still first trimester', currentMilestone(12).code == 'MS_FIRST_TRIMESTER');
  _chk('week 13 → second trimester', currentMilestone(13).code == 'MS_SECOND_TRIMESTER');
  _chk('week 20 → halfway', currentMilestone(20).code == 'MS_HALFWAY');
  _chk('week 26 → still halfway bucket', currentMilestone(26).code == 'MS_HALFWAY');
  // Week 27 is still the SECOND trimester under both the NHS and ACOG; the
  // third begins at 28w0d. This fired a week early.
  _chk('week 27 → still second trimester', currentMilestone(27).code == 'MS_HALFWAY');
  _chk('week 28 → third trimester', currentMilestone(28).code == 'MS_THIRD_TRIMESTER');
  _chk('week 37 → full term', currentMilestone(37).code == 'MS_FULL_TERM');
  _chk('week 40 → due', currentMilestone(40).code == 'MS_DUE');
  _chk('week 42 → still due (clamped)', currentMilestone(42).code == 'MS_DUE');

  _chk('next after week 0 = second trimester in 13', nextMilestone(0)?.code == 'MS_SECOND_TRIMESTER' && weeksUntil(0, nextMilestone(0)!) == 13);
  // Eight weeks, not seven: the third trimester starts at 28, not 27.
  _chk('next after week 20 = third trimester in 8', nextMilestone(20)?.code == 'MS_THIRD_TRIMESTER' && weeksUntil(20, nextMilestone(20)!) == 8);
  _chk('next after week 37 = due in 3', nextMilestone(37)?.code == 'MS_DUE' && weeksUntil(37, nextMilestone(37)!) == 3);
  _chk('no next past week 40', nextMilestone(40) == null);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
