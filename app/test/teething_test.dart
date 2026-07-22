/// The teething screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/teething.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/teething_screen.dart';

Future<void> pump(WidgetTester tester, int ageMonths, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: TeethingScreen(ageMonths: ageMonths)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows the timeline, signs, soothing and the not-teething caution', (tester) async {
    await pump(tester, 7);
    expect(find.text(ru.t('teeth_timeline_title').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('teeth_lower_central')), findsOneWidget);
    expect(find.text(ru.t('teeth_soothe_title').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('teeth_not_title')), findsOneWidget);
  });

  testWidgets('the not-teething caution names a high fever', (tester) async {
    await pump(tester, 7);
    expect(find.text(ru.t('teeth_not_high_fever')), findsOneWidget);
  });

  testWidgets('every timeline group renders its age range', (tester) async {
    await pump(tester, 7);
    for (final g in teethingTimeline) {
      expect(find.text(ru.t('teeth_${g.id}')), findsOneWidget, reason: g.id);
      expect(find.text(ru.t('teeth_age_range', {'from': g.fromMonth, 'to': g.toMonth})), findsWidgets, reason: g.id);
    }
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 12, loc);
      expect(find.textContaining('teeth_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the teething guide for a seven-month-old', (tester) async {
    await pump(tester, 7);
    await expectLater(find.byType(TeethingScreen), matchesGoldenFile('goldens/teething.png'));
  });
}
