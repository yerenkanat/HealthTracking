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

  // showUpdateNudge — the policy the shell strip reads.
  final now = DateTime.utc(2026, 8, 18, 9);
  bool nudge({
    int current = 4,
    int min = 0,
    int latest = 5,
    int dismissedBuild = 0,
    DateTime? dismissedAt,
    DateTime? at,
  }) =>
      showUpdateNudge(
        currentBuild: current,
        minBuild: min,
        latestBuild: latest,
        dismissedBuild: dismissedBuild,
        dismissedAt: dismissedAt,
        now: at ?? now,
      );

  _chk('an older build with a newer one published is nudged', nudge());
  _chk('an up-to-date build is not nudged', !nudge(current: 5, latest: 5));
  _chk('a build ahead of the server is not nudged', !nudge(current: 6, latest: 5));
  _chk('a server that has said nothing yet (latest 0) nudges nobody',
      !nudge(current: 4, latest: 0));
  _chk('the hard block wins — a blocked build is never also nudged',
      !nudge(current: 4, min: 5, latest: 5));
  _chk('at the floor but below latest, the nudge is exactly what she gets',
      nudge(current: 5, min: 5, latest: 6));
  _chk('dismissed just now, it stays quiet',
      !nudge(dismissedBuild: 5, dismissedAt: now));
  _chk('still quiet a day short of the snooze',
      !nudge(dismissedBuild: 5, dismissedAt: now.subtract(const Duration(days: 6, hours: 23))));
  _chk('it comes back once the snooze has elapsed',
      nudge(dismissedBuild: 5, dismissedAt: now.subtract(updateNudgeSnooze)));
  _chk('a NEWER release than the one she snoozed asks again immediately',
      nudge(latest: 6, dismissedBuild: 5, dismissedAt: now));
  _chk('an unset dismissal (never closed) nudges',
      nudge(dismissedBuild: 0, dismissedAt: null));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
