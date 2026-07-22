/// Pure-Dart verification of the postpartum recovery domain.
/// `dart run tool/verify_postpartum.dart`
///
/// As with the vaccination schedule, most of this checks the DATA and the
/// windows: a wrong window here is a mother told that heavy bleeding at week
/// three is "fading and normal", or never shown the warning that would send her
/// to a clinic. The warning list in particular must never come back empty.
library;

import 'dart:io';
import '../lib/domain/postpartum.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The table is coherent ----
  {
    _chk('there are recovery notes', recoveryNotes.length >= 8);
    _chk('every note has a non-empty id', recoveryNotes.every((n) => n.id.trim().isNotEmpty));
    _chk('no window is inside-out', recoveryNotes.every((n) => n.fromDay <= n.toDay));
    _chk('no note starts before birth', recoveryNotes.every((n) => n.fromDay >= 0));

    final ids = recoveryNotes.map((n) => n.id).toList();
    _chk('note ids are unique', ids.toSet().length == ids.length);

    // Every area is represented — a recovery guide that never mentions mood
    // would miss the most under-recognised postpartum complication.
    for (final area in RecoveryArea.values) {
      _chk('the ${area.name} thread has at least one note',
          recoveryNotes.any((n) => n.area == area));
    }
  }

  // ---- Warning signs ----
  {
    _chk('the warning list is not empty', warningSigns.isNotEmpty);
    _chk('warning ids are unique', warningSigns.toSet().length == warningSigns.length);
    _chk('the emotional red flag is present', warningSigns.contains('harm'));
    _chk('haemorrhage is present', warningSigns.contains('bleeding'));
    _chk('infection (fever) is present', warningSigns.contains('fever'));
  }

  // ---- Days since birth ----
  {
    final birth = DateTime(2026, 6, 1);
    _chk('same day is day zero', daysSinceBirth(birth, DateTime(2026, 6, 1, 23)) == 0);
    _chk('a week later is seven', daysSinceBirth(birth, DateTime(2026, 6, 8)) == 7);
    _chk('a future birth never goes negative', daysSinceBirth(birth, DateTime(2026, 5, 20)) == 0);
    // Time of day must not tip a day over — it is a calendar count.
    _chk('crossing midnight, not 24h, marks a day',
        daysSinceBirth(DateTime(2026, 6, 1, 23), DateTime(2026, 6, 2, 1)) == 1);
  }

  // ---- Which notes are "now" ----
  {
    // Day 3: early lochia, rest, soreness, baby blues, hydrate — not the
    // week-two-onward notes.
    final d3 = notesNow(3).map((n) => n.id).toSet();
    _chk('day 3 shows early lochia', d3.contains('lochia_early'));
    _chk('day 3 shows the baby blues note', d3.contains('blues'));
    _chk('day 3 does NOT show the after-check clearance note', !d3.contains('clearance'));

    // Day 30: fading lochia and the ongoing threads, not the early ones.
    final d30 = notesNow(30).map((n) => n.id).toSet();
    _chk('day 30 shows fading lochia', d30.contains('lochia_fading'));
    _chk('day 30 no longer shows early lochia', !d30.contains('lochia_early'));

    // After the check: clearance and contraception, not the acute early notes.
    final d50 = notesNow(50).map((n) => n.id).toSet();
    _chk('after the check, clearance shows', d50.contains('clearance'));
    _chk('after the check, early soreness is gone', !d50.contains('soreness'));

    _chk('every day in the window has at least one note',
        List.generate(postpartumWindowDays + 1, (d) => notesNow(d).isNotEmpty).every((x) => x));
  }

  // ---- The postnatal check countdown ----
  {
    _chk('the check is at six weeks', postnatalCheckDay == 42);
    _chk('day 0 counts down to the check', daysUntilCheck(0) == 42);
    _chk('day 40 has two days left', daysUntilCheck(40) == 2);
    _chk('on the day itself there is nothing left to count', daysUntilCheck(42) == null);
    _chk('after it, no countdown to invent', daysUntilCheck(60) == null);
  }

  // ---- The window ----
  {
    _chk('birth day is in the window', isPostpartumWindow(0));
    _chk('four months is the edge of the window', isPostpartumWindow(postpartumWindowDays));
    _chk('beyond four months it is no longer shown', !isPostpartumWindow(postpartumWindowDays + 1));
    _chk('a negative day is not in the window', !isPostpartumWindow(-1));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
