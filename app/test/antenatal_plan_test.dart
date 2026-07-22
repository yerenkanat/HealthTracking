/// The antenatal-plan screen: the state eight-visit schedule, keyed to the week.
///
/// The domain is verified exhaustively in tool/verify_antenatal_protocol.dart;
/// these tests are about the screen doing right by it — leading with the visit
/// that matters now, surfacing the windows that close, and never leaking a raw
/// key in any of the three languages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';

Future<void> pump(WidgetTester tester, int week, [AppLocale loc = AppLocale.ru]) async {
  // Tall so every collapsed visit tile is laid out and tappable — the lazy
  // ListView would otherwise skip the ones below the fold.
  tester.view.physicalSize = const Size(1000, 12000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: L10nScope(l10n: L10n(loc), child: AntenatalPlanScreen(week: week)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('inside a visit window it leads with "due now" and the visit number',
      (tester) async {
    await pump(tester, 27); // visit 3 (26–28) is due
    expect(find.text(ru.t('an_due_now').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('an_of_eight', {'n': 3})), findsOneWidget);
    // The lead card is expanded, so a visit-3 item is on screen.
    expect(find.text(ru.t('an_item_fetal_heartbeat')), findsWidgets);
  });

  testWidgets('between windows it leads with the next visit as "upcoming"',
      (tester) async {
    await pump(tester, 22); // no visit due; visit 3 is next
    expect(find.text(ru.t('an_upcoming').toUpperCase()), findsOneWidget);
    expect(find.text(ru.t('an_of_eight', {'n': 3})), findsOneWidget);
    expect(find.text(ru.t('an_due_now').toUpperCase()), findsNothing);
  });

  testWidgets('the time-sensitive windows surface only when one is open',
      (tester) async {
    await pump(tester, 28); // OGTT (24–28) and anti-D (28–30) both open
    expect(find.text(ru.t('an_windows_title')), findsOneWidget);
    // The window rows reuse the visit-item strings for the screening names.
    expect(find.text(ru.t('an_item_ogtt')), findsWidgets);
    expect(find.text(ru.t('an_item_anti_d')), findsWidgets);
  });

  testWidgets('early on, before any window opens, no windows block is shown',
      (tester) async {
    await pump(tester, 6);
    expect(find.text(ru.t('an_windows_title')), findsNothing);
  });

  testWidgets('the whole eight-visit plan is listed', (tester) async {
    await pump(tester, 12);
    for (var n = 1; n <= 8; n++) {
      expect(find.text(ru.t('an_visit_label', {'n': n})), findsOneWidget, reason: 'visit $n');
    }
  });

  testWidgets('a collapsed visit opens when tapped', (tester) async {
    await pump(tester, 6); // visit 1 leads/expanded; visit 2 is collapsed
    // The anomaly scan lives only on visit 2, which starts collapsed.
    expect(find.text(ru.t('an_item_us_anomaly')), findsNothing);
    await tester.tap(find.text(ru.t('an_visit_label', {'n': 2})));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('an_item_us_anomaly')), findsOneWidget);
  });

  testWidgets('once term has passed it says the plan is complete, not a raw gap',
      (tester) async {
    await pump(tester, 41);
    expect(find.text(ru.t('an_term_title')), findsOneWidget);
    // No "due" or "upcoming" lead once there is no scheduled visit left.
    expect(find.text(ru.t('an_due_now').toUpperCase()), findsNothing);
    expect(find.text(ru.t('an_upcoming').toUpperCase()), findsNothing);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 28, loc);
      expect(find.textContaining('an_'), findsNothing, reason: loc.name);
    }
  });
}
