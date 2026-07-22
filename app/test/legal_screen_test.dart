/// The privacy & terms screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/legal_screen.dart';

Future<void> pump(WidgetTester tester, LegalDoc doc, [AppLocale loc = AppLocale.ru]) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: LegalScreen(doc: doc)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('privacy shows the draft banner and the not-a-device boundary', (tester) async {
    await pump(tester, LegalDoc.privacy);
    expect(find.text(ru.t('legal_draft_note')), findsOneWidget);
    expect(find.text(ru.t('legal_priv_medical_h')), findsOneWidget);
    expect(find.text(ru.t('legal_priv_controls_h')), findsOneWidget);
  });

  testWidgets('terms shows the emergency-services boundary', (tester) async {
    await pump(tester, LegalDoc.terms);
    expect(find.text(ru.t('legal_terms_emergency_h')), findsOneWidget);
    expect(find.textContaining('103'), findsOneWidget); // ambulance number is spelled out
  });

  testWidgets('no raw keys in any locale', (tester) async {
    for (final loc in AppLocale.values) {
      for (final doc in LegalDoc.values) {
        await pump(tester, doc, loc);
        expect(find.textContaining('legal_'), findsNothing, reason: '${doc.name}/${loc.name}');
      }
    }
  });
}
