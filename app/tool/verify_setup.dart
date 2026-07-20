/// Pure-Dart verification of the setup checklist.
/// `dart run tool/verify_setup.dart`
library;

import 'dart:io';
import '../lib/domain/setup_checklist.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

SetupProgress p({
  bool name = false,
  bool health = false,
  bool child = false,
  bool zone = false,
  bool details = false,
  bool backup = false,
}) =>
    computeSetupProgress(
      hasName: name, hasHealthData: health, hasChild: child, hasZone: zone,
      hasDetails: details, hasBackup: backup,
    );

void main() {
  final none = p();
  _chk('nothing done → all remaining', none.done.isEmpty && none.remaining.length == SetupStep.values.length);
  _chk('nothing done → fraction 0', none.fraction == 0 && !none.complete);
  _chk('next is the first step', none.next == SetupStep.profileName);

  final all = p(name: true, health: true, child: true, zone: true, details: true, backup: true);
  _chk('everything done → complete', all.complete && all.remaining.isEmpty);
  _chk('complete → fraction 1', all.fraction == 1.0 && all.next == null);

  final some = p(name: true, health: true);
  _chk('partial done count', some.done.length == 2 && some.remaining.length == 4);
  // 2 of 6 steps done.
  _chk('partial fraction', (some.fraction - (2 / 6)).abs() < 1e-9);
  _chk('next skips completed steps', some.next == SetupStep.child);
  _chk('remaining keeps declaration order',
      some.remaining[0] == SetupStep.child && some.remaining[1] == SetupStep.zone &&
          some.remaining[2] == SetupStep.details && some.remaining[3] == SetupStep.backup);

  final gap = p(name: true, zone: true);
  _chk('out-of-order completion still ordered', gap.next == SetupStep.healthMode && gap.done.contains(SetupStep.zone));
  _chk('total is stable', gap.total == SetupStep.values.length);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
