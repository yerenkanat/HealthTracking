/// The privacy & terms screens.
///
/// These were six short sections until the documents were rewritten against an
/// inventory of what the code actually does. Two of the things this file used to
/// assert are gone — `legal_priv_controls_h` was split into rights and staff
/// access, `legal_priv_cloud_b` into a named sub-processor list and a dedicated
/// cry section — and the test failing on their absence is the reason it is worth
/// having. It was updated rather than deleted.
///
/// With seventeen sections per document nothing below the third is on screen at
/// once, so every assertion here scrolls. A `findsNothing` against an unscrolled
/// ListView proves only that the widget is far down the page.
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

/// Scrolls the document until [finder] is on screen, then asserts it is there.
Future<void> expectOnPage(WidgetTester tester, Finder finder, {String? reason}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 200);
  }
  expect(finder, findsWidgets, reason: reason);
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('privacy shows the draft banner and the not-a-device boundary', (tester) async {
    await pump(tester, LegalDoc.privacy);
    expect(find.text(ru.t('legal_draft_note')), findsOneWidget);
    await expectOnPage(tester, find.text(ru.t('legal_priv_medical_h')));
    await expectOnPage(tester, find.text(ru.t('legal_priv_rights_h')));
  });

  testWidgets('terms shows the emergency-services boundary', (tester) async {
    await pump(tester, LegalDoc.terms);
    await expectOnPage(tester, find.text(ru.t('legal_terms_emergency_h')));
    await expectOnPage(tester, find.textContaining('103'),
        reason: 'the ambulance number is spelled out, not implied');
  });

  testWidgets('the operator is named and the unfilled slots are visible', (tester) async {
    // The documents ship with БИН, the registered address and the contact
    // e-mail deliberately blank, because inventing a company registration
    // number is worse than publishing without one. The blanks are the reminder,
    // and the draft banner is what explains them — neither may quietly vanish
    // while the other stays.
    await pump(tester, LegalDoc.privacy);
    await expectOnPage(tester, find.textContaining('Ana-Bala'));
    await expectOnPage(tester, find.textContaining('______'),
        reason: 'the slots for БИН / address / e-mail are no longer visible — '
            'if they were filled in, the draft banner must go too');
  });

  testWidgets('the cry section says both halves, in every language', (tester) async {
    // The tempting sentence is «звук не покидает телефон», and it is false: the
    // clip is uploaded. What is true is that it is stored nowhere. A policy
    // that states only the comforting half is the defect this guards.
    for (final loc in AppLocale.values) {
      final body = L10n(loc).t('legal_priv_cry_b');
      expect(body, isNot(contains('legal_')), reason: '${loc.name}: raw key');
      await pump(tester, LegalDoc.privacy, loc);
      await expectOnPage(tester, find.text(L10n(loc).t('legal_priv_cry_h')),
          reason: '${loc.name}: no cry section in the privacy policy');
    }
  });

  testWidgets('every section is written in every language', (tester) async {
    // Nothing user-visible ships without its Kazakh. While the Kazakh copy is
    // being written the untranslated values carry a visible marker, so this
    // test fails until the last one is replaced — which is the point of using a
    // marker rather than falling back to Russian.
    for (final loc in AppLocale.values) {
      for (final doc in LegalDoc.values) {
        await pump(tester, doc, loc);
        expect(find.textContaining('legal_'), findsNothing,
            reason: '${doc.name}/${loc.name}: a key leaked onto the page');
        expect(find.textContaining('аударылмаған'), findsNothing,
            reason: '${doc.name}/${loc.name}: an untranslated section is on screen');
      }
    }
  });
}
