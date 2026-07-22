/// The starting-solids screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/solids_screen.dart';

Future<void> pump(WidgetTester tester, int ageMonths, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: SolidsScreen(ageMonths: ageMonths)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows when to begin and the readiness signs', (tester) async {
    await pump(tester, 6);
    expect(find.text(ru.t('sol_when_title')), findsOneWidget);
    expect(find.text(ru.t('sol_ready_sits')), findsOneWidget);
  });

  testWidgets('at six months, first foods and the allergen note are offered', (tester) async {
    await pump(tester, 6);
    expect(find.text(ru.t('sol_stage_first_foods')), findsOneWidget);
    expect(find.text(ru.t('sol_stage_allergens')), findsOneWidget);
    // Not the family-food stage yet.
    expect(find.text(ru.t('sol_stage_family')), findsNothing);
  });

  testWidgets('before the start age there is no "offer now" list, but the guidance is there', (tester) async {
    await pump(tester, 4);
    expect(find.text(ru.t('sol_stage_title').toUpperCase()), findsNothing);
    // Readiness and the safety list still show.
    expect(find.text(ru.t('sol_ready_sits')), findsOneWidget);
    expect(find.text(ru.t('sol_avoid_honey')), findsOneWidget);
  });

  testWidgets('the safety avoid-list is always present, honey and choking by name', (tester) async {
    for (final m in [5, 8, 13]) {
      await pump(tester, m);
      expect(find.text(ru.t('sol_avoid_honey')), findsOneWidget, reason: 'month $m');
      expect(find.text(ru.t('sol_avoid_choking')), findsOneWidget, reason: 'month $m');
    }
  });

  testWidgets('carries a not-medical-advice note', (tester) async {
    await pump(tester, 8);
    expect(find.text(ru.t('sol_disclaimer')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 8, loc);
      expect(find.textContaining('sol_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the solids guide at eight months', (tester) async {
    await pump(tester, 8);
    await expectLater(find.byType(SolidsScreen), matchesGoldenFile('goldens/solids_8mo.png'));
  });
}
