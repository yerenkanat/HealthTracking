/// Pure-Dart verification of daily reminder scheduling across DST boundaries.
/// `dart run tool/verify_reminder_schedule.dart`
library;

import 'dart:io';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../lib/domain/reminder_schedule.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  tzdata.initializeTimeZones();
  final berlin = tz.getLocation('Europe/Berlin'); // observes DST
  final almaty = tz.getLocation('Asia/Almaty'); // has not since 2005

  tz.TZDateTime at(tz.Location l, int y, int m, int d, int h, int min) =>
      tz.TZDateTime(l, y, m, d, h, min);

  // ---- the ordinary day ----
  {
    final now = at(almaty, 2026, 7, 21, 8, 0);
    final next = nextDailyOccurrence(now, 9, 0);
    _chk('later today is today', next.day == 21 && next.hour == 9 && next.minute == 0);
  }
  {
    final now = at(almaty, 2026, 7, 21, 10, 0);
    final next = nextDailyOccurrence(now, 9, 0);
    _chk('a time already past rolls to tomorrow', next.day == 22 && next.hour == 9);
  }
  {
    // Exactly now counts as past: scheduling for this instant would fire
    // immediately, which is not what "daily at 9" means when it is 9.
    final now = at(almaty, 2026, 7, 21, 9, 0);
    _chk('the exact minute rolls forward', nextDailyOccurrence(now, 9, 0).day == 22);
  }

  // ---- spring forward: the day is 23 hours long ----
  //
  // Berlin goes 02:00 → 03:00 on 29 March 2026. Adding Duration(days: 1) to
  // 28 March 09:00 lands on 29 March at TEN — the reminder to take her folic
  // acid arrives an hour late, every spring, in every DST country.
  {
    final now = at(berlin, 2026, 3, 28, 10, 0); // 09:00 already passed
    final next = nextDailyOccurrence(now, 9, 0);
    _chk('spring forward: still 09:00 the next morning',
        next.month == 3 && next.day == 29 && next.hour == 9 && next.minute == 0);
    // Pin the defect itself, so this stays a demonstration and not a claim:
    // the old code took today at 09:00 and added an exact 24 hours.
    final naive = at(berlin, 2026, 3, 28, 9, 0).add(const Duration(days: 1));
    _chk('spring forward: the old arithmetic really did land on 10:00',
        naive.day == 29 && naive.hour == 10);
  }

  // ---- autumn back: the day is 25 hours long ----
  {
    final now = at(berlin, 2026, 10, 24, 10, 0);
    final next = nextDailyOccurrence(now, 9, 0);
    _chk('autumn back: still 09:00 the next morning',
        next.month == 10 && next.day == 25 && next.hour == 9);
  }

  // ---- a wall-clock time that does not exist ----
  {
    // 02:30 never happens on the morning the clocks skip an hour. It must
    // still produce a real instant rather than a null or a throw — an hour
    // late beats a reminder that silently never schedules.
    final now = at(berlin, 2026, 3, 28, 10, 0);
    final next = nextDailyOccurrence(now, 2, 30);
    _chk('a skipped wall-clock time still yields an instant',
        next.day == 29 && next.hour == 3 && next.minute == 30);
  }

  // ---- a wall-clock time that happens twice ----
  {
    final now = at(berlin, 2026, 10, 24, 10, 0);
    final next = nextDailyOccurrence(now, 2, 30);
    _chk('an ambiguous wall-clock time picks one and is real',
        next.day == 25 && next.hour == 2 && next.minute == 30);
  }

  // ---- date rollover ----
  {
    _chk('month end rolls to the first',
        nextDailyOccurrence(at(almaty, 2026, 1, 31, 23, 0), 9, 0).month == 2);
    _chk('year end rolls to January',
        nextDailyOccurrence(at(almaty, 2026, 12, 31, 23, 0), 9, 0).year == 2027);
    // 2028 is a leap year: 28 February is followed by the 29th, not by March.
    _chk('a leap day is not skipped',
        nextDailyOccurrence(at(almaty, 2028, 2, 28, 23, 0), 9, 0).day == 29);
  }

  // ---- the result is always in the future, in every zone ----
  {
    var ok = true;
    for (final loc in [berlin, almaty, tz.getLocation('America/Santiago')]) {
      for (var d = 1; d <= 28; d++) {
        for (final h in [0, 9, 23]) {
          final now = at(loc, 2026, 3, d, h, 0);
          if (!nextDailyOccurrence(now, 9, 0).isAfter(now)) ok = false;
        }
      }
    }
    _chk('never schedules into the past, across zones and days', ok);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
