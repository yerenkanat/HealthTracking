/// Pure-Dart verification of the child development calendar.
/// `dart run tool/verify_child_development.dart`
///
/// Most of this checks the TABLE rather than the code around it. The functions
/// are a few lines each; the data is where a mistake would quietly tell a
/// mother her healthy child is late.
library;

import 'dart:io';
import '../lib/domain/child_development.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The table is internally coherent ----
  {
    _chk('there is a table to check', devMilestones.length > 20);

    final ids = devMilestones.map((m) => m.id).toList();
    _chk('every id is unique', ids.toSet().length == ids.length);
    _chk('no id is empty', ids.every((i) => i.trim().isNotEmpty));

    var ordered = true, positive = true, askLate = true;
    for (final m in devMilestones) {
      if (m.typicalTo < m.typicalFrom) ordered = false;
      if (m.typicalFrom < 0) positive = false;
      // "Worth asking" must sit at or beyond the end of the typical window.
      // An askBy inside the window would flag a child while they are still
      // squarely in the ordinary range — the exact alarm this table exists to
      // avoid.
      final ask = m.askByMonth;
      if (ask != null && ask <= m.typicalTo) askLate = false;
    }
    _chk('no range ends before it starts', ordered);
    _chk('no negative ages', positive);
    _chk('every "ask a doctor" age is past the typical window', askLate);

    // Every area is represented, or the grouped view has an empty column.
    final areas = devMilestones.map((m) => m.area).toSet();
    _chk('every area has at least one milestone', areas.length == DevArea.values.length);
  }

  // ---- Ranges, not points ----
  {
    // The spread between healthy children is the whole reason this is a range.
    // A table of point events would be a schedule, and a schedule is something
    // a child can be "behind".
    final spans = devMilestones.map((m) => m.typicalTo - m.typicalFrom).toList();
    final wide = spans.where((s) => s >= 2).length;
    _chk('most milestones span several months', wide > devMilestones.length * 0.7);
    _chk('walking spans the real range',
        devMilestones.firstWhere((m) => m.id == 'first_steps').typicalFrom <= 9 &&
            devMilestones.firstWhere((m) => m.id == 'first_steps').typicalTo >= 15);
  }

  // ---- statusFor ----
  {
    final walk = devMilestones.firstWhere((m) => m.id == 'first_steps'); // 9–15, ask 18
    _chk('before the window: ahead', statusFor(walk, 6) == DevStatus.ahead);
    _chk('at the opening edge: now', statusFor(walk, 9) == DevStatus.now);
    _chk('mid window: now', statusFor(walk, 12) == DevStatus.now);
    _chk('at the closing edge: now', statusFor(walk, 15) == DevStatus.now);
    // A 16-month-old who is not walking yet is ORDINARY. This is the assertion
    // that keeps the app from telling her otherwise.
    _chk('just past the window is passed, not a concern', statusFor(walk, 16) == DevStatus.passed);
    _chk('at the ask age it becomes worth asking', statusFor(walk, 18) == DevStatus.worthAsking);
    _chk('and stays so afterwards', statusFor(walk, 24) == DevStatus.worthAsking);
  }
  {
    // With no threshold, it can never become "worth asking" — a first tooth at
    // 15 months is not a problem, and the table must never imply it is.
    final tooth = devMilestones.firstWhere((m) => m.id == 'first_tooth');
    _chk('a milestone with no threshold has none', tooth.askByMonth == null);
    _chk('and never escalates', statusFor(tooth, 36) == DevStatus.passed);
  }

  // ---- The three views the screen uses ----
  {
    final now = milestonesNow(6);
    _chk('at six months something is happening', now.isNotEmpty);
    _chk('and everything listed really is in its window',
        now.every((m) => 6 >= m.typicalFrom && 6 <= m.typicalTo));

    final ahead = milestonesAhead(6, limit: 3);
    _chk('what is next is genuinely next', ahead.every((m) => m.typicalFrom > 6));
    _chk('and is capped', ahead.length <= 3);
    _chk('soonest first',
        ahead.length < 2 || ahead[0].typicalFrom <= ahead[1].typicalFrom);

    _chk('a newborn has nothing overdue', worthAsking(0).isEmpty);
    _chk('and nothing is flagged before its threshold',
        worthAsking(11).every((m) => (m.askByMonth ?? 999) <= 11));

    // Bounded to what was crossed RECENTLY.
    //
    // Unwindowed, an 18-month-old's list was nineteen items long and opened
    // with "lifts their head" — handed to the parent of a walking, talking
    // toddler. The app does not know what the child has actually done, so a
    // list that long is not information, it is alarm.
    final at18 = worthAsking(18);
    _chk('the list at 18 months is a conversation, not a page',
        at18.length <= worthAskingMax);
    _chk('at no age does it become a page',
        List.generate(40, (i) => worthAsking(i).length).every((n) => n <= worthAskingMax));
    _chk('most recently crossed first — the question likeliest to still stand',
        at18.length < 2 || at18[0].askByMonth! >= at18[1].askByMonth!);
    _chk('and holds nothing from early infancy',
        at18.every((m) => 18 - m.askByMonth! <= worthAskingWindowMonths));
    _chk('specifically, head control is not raised with a toddler',
        !at18.any((m) => m.id == 'lifts_head'));
    _chk('while something recent still surfaces', at18.isNotEmpty);
  }
  {
    // A child at the very start and one well past the table must both render.
    _chk('a newborn gets a "now" list', milestonesNow(0).isNotEmpty || milestonesAhead(0).isNotEmpty);
    _chk('a four-year-old does not crash the views',
        milestonesNow(48).isEmpty && milestonesAhead(48).isEmpty);
  }

  // ---- Age in whole months ----
  {
    _chk('the day before a birthday is still the month before',
        ageInMonths(DateTime(2026, 1, 15), DateTime(2026, 2, 14)) == 0);
    _chk('the birthday itself turns the month',
        ageInMonths(DateTime(2026, 1, 15), DateTime(2026, 2, 15)) == 1);
    _chk('a year is twelve months',
        ageInMonths(DateTime(2025, 7, 22), DateTime(2026, 7, 22)) == 12);
    _chk('across a year boundary',
        ageInMonths(DateTime(2025, 11, 30), DateTime(2026, 2, 28)) == 2);
    _chk('a date before birth is not a negative age',
        ageInMonths(DateTime(2026, 7, 22), DateTime(2026, 1, 1)) == 0);
  }

  // ---- Grouping ----
  {
    final grouped = byArea();
    _chk('grouping loses nothing',
        grouped.values.fold<int>(0, (n, l) => n + l.length) == devMilestones.length);
    _chk('each group is in order',
        grouped.values.every((l) {
          for (var i = 1; i < l.length; i++) {
            if (l[i].typicalFrom < l[i - 1].typicalFrom) return false;
          }
          return true;
        }));
    _chk('teeth are their own thread', (grouped[DevArea.teeth] ?? []).length >= 3);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
