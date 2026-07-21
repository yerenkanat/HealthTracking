/// Widget test for the onboarding flow (run with `flutter test`).
/// Drives welcome → language → profile → pairBand → child → done and asserts the
/// assembled result. Uses English scope so labels are stable.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/data/device_location.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';

void main() {
  // The zone tiles now really ask the device where it is. A widget test has no
  // platform channel, so without a stand-in the button spins forever.
  setUp(() => debugLocationOverride =
      () async => const LocationResult.ok(Coordinates(43.238949, 76.889709)));
  tearDown(() => debugLocationOverride = null);

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
    expect(result!.child!.name, 'Sultan');
    expect(result!.child!.geofences.any((f) => f.name == 'Home'), isTrue);
  });

  // The happy-path test above taps "Next" straight past the language page and
  // skips band pairing, so the radio choices themselves were never exercised.
  // These pin what selecting one actually does, independent of how the radios
  // are wired underneath.
  Widget flow(
    OnboardingController controller, {
    BandScanner? scanBands,
    void Function(AppLocale)? onLocaleChange,
  }) =>
      MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: OnboardingFlow(
            controller: controller,
            onComplete: (_) {},
            scanBands: scanBands,
            onLocaleChange: onLocaleChange,
          ),
        ),
      );

  Future<void> toLanguage(WidgetTester tester) async {
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
  }

  testWidgets('a woman with no children can finish setup', (tester) async {
    // The child step used to require a name AND a home zone, behind a single
    // button that stayed greyed out until both were given, with no skip. A
    // first-time expectant mother — the most likely person to install a
    // pregnancy app — could not get past it without inventing a child.
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

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // language
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // profile
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next')); // band, optional
    await tester.pumpAndSettle();

    // The child step, untouched. The button says so rather than showing a
    // "Finish" that cannot be pressed.
    expect(find.text('Add your child'), findsOneWidget);
    final skip = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Skip for now'));
    expect(skip.onPressed, isNotNull);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.child, isNull); // no invented child
    expect(result!.profile.displayName, 'Aigerim');
  });

  testWidgets('picking a language selects it and switches the app live', (tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    final live = <AppLocale>[];
    await tester.pumpWidget(flow(controller, onLocaleChange: live.add));
    await toLanguage(tester);

    expect(controller.locale, AppLocale.en);
    await tester.tap(find.text('Қазақша'));
    await tester.pumpAndSettle();

    expect(controller.locale, AppLocale.kk);
    expect(live, [AppLocale.kk]); // the whole app follows, not just this page
  });

  testWidgets('the selected language is the one shown as chosen', (tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    await tester.pumpWidget(flow(controller));
    await toLanguage(tester);

    RadioListTile<AppLocale> tileFor(String label) => tester.widget<RadioListTile<AppLocale>>(
        find.ancestor(of: find.text(label), matching: find.byType(RadioListTile<AppLocale>)));

    expect(tileFor('English').value, AppLocale.en);
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(controller.locale, AppLocale.ru);
  });

  testWidgets('switching language re-labels the flow immediately', (tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    late AppLocale current;
    current = AppLocale.en;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      return MaterialApp(
        home: L10nScope(
          l10n: L10n(current),
          child: OnboardingFlow(
            controller: controller,
            onComplete: (_) {},
            onLocaleChange: (v) => setState(() => current = v),
          ),
        ),
      );
    }));
    await toLanguage(tester);

    expect(find.text('Choose your language'), findsOneWidget);
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsNothing); // now in Russian
  });

  testWidgets('picking a discovered band records it', (tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    await tester.pumpWidget(flow(
      controller,
      scanBands: () => Stream.value(const [
        (id: 'AA:BB', name: 'Umay Band'),
        (id: 'CC:DD', name: 'Other Band'),
      ]),
    ));

    // Welcome → language → profile → pair.
    await toLanguage(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Pair your band'), findsOneWidget);
    expect(controller.bandId, isNull);
    await tester.tap(find.text('Umay Band'));
    await tester.pumpAndSettle();
    expect(controller.bandId, 'AA:BB');

    // Choosing a different band replaces the first, rather than adding to it.
    await tester.tap(find.text('Other Band'));
    await tester.pumpAndSettle();
    expect(controller.bandId, 'CC:DD');
  });
}
