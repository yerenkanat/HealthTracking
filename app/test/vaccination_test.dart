/// The vaccination calendar screen.
///
/// The tone here is the opposite of the development calendar's, and on purpose:
/// these ages are set by the health ministry, so "пора" is the right word and a
/// passed date is worth catching up on. What must never appear is any claim
/// that the app knows which vaccinations were actually given.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/vaccination.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/vaccination_screen.dart';

final today = DateTime(2026, 7, 22);

ChildProfile childAged(int months) => ChildProfile(
      id: 'c1',
      name: 'Сұлтан',
      dateOfBirth: DateTime(today.year, today.month - months, today.day),
    );

Future<void> pump(WidgetTester tester, ChildProfile child,
    [AppLocale loc = AppLocale.ru]) async {
  // Tall: the full schedule is a long list, and a short surface would let a
  // lazy ListView skip the sections these tests are about.
  tester.view.physicalSize = const Size(880, 5200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: VaccinationScreen(child: child, today: today)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('a two-month-old has the two-month visit due', (tester) async {
    await pump(tester, childAged(2));
    expect(find.text(ru.t('vac_due')), findsOneWidget);
    expect(find.textContaining(ru.t('vac_pcv')), findsWidgets);
  });

  testWidgets('a newborn is told what the next visit brings, and when', (tester) async {
    await pump(tester, childAged(0));
    expect(find.textContaining(ru.t('vac_next')), findsOneWidget);
    // Three vaccines are given at two months; naming one would have a parent
    // arrive expecting one injection.
    expect(nextVisit(0).length, 3);
  });

  testWidgets('the whole schedule is browsable, not just what is due', (tester) async {
    await pump(tester, childAged(2));
    // The birth group and a late one both render, so a parent can look back
    // and ahead — the question they actually bring to a visit.
    expect(find.text(ru.t('vac_at_birth')), findsOneWidget);
    expect(find.text(ru.t('vac_at_month', {'n': 12})), findsOneWidget);
  });

  testWidgets('it never claims to know what was actually given', (tester) async {
    for (final age in [0, 4, 20]) {
      await pump(tester, childAged(age));
      expect(find.text(ru.t('vac_disclaimer')), findsOneWidget, reason: 'missing at $age months');
    }
  });

  testWidgets('the schedule says how old it is', (tester) async {
    // A schedule changes by ministry order. A build shipping a stale one
    // should be identifiable as stale rather than silently authoritative.
    await pump(tester, childAged(6));
    expect(find.text(ru.t('vac_revision', {'d': scheduleRevision})), findsOneWidget);
  });

  testWidgets('past the last vaccine it says so instead of inventing a next visit', (tester) async {
    await pump(tester, childAged(90));
    expect(find.text(ru.t('vac_complete')), findsOneWidget);
    expect(find.textContaining(ru.t('vac_next')), findsNothing);
  });

  testWidgets('without a date of birth it asks for one', (tester) async {
    await pump(tester, const ChildProfile(id: 'c1', name: 'Сұлтан'));
    expect(find.text(ru.t('dev_no_birthdate')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, childAged(4), loc);
      expect(find.textContaining('vac_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the calendar at four months', (tester) async {
    tester.view.physicalSize = const Size(880, 3400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: VaccinationScreen(child: childAged(4), today: today),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(VaccinationScreen),
      matchesGoldenFile('goldens/vaccination_4mo.png'),
    );
  });
}
