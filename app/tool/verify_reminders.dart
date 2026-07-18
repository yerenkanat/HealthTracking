/// Pure-Dart verification of the reminders-overview domain.
/// `dart run tool/verify_reminders.dart`
library;

import 'dart:io';
import '../lib/domain/reminders.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Active count ----
  _chk('none active → 0', activeReminderCount(period: false, fertile: false, water: false) == 0);
  _chk('all active → 3', activeReminderCount(period: true, fertile: true, water: true) == 3);
  _chk('two active → 2', activeReminderCount(period: true, fertile: false, water: true) == 2);

  // ---- minutesToHhmm ----
  _chk('midnight → 0:00', minutesToHhmm(0) == '0:00');
  _chk('08:05', minutesToHhmm(8 * 60 + 5) == '8:05');
  _chk('20:30', minutesToHhmm(20 * 60 + 30) == '20:30');
  _chk('23:59', minutesToHhmm(23 * 60 + 59) == '23:59');
  _chk('wraps past a day', minutesToHhmm(24 * 60 + 90) == '1:30');
  _chk('negative clamps to 0:00', minutesToHhmm(-5) == '0:00');

  _chk('enum has three kinds', ReminderKind.values.length == 3);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
