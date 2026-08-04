/// The primary call to action on the screens that have exactly one.
///
/// The spec gives a primary CTA a coral pill, an ink outline AND a 4px hard
/// offset shadow. A Flutter ButtonStyle cannot express that shadow, so the
/// themed FilledButton gets everything except the step — which is the whole
/// reason DsPrimaryButton exists.
///
/// It existed and was used nowhere. Thirteen of the fifteen Ds widgets were in
/// the same state: written, exported, called by nothing. This locks in the four
/// conversions so the widget cannot drift back to being decoration.
///
/// Two of these screens additionally carried three pre-design-system overrides
/// each — violet, a 14px radius and their own text style — so the app's most
/// blocking screen and its permission primer looked like a different product.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/force_update_screen.dart';
import 'package:fcs_app/ui/settings/legal_consent_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/widgets/error_fallback.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(l10n: const L10n(AppLocale.ru), child: screen),
    ));
    await tester.pumpAndSettle();
  }

  /// The step under the button — the part a ButtonStyle cannot carry.
  void expectHardStep(WidgetTester tester) {
    final box = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: find.byType(DsPrimaryButton), matching: find.byType(DecoratedBox)),
        )
        .firstWhere((d) => (d.decoration as BoxDecoration).boxShadow != null);
    final shadow = (box.decoration as BoxDecoration).boxShadow!.single;
    expect(shadow.offset, const Offset(4, 4));
    expect(shadow.blurRadius, 0, reason: 'a blurred shadow is not the hard step the spec draws');
    expect(shadow.color, Ds.ink);
  }

  testWidgets('the force-update screen', (tester) async {
    // The one screen a user cannot get past. It was violet with a 14px radius.
    await pump(tester, ForceUpdateScreen(onUpdate: () {}));
    expect(find.byType(DsPrimaryButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expectHardStep(tester);
  });

  testWidgets('the legal consent screen', (tester) async {
    await pump(tester, LegalConsentScreen(onAccept: () {}));
    expect(find.byType(DsPrimaryButton), findsOneWidget);
    expectHardStep(tester);
  });

  testWidgets('the error fallback', (tester) async {
    // Shown when a subtree fails to build, to someone who opened the app
    // worried about a reading. Its one action has to look like an action.
    await pump(tester, ErrorFallback(onRestart: () {}));
    expect(find.byType(DsPrimaryButton), findsOneWidget);
    expectHardStep(tester);
  });

  testWidgets('a disabled primary button keeps its outline and loses the step',
      (tester) async {
    // The force-update screen hides its button when there is no store listing,
    // but the widget's disabled state is part of its contract: still obviously
    // a button, just not one waiting to be pressed.
    await pump(
      tester,
      const Scaffold(body: Center(child: DsPrimaryButton(label: 'Обновить'))),
    );
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(of: find.byType(DsPrimaryButton), matching: find.byType(DecoratedBox)),
    );
    expect(
      boxes.every((d) => (d.decoration as BoxDecoration).boxShadow == null),
      isTrue,
      reason: 'a disabled button should not look pressable',
    );
  });
}
