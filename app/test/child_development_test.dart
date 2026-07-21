/// The development calendar, rendered.
///
/// The editorial risk here is not a crash — it is tone. A parent whose
/// 14-month-old is not walking must close this screen reassured, because 14
/// months is squarely ordinary. These tests assert the screen says so, and a
/// golden makes the result visible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/child_development.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_development_screen.dart';

final today = DateTime(2026, 7, 22);

ChildProfile childAged(int months, {String name = 'Сұлтан'}) => ChildProfile(
      id: 'c1',
      name: name,
      dateOfBirth: DateTime(today.year, today.month - months, today.day),
    );

Widget wrap(ChildProfile child, [AppLocale locale = AppLocale.ru]) => MaterialApp(
      home: L10nScope(
        l10n: L10n(locale),
        child: ChildDevelopmentScreen(child: child, today: today),
      ),
    );

/// Pump the screen on a surface tall enough to hold it.
///
/// The default test view is 800x600, and this screen is a lazy ListView — so
/// on a short surface the later sections are never BUILT, and `findsNothing`
/// passes for a section that renders perfectly well on a phone. Half these
/// tests would have been green for the wrong reason.
///
/// 2300 logical points, not 1300: eight cards in the 'now' section already
/// fill 1300, so the section header after them fell outside even the cache
/// extent and 'Скоро' genuinely was not in the tree.
Future<void> pumpScreen(WidgetTester tester, ChildProfile child,
    [AppLocale locale = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 4600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child, locale));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('a six-month-old sees what is happening now and what is next', (tester) async {
    await pumpScreen(tester, childAged(6));

    expect(find.text(ru.t('dev_now')), findsOneWidget);
    expect(find.text(ru.t('dev_next')), findsOneWidget);
    // First solids is a six-month event, and it should be on the "now" list.
    expect(find.text(ru.t('dev_first_solids')), findsOneWidget);
  });

  testWidgets('nothing is flagged for a newborn', (tester) async {
    await pumpScreen(tester, childAged(0));
    expect(find.text(ru.t('dev_ask')), findsNothing);
  });

  testWidgets('a 14-month-old who is not walking is NOT told walking is late', (tester) async {
    // The whole editorial point. Walking spans 9–15 months and the prompt to
    // ask a doctor does not arrive until 18, so at 14 months it belongs under
    // "right now" and nowhere near the doctor section.
    //
    // The first version of this asserted the doctor section was absent
    // ENTIRELY, which was wrong: other thresholds have genuinely passed by 14
    // months, and hiding those would defeat the section's purpose. The claim
    // is about walking, so the test is about walking.
    await pumpScreen(tester, childAged(14));

    final walking = devMilestones.firstWhere((m) => m.id == 'first_steps');
    expect(statusFor(walking, 14), DevStatus.now);
    expect(worthAsking(14).any((m) => m.id == 'first_steps'), isFalse);
    expect(find.text(ru.t('dev_first_steps')), findsOneWidget);
  });

  testWidgets('at 18 months it becomes a question for the doctor, worded as one', (tester) async {
    await pumpScreen(tester, childAged(18));

    expect(find.text(ru.t('dev_ask')), findsOneWidget);
    // And with the sentence that makes it a prompt rather than a finding.
    expect(find.text(ru.t('dev_ask_note')), findsOneWidget);
  });

  testWidgets('every card carries its range, not just a title', (tester) async {
    // "Первые шаги" alone reads as "this should have happened by now".
    // "9–15 мес." cannot be read that way.
    await pumpScreen(tester, childAged(12));
    expect(find.textContaining('–'), findsWidgets);
  });

  testWidgets('the spread disclaimer is always there, not only with bad news', (tester) async {
    for (final age in [0, 6, 20]) {
      await pumpScreen(tester, childAged(age));
      expect(find.text(ru.t('dev_spread')), findsOneWidget, reason: 'missing at $age months');
    }
  });

  testWidgets('without a date of birth it asks for one instead of guessing', (tester) async {
    await pumpScreen(tester, const ChildProfile(id: 'c1', name: 'Сұлтан'));
    expect(find.text(ru.t('dev_no_birthdate')), findsOneWidget);
  });

  testWidgets('renders in all three languages without falling back to a key', (tester) async {
    for (final loc in AppLocale.values) {
      await pumpScreen(tester, childAged(9), loc);
      // A missing string renders as the key itself, which starts with "dev_".
      expect(find.textContaining('dev_'), findsNothing, reason: 'raw key shown in ${loc.name}');
    }
  });

  testWidgets('golden: the calendar at nine months', (tester) async {
    tester.view.physicalSize = const Size(880, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester, childAged(9));

    await expectLater(
      find.byType(ChildDevelopmentScreen),
      matchesGoldenFile('goldens/child_development_9mo.png'),
    );
  });
}
