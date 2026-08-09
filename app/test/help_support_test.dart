/// Screen 43 — the help & support screen: FAQ, self-service, contact, share.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/help_support_screen.dart';

Future<void> pump(WidgetTester tester, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: const HelpSupportScreen(diagnostics: 'locale ru')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('shows FAQ, the contact row and the emergency reminder', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('help_q1_q')), findsOneWidget);
    // The contact row is WhatsApp now. It used to be a mailto to
    // support@umay.app — a placeholder on the retired brand — so every message
    // sent from this screen went to an address nobody owns.
    expect(find.text(ru.t('sup_write')), findsOneWidget);
    expect(find.text(ru.t('help_share')), findsOneWidget);
    expect(find.text(ru.t('help_emergency_note')), findsOneWidget);
  });

  testWidgets('says the contact row is unavailable rather than doing nothing',
      (tester) async {
    // With no number configured the row must not look live.
    await pump(tester);
    expect(find.text(ru.t('sup_unavailable')), findsOneWidget);
  });

  testWidgets('offers no self-service action this build cannot perform',
      (tester) async {
    // A dead row teaches her that none of them work.
    await pump(tester);
    expect(find.text(ru.t('sup_act_refresh')), findsNothing);
  });

  testWidgets('an FAQ answer expands on tap', (tester) async {
    await pump(tester);
    expect(find.text(ru.t('help_q1_a')), findsNothing); // collapsed
    await tester.tap(find.text(ru.t('help_q1_q')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('help_q1_a')), findsOneWidget);
  });

  testWidgets('no raw keys in any locale', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, loc);
      expect(find.textContaining('help_'), findsNothing, reason: loc.name);
    }
  });
}
