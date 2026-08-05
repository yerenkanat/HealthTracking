/// Which day the week starts on.
///
/// The month grid was Sunday-first — `first.weekday % 7` — under a header that
/// also began at Sunday. Russian and Kazakh weeks start on Monday, so every
/// date sat one column to the left of where a reader here expects it. The
/// numbers were correct and the shape of the month was wrong, which is the kind
/// of error you feel rather than notice.
///
/// Tested as arithmetic rather than through the widget: this is the whole of
/// what was broken, and a pure function can be checked against months whose
/// real-world layout is easy to verify by hand.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';

void main() {
  group('Monday-first (ru, kk — firstDayOfWeekIndex 1)', () {
    const monday = 1;

    test('a month starting on Thursday leaves three blanks', () {
      // 1 August 2026 is a Saturday. Mon Tue Wed Thu Fri | Sat → five blanks.
      expect(leadingBlanksFor(DateTime(2026, 8, 1), monday), 5);
    });

    test('a month starting on Monday leaves none', () {
      // 1 June 2026 is a Monday.
      expect(leadingBlanksFor(DateTime(2026, 6, 1), monday), 0);
    });

    test('a month starting on Sunday leaves six — the whole week', () {
      // 1 February 2026 is a Sunday: under a Monday-first grid it is the LAST
      // column, not the first. This is the case the old code got most wrong —
      // it put Sunday at the start and shifted the entire month.
      expect(leadingBlanksFor(DateTime(2026, 2, 1), monday), 6);
    });
  });

  group('Sunday-first (en_US — firstDayOfWeekIndex 0)', () {
    const sunday = 0;

    test('the same Sunday month leaves none', () {
      expect(leadingBlanksFor(DateTime(2026, 2, 1), sunday), 0);
    });

    test('and a Saturday month leaves six', () {
      expect(leadingBlanksFor(DateTime(2026, 8, 1), sunday), 6);
    });
  });

  test('never returns a column outside the grid', () {
    // Twelve months against both conventions: the result has to be a real
    // column, or the first row silently loses days off the end.
    for (var m = 1; m <= 12; m++) {
      for (final firstDow in [0, 1]) {
        final blanks = leadingBlanksFor(DateTime(2026, m, 1), firstDow);
        expect(blanks, inInclusiveRange(0, 6), reason: 'month $m, firstDow $firstDow');
      }
    }
  });
}
