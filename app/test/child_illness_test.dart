/// The "when your child is unwell" screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/child_illness.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_illness_screen.dart';

Future<void> pump(WidgetTester tester, int ageMonths, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: ChildIllnessScreen(ageMonths: ageMonths)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows the comfort measures and the warning list', (tester) async {
    await pump(tester, 8);
    expect(find.text(ru.t('ill_care_title').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('ill_warn_title')), findsOneWidget);
    // The red flags that matter most, by name.
    expect(find.text(ru.t('ill_warn_breathing')), findsOneWidget);
    expect(find.text(ru.t('ill_warn_rash')), findsOneWidget);
    expect(find.text(ru.t('ill_warn_seizure')), findsOneWidget);
  });

  testWidgets('a baby under three months gets the urgent-fever banner', (tester) async {
    await pump(tester, 1);
    expect(find.text(ru.t('ill_young_title')), findsOneWidget);
    expect(find.text(ru.t('ill_young_body')), findsOneWidget);
  });

  testWidgets('an older baby does not get the age banner', (tester) async {
    await pump(tester, 8);
    expect(find.text(ru.t('ill_young_title')), findsNothing);
  });

  testWidgets('every warning renders, at any age', (tester) async {
    for (final age in [0, 5, 24]) {
      await pump(tester, age);
      for (final id in illnessWarnings) {
        expect(find.text(ru.t('ill_warn_$id')), findsOneWidget, reason: 'ill_warn_$id at $age mo');
      }
    }
  });

  testWidgets('carries a not-medical-advice note', (tester) async {
    await pump(tester, 8);
    expect(find.text(ru.t('ill_disclaimer')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 1, loc); // age 1 so the young banner renders too
      expect(find.textContaining('ill_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the illness guide for a young baby', (tester) async {
    await pump(tester, 1);
    await expectLater(find.byType(ChildIllnessScreen), matchesGoldenFile('goldens/child_illness.png'));
  });
}
