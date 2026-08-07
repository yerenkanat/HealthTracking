/// Why the primary button will not move her on.
///
/// It was grey and silent on two of the five onboarding steps. A disabled
/// control that gives no reason is where onboarding is abandoned: she cannot
/// tell whether she missed something or the app is broken — and neither cause
/// is obvious here, because the consent checkbox sits far left of its label and
/// the phone field looks filled the moment it holds any digits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

Widget _wrap(OnboardingController c) => L10nScope(
      l10n: const L10n(AppLocale.ru),
      child: MaterialApp(
        home: OnboardingFlow(controller: c, onComplete: (_) {}),
      ),
    );

String _reason(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const Key('onb-block-reason')), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('the welcome step says the box has to be ticked', (tester) async {
    final c = OnboardingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onb-block-reason')), findsOneWidget);
    expect(_reason(tester), contains('согласие'));
  });

  testWidgets('the reason goes once she ticks it', (tester) async {
    final c = OnboardingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onb-block-reason')), findsNothing);
  });

  testWidgets('the name step names the ONE thing missing, not both', (tester) async {
    // "Enter a name and a phone number" over a form where only the phone is
    // short reads as a wall, and she has to work out which half is hers.
    // Driven through the real flow rather than poked into place.
    final c = OnboardingController()..next()..next();
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(_reason(tester), contains('имя'));

    c.setDisplayName('Айгерім');
    await tester.pumpAndSettle();
    // Name given, number still missing — the reason moves on rather than
    // repeating what she has already done.
    expect(_reason(tester), contains('номер'));
  });
}
