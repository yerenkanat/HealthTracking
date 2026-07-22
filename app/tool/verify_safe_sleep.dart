/// Pure-Dart verification of the safe-sleep guidance.
/// `dart run tool/verify_safe_sleep.dart`
library;

import 'dart:io';
import '../lib/domain/safe_sleep.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('there are rules', safeSleepRules.length >= 6);
  _chk('every rule has a non-empty id', safeSleepRules.every((r) => r.id.trim().isNotEmpty));

  final ids = safeSleepRules.map((r) => r.id).toList();
  _chk('rule ids are unique', ids.toSet().length == ids.length);

  // The three that matter most must be present — this is the whole point.
  _chk('back-to-sleep is present', ids.contains('back'));
  _chk('own-bed (room-share, not bed-share) is present', ids.contains('own_bed'));
  _chk('a clear cot is present', ids.contains('clear'));
  _chk('the bed-sharing caution is present', ids.contains('bedshare'));

  // Both lists are non-empty, and together they account for every rule.
  _chk('there are things to do', sleepDos.isNotEmpty);
  _chk('there are things to avoid', sleepAvoids.isNotEmpty);
  _chk('the two lists partition the rules',
      sleepDos.length + sleepAvoids.length == safeSleepRules.length);
  _chk('back-to-sleep is a DO, not an avoid',
      sleepDos.any((r) => r.id == 'back') && !sleepAvoids.any((r) => r.id == 'back'));
  _chk('bed-sharing is an AVOID, not a do',
      sleepAvoids.any((r) => r.id == 'bedshare') && !sleepDos.any((r) => r.id == 'bedshare'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
