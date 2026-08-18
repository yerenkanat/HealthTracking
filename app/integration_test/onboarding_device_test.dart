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

import 'package:fcs_app/ble/band_scan.dart';
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

  testWidgets('a step she is bounced back to still SHOWS her name and number',
      (tester) async {
    // Observed here, on a handset, and on no other kind of run: deny the
    // Bluetooth permission on step 4 and the flow drops back to step 3 with the
    // name and phone boxes blank — while the pregnancy switch beside them is
    // still on. The data was never lost. The fields were declared without a
    // `controller:`, so each fresh State made itself an empty private one and
    // painted that over a model that still said "Aigerim".
    //
    // On a device because the bounce arrives with the real IME open: the
    // keyboard resizes the layout, the page is rebuilt under it, and that is
    // the state a widget test cannot stand up. Found by finder, never by
    // coordinate — remembered positions are what produced three false reports
    // on this flow.
    final c = OnboardingController(initialLocale: AppLocale.en);
    addTearDown(c.dispose);
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: OnboardingFlow(controller: c, onComplete: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    await toProfile(tester);

    await tester.tap(find.byType(TextField).first); // raises the real keyboard
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Pair your band'), findsOneWidget);

    // The bounce.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);

    String shown(Finder field) => tester
        .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)))
        .controller
        .text;

    expect(shown(find.byType(TextField).first), c.displayName,
        reason: 'the field is showing something other than what the app holds '
            '("${c.displayName}"), and «Next» is enabled from the model — so a '
            'blank-looking required field advances the flow');
    expect(shown(find.byType(TextField).last), c.phoneNumber);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed,
      isNotNull,
    );
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

  /// The real radio, on a real handset, with no watch anywhere near it.
  ///
  /// The widget suite drives every [BandScanPhase] through an injected stream,
  /// which proves the page can draw them. It cannot prove the thing that was
  /// actually broken: that the SCAN ever leaves «Поиск устройств…». It never
  /// did — an empty list was its answer to Bluetooth being off, to the
  /// permission being declined, and to nothing being nearby alike, so the
  /// spinner ran until she gave up.
  ///
  /// Only a device can settle that, and it is deliberately not asserted WHICH
  /// reason this machine gives: an emulator with no Bluetooth stack, a phone
  /// with the radio off and a phone in an empty room are three different true
  /// answers. What must hold on all of them is that the page stops spinning,
  /// names something, and offers a way on.
  testWidgets('the pairing step stops spinning and says what happened',
      (tester) async {
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: OnboardingFlow(
          controller: OnboardingController(initialLocale: AppLocale.en),
          onComplete: (_) {},
          // The real scan, on a short window so the test does not sit through
          // the production fifteen seconds.
          scanBands: () => scanForBands(timeout: const Duration(seconds: 3)),
        ),
      ),
    ));
    await tester.pump();
    await toProfile(tester);
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    // pump, NOT pumpAndSettle: the scanning state carries an indeterminate
    // progress indicator and pumpAndSettle would wait for it for ever — which
    // is a fair description of the defect this test exists for.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pair your band'), findsOneWidget);

    // Let the window close, plus a margin for the platform round-trip.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    final settled = [
      const Key('onb-pair-none'),
      const Key('onb-pair-bluetooth-off'),
      const Key('onb-pair-permission'),
      const Key('onb-pair-unsupported'),
      const Key('onb-pair-failed'),
    ].where((k) => find.byKey(k).evaluate().isNotEmpty).toList();

    // Either it found a watch (somebody left one on the desk) or it settled on
    // exactly one reason. What it may NOT do is neither.
    final foundAWatch = find.byType(RadioListTile<String>).evaluate().isNotEmpty;
    expect(foundAWatch || settled.length == 1, isTrue,
        reason: 'the scan is still showing the scanning line after its window '
            'closed — the state it could never leave');

    if (!foundAWatch) {
      // A reason, and a way on. «Пока нет — буду записывать вручную» is always
      // there; a retry is offered wherever retrying could change the answer.
      expect(find.byKey(const Key('onb-pair-no-device')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  });
}
