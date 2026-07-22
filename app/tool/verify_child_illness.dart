/// Pure-Dart verification of the child-illness guidance.
/// `dart run tool/verify_child_illness.dart`
library;

import 'dart:io';
import '../lib/domain/child_illness.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  {
    _chk('there are comfort measures', illnessCare.length >= 3);
    _chk('care ids are unique', illnessCare.toSet().length == illnessCare.length);

    _chk('the warning list is not empty', illnessWarnings.isNotEmpty);
    _chk('warning ids are unique', illnessWarnings.toSet().length == illnessWarnings.length);

    // The ones that matter most must be present.
    _chk('breathing trouble is a red flag', illnessWarnings.contains('breathing'));
    _chk('the non-fading rash is a red flag', illnessWarnings.contains('rash'));
    _chk('a seizure is a red flag', illnessWarnings.contains('seizure'));
    _chk('being unrousable is a red flag', illnessWarnings.contains('unrousable'));
    _chk('dehydration is a red flag', illnessWarnings.contains('dehydration'));
  }

  // ---- The age rule ----
  {
    _chk('the urgent-fever age is three months', feverUrgentUnderMonths == 3);
    _chk('a newborn fever is urgent on age', feverIsUrgentForAge(0));
    _chk('a two-month-old fever is urgent on age', feverIsUrgentForAge(2));
    _chk('at exactly three months the age rule no longer forces urgent', !feverIsUrgentForAge(3));
    _chk('an older baby is not urgent on age alone', !feverIsUrgentForAge(9));
    _chk('the fever reference is a sane temperature', feverThresholdC >= 37 && feverThresholdC <= 39);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
