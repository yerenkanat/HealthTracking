/// The postpartum recovery screen.
///
/// Two halves that must both hold: the calm "what is normal now" notes that
/// change with the days, and the warning list that must ALWAYS be present and
/// complete — it is the part a mother's safety turns on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/postpartum.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';

final today = DateTime(2026, 7, 22);
DateTime birthDaysAgo(int days) => DateTime(2026, 7, 22 - days);

Future<void> pump(WidgetTester tester, int daysAgo, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: L10n(loc),
      child: PostpartumScreen(birthDate: birthDaysAgo(daysAgo), today: today),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('it always leads with the disclaimer', (tester) async {
    await pump(tester, 3);
    expect(find.text(ru.t('pp_disclaimer')), findsOneWidget);
  });

  testWidgets('early on, the baby-blues note is shown', (tester) async {
    await pump(tester, 3);
    expect(find.text(ru.t('pp_note_blues')), findsOneWidget);
    expect(find.text(ru.t('pp_note_lochia_early')), findsOneWidget);
    // The after-check clearance note is not relevant yet.
    expect(find.text(ru.t('pp_note_clearance')), findsNothing);
  });

  testWidgets('after the six-week check, the notes move on', (tester) async {
    await pump(tester, 50);
    expect(find.text(ru.t('pp_note_clearance')), findsOneWidget);
    // And the acute early notes are gone.
    expect(find.text(ru.t('pp_note_lochia_early')), findsNothing);
  });

  testWidgets('the check counts down, then says have it if you have not', (tester) async {
    await pump(tester, 0);
    expect(find.text(ru.t('pp_check_in', {'n': 42})), findsOneWidget);

    await pump(tester, 50); // past the check
    expect(find.text(ru.t('pp_check_past')), findsOneWidget);
  });

  testWidgets('the whole warning list is present, at every stage', (tester) async {
    // The warnings do not depend on the day — a haemorrhage at week six is as
    // urgent as at week one.
    for (final day in [1, 30, 90]) {
      await pump(tester, day);
      expect(find.text(ru.t('pp_warn_title')), findsOneWidget, reason: 'day $day');
      for (final id in warningSigns) {
        expect(find.text(ru.t('pp_warn_$id')), findsOneWidget, reason: 'pp_warn_$id at day $day');
      }
    }
  });

  testWidgets('the mental-health red flag is never omitted', (tester) async {
    await pump(tester, 10);
    expect(find.text(ru.t('pp_warn_harm')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 20, loc);
      expect(find.textContaining('pp_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the recovery screen in the first weeks', (tester) async {
    await pump(tester, 10);
    await expectLater(
      find.byType(PostpartumScreen),
      matchesGoldenFile('goldens/postpartum_early.png'),
    );
  });
}
