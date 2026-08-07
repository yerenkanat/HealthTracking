/// «Красные флаги — отдельным блоком, не под "читать дальше". Внизу — 103.»
///
/// docs/CLAUDE-app-design.md §"Медицинские формулировки".
///
/// Both red-flag screens listed the signs and stopped. A woman who has just
/// read «кровотечение», «схватки раньше срока», «ребёнок стал меньше
/// шевелиться» and recognised herself was left to leave the app, find the
/// dialler and remember the number — in the state of mind that list creates.
/// A parent reading the child's fever red flags was in the same position.
///
/// The first half of the rule already held and is checked here too, because it
/// is the half that would break silently: a future "show more" wrapped around a
/// long list is an obvious, reasonable-looking edit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/pregnancy_warnings.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/child_illness_screen.dart';
import 'package:fcs_app/ui/widgets/call_ambulance.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen,
      {AppLocale locale = AppLocale.ru}) async {
    tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(locale),
      home: L10nScope(l10n: L10n(locale), child: screen),
    ));
    await tester.pumpAndSettle();
  }

  final screens = <String, Widget Function()>{
    'the pregnancy warnings': () => const PregnancyWarningsScreen(),
    'the child illness guide': () => const ChildIllnessScreen(ageMonths: 8),
  };

  group('every red-flag screen ends with a way to call', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} offers 103', (tester) async {
        await pump(tester, entry.value());
        expect(find.byType(CallAmbulanceFooter), findsOneWidget,
            reason: '${entry.key} lists the signs and leaves her to find the number');
        // The digits are on screen, not only behind the tap: a tablet or a
        // locked-down device cannot open a dialler, and she still needs them.
        expect(find.textContaining(kAmbulanceTel), findsWidgets);
      });

      testWidgets('${entry.key} keeps the red flags out in the open', (tester) async {
        // «не под "читать дальше"». An ExpansionTile around a long warning list
        // is an obvious, reasonable-looking edit, and it would hide the one
        // block on the screen that must not be hidden.
        await pump(tester, entry.value());
        expect(find.byType(ExpansionTile), findsNothing,
            reason: '${entry.key} put its warnings behind a disclosure');
      });
    }
  });

  testWidgets('it is at the BOTTOM, under the signs it belongs to', (tester) async {
    // Above the list it reads as a banner and gets skipped past on the way to
    // the content; the rule is «внизу» for a reason.
    await pump(tester, const PregnancyWarningsScreen());
    final cardY = tester.getTopLeft(find.byType(PregnancyWarningsCard)).dy;
    final callY = tester.getTopLeft(find.byType(CallAmbulanceFooter)).dy;
    expect(callY, greaterThan(cardY));
  });

  testWidgets('on the illness screen it outranks the small print', (tester) async {
    await pump(tester, const ChildIllnessScreen(ageMonths: 8));
    const l = L10n(AppLocale.ru);
    final callY = tester.getTopLeft(find.byType(CallAmbulanceFooter)).dy;
    final disclaimerY = tester.getTopLeft(find.text(l.t('ill_disclaimer'))).dy;
    expect(callY, lessThan(disclaimerY),
        reason: 'the disclaimer sits between the red flags and the way to act on them');
  });

  group('tapping it', () {
    testWidgets('dials 103', (tester) async {
      final dialled = <String>[];
      await pump(
        tester,
        Scaffold(
          body: CallAmbulanceFooter(onCall: (tel) async {
            dialled.add(tel);
            return true;
          }),
        ),
      );
      await tester.tap(find.byType(CallAmbulanceFooter));
      await tester.pumpAndSettle();
      expect(dialled, ['103']);
    });

    testWidgets('shows the number when the dialler will not open', (tester) async {
      // Doing nothing on a failed launch is the worst outcome: she taps, the
      // screen does not move, and she assumes the call went out.
      await pump(
        tester,
        Scaffold(body: CallAmbulanceFooter(onCall: (_) async => false)),
      );
      await tester.tap(find.byType(CallAmbulanceFooter));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('103'), findsWidgets);
    });
  });

  testWidgets('it is not dressed as an alarm', (tester) async {
    // This sits on a reference screen she may be reading calmly at week 20.
    // «Красный только SOS» — borrowing the emergency palette here is what makes
    // the emergency screen stop meaning anything.
    await pump(tester, const PregnancyWarningsScreen());
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(CallAmbulanceFooter),
        matching: find.byType(Container),
      ).first,
    );
    expect((box.decoration as BoxDecoration).color, isNot(Palette.danger));
  });

  testWidgets('it speaks every language', (tester) async {
    for (final locale in AppLocale.values) {
      await pump(tester, const PregnancyWarningsScreen(), locale: locale);
      final l = L10n(locale);
      expect(find.text(l.t('em_call_ambulance')), findsOneWidget,
          reason: 'no call action in ${locale.name}');
      expect(find.text(l.t('em_ambulance_hint', {'tel': kAmbulanceTel})), findsOneWidget,
          reason: 'no ambulance hint in ${locale.name}');
    }
  });
}
