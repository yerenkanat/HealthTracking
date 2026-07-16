/// Widget tests for the Women's Health calendar — pregnancy (gestation) vs
/// cycle mode headers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  AppController controllerFor({DateTime? dueDate}) {
    final c = AppController(now: () => today);
    if (dueDate != null) c.setDueDate(dueDate);
    return c;
  }

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: WomensHealthScreen(controller: c, now: () => today),
        ),
      );

  testWidgets('pregnancy mode shows the gestation header', (tester) async {
    // Due in 140 days → 280-140 = 140 gestational days = week 20.
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(find.text('Week 20, Day 0'), findsOneWidget);
    expect(find.textContaining('days to go'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('cycle mode (no due date) invites tracking the cycle', (tester) async {
    final c = controllerFor(); // no due date → cycle mode
    await tester.pumpWidget(wrap(c));
    expect(find.text('Track your cycle'), findsOneWidget);
    expect(find.textContaining('Week 20'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('the "No longer pregnant?" action returns to cycle mode', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(c.isPregnant, true);

    await tester.tap(find.text('No longer pregnant?'));
    await tester.pumpAndSettle();
    // Confirm dialog → tap the neutral confirm ("Finish").
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(c.isPregnant, false);
    expect(find.text('Track your cycle'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
