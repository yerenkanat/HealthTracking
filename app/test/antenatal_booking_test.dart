/// The antenatal plan screen can turn a protocol visit into a real appointment:
/// the "Add to my appointments" button appears only with a due date + callback,
/// and books the visit on the day its window opens.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/antenatal_protocol.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: L10nScope(l10n: const L10n(AppLocale.en), child: child));

void main() {
  const en = L10n(AppLocale.en);

  testWidgets('no booking button without a due date / callback', (tester) async {
    await tester.pumpWidget(_wrap(const AntenatalPlanScreen(week: 27)));
    await tester.pumpAndSettle();
    expect(find.text(en.t('an_book_cta')), findsNothing);
  });

  testWidgets('books the lead visit on the day its window opens', (tester) async {
    final due = DateTime(2026, 12, 31);
    AntenatalVisit? bookedVisit;
    DateTime? bookedAt;

    await tester.pumpWidget(_wrap(AntenatalPlanScreen(
      week: 27, // visit 3 (26–28) is due now → the lead card
      dueDate: due,
      onBook: (v, at) {
        bookedVisit = v;
        bookedAt = at;
      },
    )));
    await tester.pumpAndSettle();

    // The lead card carries the CTA.
    expect(find.text(en.t('an_book_cta')), findsWidgets);
    final cta = find.widgetWithText(OutlinedButton, en.t('an_book_cta')).first;
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(bookedVisit?.number, 3);
    // Visit 3 opens at week 26 → 14 weeks before the due date, at 10:00.
    final expectedDay = due.subtract(const Duration(days: 14 * 7));
    expect(bookedAt, DateTime(expectedDay.year, expectedDay.month, expectedDay.day, 10, 0));
    // And it confirms with a snackbar.
    expect(find.text(en.t('an_booked')), findsOneWidget);
  });
}
