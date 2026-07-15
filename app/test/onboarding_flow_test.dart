/// Widget test for the onboarding flow (run with `flutter test`).
/// Drives welcome → language → profile → pairBand → child → done and asserts the
/// assembled result. Uses English scope so labels are stable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  testWidgets('completes the flow and produces a config', (tester) async {
    OnboardingResult? result;
    final controller = OnboardingController(initialLocale: AppLocale.en);

    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: OnboardingFlow(
          controller: controller,
          onComplete: (r) => result = r,
        ),
      ),
    ));

    // Welcome → Get started.
    expect(find.text('Welcome to Umay'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // Language → Next.
    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Profile: Next disabled until a name AND phone are entered.
    expect(find.text("What's your name?"), findsOneWidget);
    final nextBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'));
    expect(nextBtn.onPressed, isNull); // gated
    await tester.enterText(find.byType(TextField).first, 'Aigerim'); // name
    await tester.enterText(find.byType(TextField).last, '7001234567'); // phone
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Pair band: optional → Next enabled, skip.
    expect(find.text('Pair your band'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Child: Finish gated until name + Home set.
    expect(find.text('Add your child'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sultan');
    await tester.pumpAndSettle();
    var finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'));
    expect(finish.onPressed, isNull); // no Home yet
    await tester.tap(find.text('Use current location').first); // set Home
    await tester.pumpAndSettle();
    finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'));
    expect(finish.onPressed, isNotNull);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    // Result assembled.
    expect(result, isNotNull);
    expect(result!.profile.displayName, 'Aigerim');
    expect(result!.profile.e164, '+77001234567');
    expect(result!.child.name, 'Sultan');
    expect(result!.child.geofences.any((f) => f.name == 'Home'), isTrue);
  });
}
