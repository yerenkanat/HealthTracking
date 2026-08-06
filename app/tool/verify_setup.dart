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
  bool signedIn = false,
  bool name = false,
  bool health = false,
  bool child = false,
  bool zone = false,
  bool details = false,
  bool backup = false,
}) =>
    computeSetupProgress(
      signedIn: signedIn, hasName: name, hasHealthData: health, hasChild: child, hasZone: zone,
      hasDetails: details, hasBackup: backup,
    );

void main() {
  // This runner did not compile at all: the checklist gained a sign-in step
  // and nothing here was updated, so `dart run tool/verify_all.dart` reported
  // it as a problem runner on every build and the checklist went unverified.
  final none = p();
  _chk('nothing done → all remaining', none.done.isEmpty && none.remaining.length == SetupStep.values.length);
  _chk('nothing done → fraction 0', none.fraction == 0 && !none.complete);

  // Signing in is first on purpose, and stays first: until she has, every
  // other step writes to one handset only. Nudging her to add a child before
  // that is nudging her to lose it.
  _chk('next is signing in', none.next == SetupStep.signIn);
  _chk('sign-in leads the list', SetupStep.values.first == SetupStep.signIn);

  final all = p(signedIn: true, name: true, health: true, child: true, zone: true,
      details: true, backup: true);
  _chk('everything done → complete', all.complete && all.remaining.isEmpty);
  _chk('complete → fraction 1', all.fraction == 1.0 && all.next == null);

  final some = p(signedIn: true, name: true, health: true);
  _chk('partial done count', some.done.length == 3 && some.remaining.length == 4);
  _chk('partial fraction', (some.fraction - (3 / 7)).abs() < 1e-9);
  _chk('next skips completed steps', some.next == SetupStep.child);
  _chk('remaining keeps declaration order',
      some.remaining[0] == SetupStep.child && some.remaining[1] == SetupStep.zone &&
          some.remaining[2] == SetupStep.details && some.remaining[3] == SetupStep.backup);

  // Signed in but nothing else: the one that used to be unreachable.
  final fresh = p(signedIn: true);
  _chk('after signing in the nudge moves on', fresh.next == SetupStep.profileName);

  final gap = p(signedIn: true, name: true, zone: true);
  _chk('out-of-order completion still ordered', gap.next == SetupStep.healthMode && gap.done.contains(SetupStep.zone));
  _chk('total is stable', gap.total == SetupStep.values.length);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
