/// The growth screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_growth_screen.dart';

Future<void> pump(WidgetTester tester, List<GrowthPoint> points,
    [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: L10n(loc),
      child: ChildGrowthScreen(childName: 'Сұлтан', points: points, onAdd: () {}, onDelete: (_) {}),
    ),
  ));
  await tester.pumpAndSettle();
}

final visits = [
  GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6, heightCm: 51),
  GrowthPoint(at: DateTime(2026, 2, 10), weightKg: 4.6, heightCm: 55),
  GrowthPoint(at: DateTime(2026, 3, 10), weightKg: 5.4, heightCm: 58),
];

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('with no measurements it explains what to record', (tester) async {
    await pump(tester, const []);
    expect(find.text(ru.t('grw_empty')), findsOneWidget);
  });

  testWidgets('shows the latest weight and height with the change since last time',
      (tester) async {
    await pump(tester, visits);
    expect(find.textContaining('5.4'), findsWidgets);
    expect(find.textContaining('58.0'), findsWidgets);
    expect(find.textContaining('+0.8'), findsOneWidget); // 5.4 − 4.6
  });

  testWidgets('a first measurement says so instead of claiming no growth', (tester) async {
    await pump(tester, [GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6)]);
    expect(find.text(ru.t('grw_first')), findsWidgets);
    expect(find.textContaining('+0.0'), findsNothing);
  });

  testWidgets('a loss is shown as a loss', (tester) async {
    // Babies lose weight in the first days and after illness. Hiding it would
    // make the one figure a parent came to check the one the app will not show.
    await pump(tester, [
      GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6),
      GrowthPoint(at: DateTime(2026, 1, 17), weightKg: 3.3),
    ]);
    expect(find.textContaining('−0.3'), findsOneWidget);
  });

  testWidgets('it says plainly that there are no percentile bands', (tester) async {
    // The app is not comparing her child to anyone, and must not be read as
    // doing so — in either direction.
    await pump(tester, visits);
    expect(find.text(ru.t('grw_no_percentiles')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, visits, loc);
      expect(find.textContaining('grw_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: three visits', (tester) async {
    await pump(tester, visits);
    await expectLater(
      find.byType(ChildGrowthScreen),
      matchesGoldenFile('goldens/child_growth.png'),
    );
  });
}
