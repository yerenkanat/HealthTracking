/// The advisor screen's entry into the conversational assistant.
///
/// The chat screen was fully built but had no way in — nothing navigated to it.
/// These tests lock the entry so it cannot silently disappear again: the advisor
/// offers an "ask" affordance when a chat callback is wired, and none when it is
/// not (offline/test builds where the assistant is unavailable).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';

Future<void> pump(WidgetTester tester, {VoidCallback? onOpenChat}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(
      l10n: const L10n(AppLocale.ru),
      child: AdvisorScreen(samples: const [], onOpenChat: onOpenChat),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('offers the assistant entry when chat is wired', (tester) async {
    var opened = 0;
    await pump(tester, onOpenChat: () => opened++);
    // Both the app-bar action and the ask card carry the forum icon.
    expect(find.byIcon(Icons.forum_outlined), findsWidgets);
    // The ask card leads with the assistant's greeting.
    expect(find.text(ru.t('chat_empty_title')), findsOneWidget);
    await tester.tap(find.text(ru.t('adv_ask_sub')));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('hides the entry when there is nothing to chat with', (tester) async {
    await pump(tester); // onOpenChat null
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(find.text(ru.t('adv_ask_sub')), findsNothing);
  });
}
