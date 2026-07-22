/// What she is told when the phone will not say where it is.
///
/// The zone editor used to fail in complete silence: a denied permission or a
/// failed fix just stopped the spinner, leaving the default centre in place.
/// That reads as success, so a zone gets saved around somewhere she has never
/// been — and then "left home" alerts arrive about a stranger's street, which
/// is worse than having no zone at all.
///
/// Both screens were fixed to show the reason. Nothing tested it: every test
/// overrode the device with a SUCCESS, so the entire failure surface — the one
/// the fix was for — was never exercised.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/device_location.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  tearDown(() => debugLocationOverride = null);

  /// Drive onboarding to the child step, where the zone tiles live.
  Future<OnboardingController> toChildStep(WidgetTester tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: OnboardingFlow(controller: controller, onComplete: (_) {}),
      ),
    ));
    await tester.tap(find.byType(Checkbox)); // accept privacy + terms
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // language
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // profile
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // pair band
    await tester.pumpAndSettle();
    expect(find.text('Add your child'), findsOneWidget);
    return controller;
  }

  const l = L10n(AppLocale.en);

  for (final (failure, key) in const [
    (LocationFailure.denied, 'zone_loc_denied'),
    (LocationFailure.deniedForever, 'zone_loc_denied_forever'),
    (LocationFailure.off, 'zone_loc_off'),
    (LocationFailure.unavailable, 'zone_loc_failed'),
  ]) {
    testWidgets('${failure.name} is explained, and no zone is set', (tester) async {
      debugLocationOverride = () async => LocationResult.failed(failure);
      final controller = await toChildStep(tester);
      // Name the child, so Finish is gated on the zone alone — otherwise this
      // would pass for the wrong reason.
      await tester.enterText(find.byType(TextField), 'Sultan');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use current location').first);
      await tester.pumpAndSettle();

      // She is told what went wrong, in her own language.
      expect(find.text(l.t(key)), findsOneWidget);
      // And nothing was saved. A zone centred on the default would be a zone
      // around a place she has never been.
      expect(controller.home, isNull);
      // Finish stays gated, so she cannot leave setup believing Home is set.
      final finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'));
      expect(finish.onPressed, isNull);
    });
  }

  testWidgets('each failure gives a DIFFERENT instruction', (tester) async {
    // The whole reason the failures are separate values is that the remedies
    // differ: a denied permission can be granted, a permanently-denied one only
    // from system settings, location switched off is a different toggle
    // entirely, and a failed fix is worth retrying somewhere with sky. Reusing
    // one message would quietly undo that.
    final messages = {
      for (final f in LocationFailure.values) l.t(LocationResult.failed(f).messageKey!),
    };
    expect(messages, hasLength(LocationFailure.values.length));
    for (final m in messages) {
      expect(m, isNot(startsWith('zone_loc'))); // a missing key renders as the key
    }
  });

  testWidgets('a slow device does not strand her on the step', (tester) async {
    // getCurrentPosition had no time limit, and both callers hold a spinner
    // across the await. A cold GPS indoors can take a very long time, and with
    // location services in an odd state it can simply never answer — on the
    // step that gates finishing setup.
    expect(locationTimeout.inSeconds, greaterThan(0));
    expect(locationTimeout, lessThanOrEqualTo(const Duration(seconds: 30)));

    // A fix that arrives after the wait still resolves to a failure she can act
    // on, rather than a spinner with no end.
    debugLocationOverride = () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return const LocationResult.failed(LocationFailure.unavailable);
    };
    await toChildStep(tester);
    await tester.tap(find.text('Use current location').first);
    await tester.pumpAndSettle();
    expect(find.text(l.t('zone_loc_failed')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
