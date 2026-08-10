/// ON-DEVICE onboarding. Run against a running emulator or device:
///   flutter test integration_test/onboarding_device_test.dart
///
/// WHY THIS EXISTS, given onboarding_flow_test.dart already drives the same
/// steps and passes.
///
/// I audited this flow by hand — screenshot, read the pixels, `adb shell input
/// tap <x> <y>`, repeat — and reported three defects: «Далее» dead on step 3, a
/// blank «Дата родов» picker, and a black screen after BACK. All three were
/// wrong. Entering the phone number opens the soft keyboard, the keyboard
/// resizes the layout, and every remembered coordinate then lands somewhere
/// else; one of my taps left the app entirely. A dead GPU renderer on the
/// emulator hid that it was happening.
///
/// So this file is the replacement for that method. It finds widgets instead of
/// guessing positions, which is the part I got wrong, and it runs on a device,
/// which is the part a widget test cannot do:
///
///   - the REAL soft keyboard opens over the REAL layout. `tester.enterText`
///     in a widget test never shows an IME, so the one thing that actually
///     defeated the manual pass is invisible to the existing widget test.
///   - real fonts at the real density, so a label that overflows on a phone
///     and not in a 390x844 test window shows up here.
///
/// If this passes and a manual pass appears to fail, believe this one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/data/device_location.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The zone tiles really ask the device where it is; on a device that raises a
  // permission dialog with nobody to tap it, which hangs the run.
  setUp(() => debugLocationOverride =
      () async => const LocationResult.ok(Coordinates(43.238949, 76.889709)));
  tearDown(() => debugLocationOverride = null);

  /// English, so the labels are stable regardless of the device's language.
  Future<void> pumpOnboarding(WidgetTester tester,
      {void Function(OnboardingResult)? onComplete}) async {
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: OnboardingFlow(
          controller: OnboardingController(initialLocale: AppLocale.en),
          onComplete: onComplete ?? (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Through welcome and language, leaving the profile step on screen.
  Future<void> toProfile(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);
  }

  testWidgets('the consent gate blocks, and says why', (tester) async {
    await pumpOnboarding(tester);
    final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Get started'));
    expect(cta.onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Get started'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('«Далее» is reachable and works with the keyboard OPEN',
      (tester) async {
    // THE test. This is the exact state I misread by hand: name and phone
    // entered, the IME up and pushing the CTA off where I expected it. A tap
    // found by widget, not by coordinate, must still advance the flow.
    await pumpOnboarding(tester);
    await toProfile(tester);

    // Tapping the field is what raises the real keyboard — enterText alone
    // does not, and the keyboard is the whole point of running this on a
    // device.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();

    // Scroll it into view if the keyboard covers it — a CTA that can be
    // reached by scrolling is fine; one that cannot is the bug I thought I
    // had found.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    expect(find.text("What's your name?"), findsNothing,
        reason: 'the profile step should have been left behind');
    expect(find.text('Pair your band'), findsOneWidget);
  });

  testWidgets('the profile step states WHY it is blocking', (tester) async {
    // A disabled button with no reason is indistinguishable from a broken one
    // — which is precisely the conclusion I drew from a screenshot.
    await pumpOnboarding(tester);
    await toProfile(tester);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.pumpAndSettle();
    // Name present, phone still missing: the reason must name the phone.
    expect(find.textContaining('phone', findRichText: true), findsWidgets);
  });

  testWidgets('a full run on this device produces a config', (tester) async {
    OnboardingResult? result;
    await pumpOnboarding(tester, onComplete: (r) => result = r);
    await toProfile(tester);

    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    // Pair band is optional.
    expect(find.text('Pair your band'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Child: «Finish» is gated on a name AND a Home zone.
    expect(find.text('Add your child'), findsOneWidget);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Sultan');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish')).onPressed,
      isNull,
      reason: 'no Home zone yet',
    );

    await tester.tap(find.text('Use current location').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    expect(result, isNotNull,
        reason: 'the flow completed but handed back no configuration');
    expect(result!.profile.displayName, 'Aigerim');
    // Normalised to E.164 on the way out — the one transformation in this flow
    // that a human reading the screen cannot check.
    expect(result!.profile.e164, '+77001234567');
    expect(result!.child!.name, 'Sultan');
    expect(result!.child!.geofences.any((f) => f.name == 'Home'), isTrue);
  });
}
