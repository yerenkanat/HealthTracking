/// A picture of the Health & cycle screen, in both of its modes.
///
/// This screen has the densest surface mix in the app — the pregnancy hero, the
/// month grid, phase cards, stat rows — so it is where a half-applied design
/// system shows first: a card that kept a hairline edge, or a chip that never
/// got its outline, is invisible to a test that looks for text.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  Widget wrap(AppController c) => MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: L10nScope(
          l10n: const L10n(AppLocale.ru),
          child: WomensHealthScreen(controller: c, now: () => today),
        ),
      );

  Future<void> shoot(WidgetTester tester, AppController c, String name) async {
    tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();
    await expectLater(find.byType(WomensHealthScreen), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('golden: pregnancy mode', (tester) async {
    final c = AppController(now: () => today)..setDueDate(today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await shoot(tester, c, 'womens_health_pregnancy');
  });

  testWidgets('golden: cycle mode', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await shoot(tester, c, 'womens_health_cycle');
  });
}
