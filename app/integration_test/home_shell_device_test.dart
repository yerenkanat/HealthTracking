/// ON-DEVICE smoke test for the app BEYOND onboarding:
///   flutter test integration_test/home_shell_device_test.dart
///
/// This is the coverage the manual audit never reached. Tapping my way there by
/// coordinate went wrong on step 3 of onboarding and never recovered, so the
/// dashboard, calendar, child and profile tabs were reported as "untested on
/// device" — which they were, for the whole audit.
///
/// It gets there the way a user does: the real OnboardingFlow, driven by
/// finder, whose result is handed to a real AppController, which then drives
/// the real FcsApp. That handoff is itself worth exercising — completeOnboarding
/// is the join between the flow and the app, and a widget test of either half
/// cannot see it.
///
/// DELIBERATELY A SMOKE TEST. It asserts that each tab renders something and
/// that switching between them does not throw, and it does NOT assert screen
/// content: there is no backend behind this run, so every network-fed surface is
/// legitimately empty and pinning what it shows would pin the empty state. What
/// it does catch is the class of failure I spent the audit chasing — a tab that
/// paints nothing, a route that throws, a build that fails on a real device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fcs_app/app/app.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/data/device_location.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugLocationOverride =
      () async => const LocationResult.ok(Coordinates(43.238949, 76.889709)));
  tearDown(() => debugLocationOverride = null);

  /// Drive the real flow and return what it produced.
  Future<OnboardingResult> runOnboarding(WidgetTester tester) async {
    OnboardingResult? result;
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: OnboardingFlow(
          controller: OnboardingController(initialLocale: AppLocale.en),
          onComplete: (r) => result = r,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // language
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Next'));
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next')); // skip band pairing
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Sultan');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use current location').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Finish'));
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    expect(result, isNotNull, reason: 'onboarding produced no result');
    return result!;
  }

  testWidgets('onboarding hands off to an app that actually starts',
      (tester) async {
    final result = await runOnboarding(tester);

    // No persistStore: this run must not write over whatever is on the device.
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.completeOnboarding(result);
    expect(controller.onboarded, isTrue,
        reason: 'completeOnboarding did not leave the app onboarded');

    await tester.pumpWidget(FcsApp(
      controller: controller,
      content: ContentStore(const ContentCatalog({})),
    ));
    await tester.pumpAndSettle();

    // Past the gate: the onboarding flow must be gone and a shell present.
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the home shell did not render its navigation');
  });

  testWidgets('every tab paints, and switching between them does not throw',
      (tester) async {
    final result = await runOnboarding(tester);
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.completeOnboarding(result);

    await tester.pumpWidget(FcsApp(
      controller: controller,
      content: ContentStore(const ContentCatalog({})),
    ));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = [
      for (final d in bar.destinations)
        if (d is NavigationDestination) d.label,
    ];
    expect(labels.length, greaterThanOrEqualTo(4),
        reason: 'expected the four-tab shell');

    for (final label in labels) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();

      // "Painted something" — a tab that throws during build leaves the
      // ErrorFallback, and a tab wired to nothing leaves an empty Scaffold.
      expect(find.byType(Scaffold), findsWidgets, reason: '$label painted no scaffold');
      expect(tester.takeException(), isNull, reason: '$label threw while building');
    }

    // And back to the first, so a tab that only works on first paint is caught.
    await tester.tap(find.text(labels.first).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
