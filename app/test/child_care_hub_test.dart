/// The care hub on the child detail screen.
///
/// The development, vaccination and growth screens used to hang off three
/// small header icons — easy to miss, and no summary. As cards with a one-line
/// preview they are discoverable, and each says why it is worth opening.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/newborn_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';

final today = DateTime(2026, 7, 22);

AppController withChild({DateTime? dob}) {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  c.addChild(ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: dob));
  return c;
}

// L10nScope goes ABOVE the Navigator, via builder — otherwise a pushed route
// (the vaccination screen) has no scope ancestor and L10nScope.of throws. The
// first version wrapped only `home`, which is inside the Navigator.
Widget wrap(AppController c) => MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.ru), child: child!),
      home: ChildDetailScreen(controller: c, childId: 'c1', now: () => today),
    );

Future<void> pump(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(c));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('a child with a birth date gets the three care cards', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22)); // 6 months
    addTearDown(c.dispose);
    await pump(tester, c);

    expect(find.text(ru.t('child_care').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('dev_title')), findsOneWidget);
    expect(find.text(ru.t('vac_title')), findsOneWidget);
    expect(find.text(ru.t('grw_title')), findsOneWidget);
  });

  testWidgets('without a birth date the hub is hidden, not shown empty', (tester) async {
    // All three screens are keyed on the date of birth; a hub over nothing
    // would be three dead ends.
    final c = withChild(dob: null);
    addTearDown(c.dispose);
    await pump(tester, c);

    expect(find.text(ru.t('child_care').toUpperCase()), findsNothing);
    expect(find.text(ru.t('vac_title')), findsNothing);
  });

  testWidgets('the growth card invites a first measurement when there are none',
      (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22));
    addTearDown(c.dispose);
    await pump(tester, c);
    // grw_add is the summary when no weight has been recorded.
    expect(find.text(ru.t('grw_add')), findsWidgets);
  });

  testWidgets('a recorded weight becomes the growth card summary', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22));
    addTearDown(c.dispose);
    c.recordGrowth('c1', GrowthPoint(at: today, weightKg: 6.4));
    await pump(tester, c);
    expect(find.textContaining('6.4'), findsWidgets);
  });

  testWidgets('a vaccination due now is surfaced on the card', (tester) async {
    // At two months the two-month visit is due; the card should say so rather
    // than counting down to it.
    final c = withChild(dob: DateTime(2026, 5, 22)); // 2 months
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.text(ru.t('vac_due')), findsWidgets);
  });

  testWidgets('the newborn card leads with time since the last feed', (tester) async {
    // For a young baby the card answers the 3am question straight from the
    // hub — no need to open the log.
    final c = withChild(dob: DateTime(2026, 6, 22)); // 1 month → newborn card shown
    addTearDown(c.dispose);
    // A feed earlier today (today is midnight, so 8:00 is the same calendar day).
    c.logNewbornEvent('c1', NewbornEvent(
        at: DateTime(2026, 7, 22, 8), kind: NewbornEventKind.feed, detail: 'left'));
    await pump(tester, c);
    // "Последнее: ..." — the last-feed line leads the summary.
    expect(find.textContaining(ru.t('nb_last', {'ago': ''}).trim()), findsWidgets);
  });

  testWidgets('the solids card appears in the weaning window', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22)); // 6 months
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.text(ru.t('sol_card_title')), findsOneWidget);
  });

  testWidgets('no solids card for a very young baby', (tester) async {
    final c = withChild(dob: DateTime(2026, 5, 22)); // 2 months
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.text(ru.t('sol_card_title')), findsNothing);
  });

  testWidgets('opening the solids card reaches the guide', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22)); // 6 months
    addTearDown(c.dispose);
    await pump(tester, c);
    await tester.tap(find.text(ru.t('sol_card_title')));
    await tester.pumpAndSettle();
    // The when-to-begin heading is a reliable landing marker.
    expect(find.text(ru.t('sol_when_title')), findsOneWidget);
  });

  testWidgets('the emergency medical-ID is a tap from the app bar and persists', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22));
    addTearDown(c.dispose);
    await pump(tester, c);
    await tester.tap(find.byIcon(Icons.medical_information_outlined));
    await tester.pumpAndSettle();
    // Empty at first — the invite shows. Fill an allergy and save.
    expect(find.text(ru.t('ei_empty')), findsOneWidget);
    await tester.tap(find.text(ru.t('ei_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, ru.t('ei_allergies')), 'арахис');
    await tester.tap(find.text(ru.t('ei_save')));
    await tester.pumpAndSettle();
    expect(c.emergencyInfoFor('c1').allergies, 'арахис');
  });

  testWidgets('the home-safety checklist is a care card and persists a tick', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22)); // 6 months
    addTearDown(c.dispose);
    await pump(tester, c);
    expect(find.text(ru.t('hs_card_title')), findsOneWidget);
    await tester.tap(find.text(ru.t('hs_card_title')));
    await tester.pumpAndSettle();
    // Tick a from-birth task and confirm the controller remembers it.
    await tester.tap(find.text(ru.t('hs_safe_sleep_space')));
    await tester.pumpAndSettle();
    expect(c.homeSafetyDone.contains('safe_sleep_space'), isTrue);
  });

  testWidgets('the unwell-child guide is a tap from the app bar', (tester) async {
    final c = withChild(dob: DateTime(2026, 6, 22)); // 1 month → shows the age banner
    addTearDown(c.dispose);
    await pump(tester, c);
    await tester.tap(find.byIcon(Icons.sick_outlined));
    await tester.pumpAndSettle();
    // The warning heading is a reliable landing marker; the young-baby banner
    // should also be present for a one-month-old.
    expect(find.text(ru.t('ill_warn_title')), findsOneWidget);
    expect(find.text(ru.t('ill_young_title')), findsOneWidget);
  });

  testWidgets('opening a card reaches its screen', (tester) async {
    final c = withChild(dob: DateTime(2026, 1, 22));
    addTearDown(c.dispose);
    await pump(tester, c);

    await tester.tap(find.text(ru.t('vac_title')));
    await tester.pumpAndSettle();
    // The vaccination screen's disclaimer sits at the top — a reliable marker
    // that navigation landed there. The revision line is at the bottom of a
    // long list and would be off-screen.
    expect(find.text(ru.t('vac_disclaimer')), findsOneWidget);
  });
}
