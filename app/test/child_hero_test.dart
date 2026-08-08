/// Screen 54's home block — «Есть ребёнок → возраст, навыки, перцентили».
///
/// The percentile half is where this differs from the mock on purpose.
/// domain/child_growth.dart refuses WHO bands because they need the published
/// LMS tables, and a band 300 g off tells a mother her healthy child is
/// underweight. The spec's own caption — «растёт по своему коридору» — is the
/// comparison the app CAN stand behind: her against herself.
///
/// So this file pins two things: the block exists and says her age and skills,
/// and it never states a percentile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/child_hero.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final today = DateTime(2026, 8, 8);

  Future<void> pump(WidgetTester tester, Widget child,
      {AppLocale locale = AppLocale.ru}) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(
        l10n: L10n(locale),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says whose block it is and how old she is', (tester) async {
    await pump(tester, const ChildHero(childName: 'Алия', ageMonths: 3));
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('childhero_age', {'name': 'Алия', 'n': 3})), findsOneWidget);
  });

  testWidgets('names what she is doing around now, in words', (tester) async {
    // «навыки в тексте» — named, not charted. A three-month-old has milestones
    // in the table, so the hero should be showing one rather than the fallback.
    await pump(tester, const ChildHero(childName: 'Алия', ageMonths: 3));
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('childhero_growing')), findsNothing,
        reason: 'fell back to the generic line while real milestones exist');
  });

  testWidgets('past the milestone table it does not invent a skill', (tester) async {
    // Over five there is nothing age-specific left to promise, and making one
    // up is a claim about a child the app has never met.
    await pump(tester, const ChildHero(childName: 'Алия', ageMonths: 200));
    const l = L10n(AppLocale.ru);
    expect(find.text(l.t('childhero_growing')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('growth — her own corridor, never a percentile', () {
    testWidgets('shows the latest weight and the change since last time',
        (tester) async {
      await pump(
        tester,
        ChildHero(
          childName: 'Алия',
          ageMonths: 3,
          growth: [
            GrowthPoint(at: today.subtract(const Duration(days: 30)), weightKg: 5.5),
            GrowthPoint(at: today, weightKg: 6.1),
          ],
        ),
      );
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('childhero_weight', {'kg': '6.1'})), findsOneWidget);
      // 600 g over 30 days — the number a parent leaves the polyclinic wanting.
      expect(find.text(l.t('childhero_gained', {'g': 600, 'd': 30})), findsOneWidget);
    });

    testWidgets('with one measurement it says the corridor, not a change',
        (tester) async {
      await pump(
        tester,
        ChildHero(
          childName: 'Алия',
          ageMonths: 3,
          growth: [GrowthPoint(at: today, weightKg: 6.1)],
        ),
      );
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('childhero_own_corridor')), findsOneWidget);
    });

    testWidgets('with no measurements it draws no growth card at all',
        (tester) async {
      // A card with a dash where the weight goes is worse than no card.
      await pump(tester, const ChildHero(childName: 'Алия', ageMonths: 3));
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('childhero_own_corridor')), findsNothing);
      expect(find.textContaining('кг'), findsNothing);
    });

    testWidgets('never states a percentile, in any language', (tester) async {
      // The rule this file exists for. A percentile here would need the WHO LMS
      // tables; without them it would be a medical claim from invented data.
      for (final locale in AppLocale.values) {
        await pump(
          tester,
          ChildHero(
            childName: 'Алия',
            ageMonths: 3,
            growth: [
              GrowthPoint(at: today.subtract(const Duration(days: 30)), weightKg: 5.5),
              GrowthPoint(at: today, weightKg: 6.1),
            ],
          ),
          locale: locale,
        );
        for (final banned in ['перцентил', 'percentile', 'процентил', '%']) {
          expect(find.textContaining(banned), findsNothing,
              reason: '${locale.name} states a percentile the app cannot compute');
        }
      }
    });
  });
}
