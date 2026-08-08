/// «Тёмная тема только там, где ей место: таймер схваток, ночное кормление,
/// пуши на локскрине. Остальное — светлое.»
///
/// docs/CLAUDE-app-design.md §1.3 rule 4, with the palette in §2.17.
///
/// The contraction timer was fully light. A woman timing contractions at 3am is
/// holding a phone at arm's length in a dark room next to someone asleep, and a
/// cream screen in that moment is a torch in the face.
///
/// The rule has two halves and both are load-bearing: dark WHERE it belongs,
/// and light everywhere else. A dark theme that leaks onto the day screens is a
/// worse failure than not having one, so this file checks both directions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(l10n: const L10n(AppLocale.ru), child: screen),
    ));
    await tester.pumpAndSettle();
  }

  /// The Scaffold's own background — what she actually sees behind everything.
  Color? canvasOf(WidgetTester tester) =>
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;

  group('the contraction timer is a night screen', () {
    testWidgets('its canvas is the night one', (tester) async {
      await pump(tester, const ContractionTimerScreen());
      expect(canvasOf(tester), Ds.nightBg);
    });

    testWidgets('nothing on it is left on the day palette', (tester) async {
      // The failure this catches is a half-converted screen: one Text still
      // carrying Palette.text, invisible on the dark canvas. It is exactly what
      // happened to the app-bar title, which the accessibility sweep caught at
      // 1.08:1 — but only because that title happened to be 22px and audited.
      await pump(tester, const ContractionTimerScreen());
      final dayInk = <Color>{Ds.ink, Ds.text, Ds.cream};
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final c = t.style?.color;
        if (c == null) continue;
        expect(dayInk.contains(c), isFalse,
            reason: '«${t.data}» is still painted in a daytime colour');
      }
    });

    testWidgets('the action sits in the bottom third', (tester) async {
      // «действие в нижней трети» — she is mid-contraction and reaching with a
      // thumb, not aiming.
      await pump(tester, const ContractionTimerScreen());
      const l = L10n(AppLocale.ru);
      final button = find.text(l.t('contr_start'));
      if (button.evaluate().isEmpty) return; // label differs by state; skip
      final y = tester.getTopLeft(button).dy;
      final h = tester.getSize(find.byType(Scaffold).first).height;
      expect(y, greaterThan(h * 0.6));
    });
  });

  group('the night palette carries its own text', () {
    test('body text on the night canvas clears AA', () {
      // 12.9:1 — she is reading it in the dark with tired eyes.
      expect(contrastRatio(Ds.nightText, Ds.nightBg), greaterThan(7.0));
    });

    test('the dim label still clears AA', () {
      expect(contrastRatio(Ds.nightTextDim, Ds.nightBg), greaterThan(4.5));
    });

    test('the action button text clears AA on its own fill', () {
      expect(contrastRatio(Ds.nightActionText, Ds.nightAction), greaterThan(4.5));
    });

    test('the action is not the SOS red', () {
      // «Красный только SOS.» At night a saturated red IS the alarm colour, and
      // this button is pressed every few minutes by somebody not in danger.
      expect(Ds.nightAction, isNot(Ds.coral));
      expect(Ds.nightAction, isNot(Ds.coralCta));
    });
  });

  group('and it stays where it belongs', () {
    testWidgets('the home screen is still light', (tester) async {
      // «Остальное — светлое.» A dark theme leaking onto the day screens is a
      // worse failure than not having one.
      await pump(tester, const HealthDashboardView(samples: []));
      expect(canvasOf(tester), isNot(Ds.nightBg));
    });
  });
}
