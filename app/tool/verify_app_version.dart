/// Pure-Dart verification of the app-version gate logic.
/// `dart run tool/verify_app_version.dart`
///
/// The gate decides whether a build is blocked outright, so the edges matter: an
/// unset floor (0) must never block, an equal build must be allowed, and only a
/// strictly-older build is turned away.
library;

import 'dart:io';
import '../lib/domain/app_version.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // appUpdateRequired
  _chk('an unset floor (0) blocks nobody', !appUpdateRequired(1, 0));
  _chk('an equal build is allowed', !appUpdateRequired(5, 5));
  _chk('a newer build is allowed', !appUpdateRequired(6, 5));
  _chk('a strictly-older build is blocked', appUpdateRequired(4, 5));
  _chk('this build against an unset floor is allowed', !appUpdateRequired(currentAppBuild, 0));

  // appUpdateAvailable — a soft nudge, never a block
  _chk('a newer latest build is available', appUpdateAvailable(1, 2));
  _chk('an equal latest build is not "available"', !appUpdateAvailable(2, 2));
  _chk('an older latest build is not "available"', !appUpdateAvailable(3, 2));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
