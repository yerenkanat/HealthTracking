/// The signs-of-labour screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/labour_signs.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';

Future<void> pump(WidgetTester tester, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: const LabourSignsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows both lists', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('lab_signs_title').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('lab_go_title')), findsOneWidget);
  });

  testWidgets('every sign and go-in reason renders', (tester) async {
    await pump(tester);
    for (final id in labourSigns) {
      expect(find.text(ru.t('lab_sign_$id')), findsOneWidget, reason: id);
    }
    for (final id in labourGoIn) {
      expect(find.text(ru.t('lab_go_$id')), findsOneWidget, reason: id);
    }
  });

  testWidgets('the 5-1-1 pattern and the when-in-doubt call are present by name', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('lab_go_five_one_one')), findsOneWidget);
    expect(find.text(ru.t('lab_go_unsure')), findsOneWidget);
  });

  testWidgets('carries a not-medical-advice note', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('lab_disclaimer')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, loc);
      expect(find.textContaining('lab_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the signs-of-labour guide', (tester) async {
    await pump(tester);
    await expectLater(find.byType(LabourSignsScreen), matchesGoldenFile('goldens/labour_signs.png'));
  });
}
