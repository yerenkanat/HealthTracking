/// Consent versioning: a returning user must re-accept when the legal documents
/// change, and acceptance is persisted (not a transient onboarding checkbox).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/legal.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/legal_consent_screen.dart';

void main() {
  const ru = L10n(AppLocale.ru);

  test('completing onboarding records the current legal version', () {
    final c = AppController(now: () => DateTime(2026, 7, 22), locale: AppLocale.ru);
    addTearDown(c.dispose);
    expect(c.acceptedLegalVersion, 0);
    c.debugMarkOnboarded(); // same path as onboarding for consent capture
    expect(c.acceptedLegalVersion, currentLegalVersion);
    expect(c.needsLegalConsent, isFalse);
  });

  test('a returning user from before the terms changed needs to re-consent', () {
    final c = AppController(now: () => DateTime(2026, 7, 22), locale: AppLocale.ru);
    addTearDown(c.dispose);
    c.debugMarkOnboarded();
    // Simulate a returning user who accepted an older version.
    c.debugSetAcceptedLegalVersion(currentLegalVersion - 1);
    expect(c.needsLegalConsent, isTrue);
    c.acceptLegal();
    expect(c.needsLegalConsent, isFalse);
    expect(c.acceptedLegalVersion, currentLegalVersion);
  });

  testWidgets('the re-consent screen accepts and calls back', (tester) async {
    var accepted = false;
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: ru,
        child: LegalConsentScreen(onAccept: () => accepted = true),
      ),
    ));
    expect(find.text(ru.t('legal_update_title')), findsOneWidget);
    await tester.tap(find.text(ru.t('legal_update_accept')));
    await tester.pump();
    expect(accepted, isTrue);
  });
}
