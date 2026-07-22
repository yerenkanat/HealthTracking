/// The safe-sleep screen — reduce-the-risk guidance.
///
/// The content is safety content: every rule must render, and the back-to-sleep
/// and bed-sharing messages in particular must never go missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/safe_sleep.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/safe_sleep_screen.dart';

Future<void> pump(WidgetTester tester, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(880, 2600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: const SafeSleepScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('leads with the one-line summary', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('ss_intro')), findsOneWidget);
  });

  testWidgets('shows both lists, split into do and avoid', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('ss_do_title').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('ss_avoid_title').toUpperCase()), findsOneWidget);
  });

  testWidgets('every rule renders, and the crucial two are present', (tester) async {
    await pump(tester);
    for (final r in safeSleepRules) {
      expect(find.text(ru.t('ss_${r.id}')), findsOneWidget, reason: r.id);
    }
    // Back-to-sleep and the bed-sharing caution are the messages that matter
    // most — assert them by name so a refactor can never quietly drop them.
    expect(find.text(ru.t('ss_back')), findsOneWidget);
    expect(find.text(ru.t('ss_bedshare')), findsOneWidget);
  });

  testWidgets('carries a not-medical-advice note', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('ss_disclaimer')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, loc);
      expect(find.textContaining('ss_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the safe-sleep guidance', (tester) async {
    await pump(tester);
    await expectLater(find.byType(SafeSleepScreen), matchesGoldenFile('goldens/safe_sleep.png'));
  });
}
