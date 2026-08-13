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
    expect(find.text('Welcome to Ana-Bala'), findsOneWidget);
    await tester.tap(find.byType(Checkbox)); // accept privacy + terms
    await tester.pump();
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
  // L10nScope ABOVE MaterialApp, not at `home:`. Under `home:` it sits below
  // the Navigator, so anything the flow PUSHES (the privacy and terms screens)
  // falls back to English silently — L10nScope.of returns a default rather than
  // throwing, which is how a working screen comes to look broken.
  Widget flow(
    OnboardingController controller, {
    BandScanner? scanBands,
    BluetoothEnabler? onEnableBluetooth,
    void Function(AppLocale)? onLocaleChange,
  }) =>
      L10nScope(
        l10n: const L10n(AppLocale.en),
        child: MaterialApp(
          home: OnboardingFlow(
            controller: controller,
            onComplete: (_) {},
            scanBands: scanBands,
            onEnableBluetooth: onEnableBluetooth,
            onLocaleChange: onLocaleChange,
          ),
        ),
      );

  Future<void> toLanguage(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox)); // accept privacy + terms
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
  }

  testWidgets('the welcome step gates on accepting privacy + terms', (tester) async {
    await tester.pumpWidget(flow(OnboardingController(initialLocale: AppLocale.en)));
    await tester.pumpAndSettle();
    // Before consent, "Get started" is disabled and we stay on welcome.
    FilledButton start() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Get started'));
    expect(start().onPressed, isNull);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Ana-Bala'), findsOneWidget); // did not advance

    // Ticking the box (or its label) enables it.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(start().onPressed, isNotNull);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);
  });

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

  /// Walk to the pairing step. Every pairing assertion below starts here rather
  /// than building `_PairBandPage` directly: the defect being guarded is that
  /// the step a woman actually REACHES shows the state, and a widget test that
  /// mounts the page in isolation proves nothing about reachability.
  Future<void> toPairStep(WidgetTester tester) async {
    await toLanguage(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Aigerim');
    await tester.enterText(find.byType(TextField).last, '7001234567');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    // pump, NOT pumpAndSettle: the scanning state carries an indeterminate
    // progress indicator, and pumpAndSettle waits for an animation that by
    // design never ends.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pair your band'), findsOneWidget);
  }

  testWidgets('picking a discovered band records it', (tester) async {
    final controller = OnboardingController(initialLocale: AppLocale.en);
    await tester.pumpWidget(flow(
      controller,
      scanBands: () => Stream.value(const BandScanUpdate(
        BandScanPhase.found,
        bands: [
          (id: 'AA:BB', name: 'Umay Band', rssi: -55),
          (id: 'CC:DD', name: 'Other Band', rssi: -88),
        ],
      )),
    ));

    // Welcome → language → profile → pair.
    await toPairStep(tester);
    expect(controller.bandId, isNull);
    await tester.tap(find.text('Umay Band'));
    await tester.pumpAndSettle();
    expect(controller.bandId, 'AA:BB');

    // Choosing a different band replaces the first, rather than adding to it.
    await tester.tap(find.text('Other Band'));
    await tester.pumpAndSettle();
    expect(controller.bandId, 'CC:DD');

    // Two identical advertisements are told apart by id and signal — the pair
    // of facts that says which of them is the watch in front of her.
    expect(find.textContaining('strong signal'), findsOneWidget);
    expect(find.textContaining('weak signal'), findsOneWidget);
  });

  /// The pairing step had two states and needed six.
  ///
  /// `scanForBands` collapsed radio-off, permission-declined, no-watch-nearby
  /// and window-not-elapsed into one empty list, so the page showed «Поиск
  /// устройств…» for ever in all four. The state a woman is most likely to hit
  /// — Bluetooth simply switched off — never named Bluetooth anywhere on the
  /// screen, so the one thing she could have fixed was the one thing the app
  /// would not tell her.
  ///
  /// Each of these drives the flow to the step she really reaches and asserts
  /// the sentence AND the action.
  group('the pairing step names what went wrong', () {
    Future<void> pumpPhase(
      WidgetTester tester,
      BandScanUpdate update, {
      Future<bool> Function()? onEnableBluetooth,
      OnboardingController? controller,
    }) async {
      await tester.pumpWidget(flow(
        controller ?? OnboardingController(initialLocale: AppLocale.en),
        scanBands: () => Stream.value(update),
        onEnableBluetooth: onEnableBluetooth,
      ));
      await toPairStep(tester);
    }

    testWidgets('Bluetooth off says so, and offers to switch it on',
        (tester) async {
      var asked = 0;
      await pumpPhase(
        tester,
        const BandScanUpdate(BandScanPhase.bluetoothOff),
        onEnableBluetooth: () async {
          asked++;
          return false; // she declined the system dialog
        },
      );

      expect(find.byKey(const Key('onb-pair-bluetooth-off')), findsOneWidget);
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Without it the phone cannot see the band.'),
          findsOneWidget);
      // Not the scanning line: that is the state this replaces.
      expect(find.text('Scanning for devices…'), findsNothing);

      await tester.tap(find.text('Turn Bluetooth on'));
      await tester.pumpAndSettle();
      expect(asked, 1);
      // A refusal leaves the honest plate up rather than restarting a search
      // that cannot succeed.
      expect(find.text('Bluetooth is off'), findsOneWidget);
    });

    testWidgets('with no way to switch the radio on, it offers to look again',
        (tester) async {
      // iOS: no API to turn Bluetooth on. A button that did nothing would be
      // worse than none, so the state still carries an action — just a
      // different one.
      await pumpPhase(tester, const BandScanUpdate(BandScanPhase.bluetoothOff));
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Turn Bluetooth on'), findsNothing);
      expect(find.text('Search again'), findsOneWidget);
    });

    testWidgets('a declined permission says which one and does not blame her',
        (tester) async {
      await pumpPhase(
          tester, const BandScanUpdate(BandScanPhase.permissionDenied));
      expect(find.byKey(const Key('onb-pair-permission')), findsOneWidget);
      expect(find.text('Bluetooth permission is needed'), findsOneWidget);
      expect(find.textContaining('We do not use your location.'), findsOneWidget);
      expect(find.text('Search again'), findsOneWidget);
    });

    testWidgets('nothing nearby is a finished search, not an endless one',
        (tester) async {
      await pumpPhase(tester, const BandScanUpdate(BandScanPhase.noneNearby));
      expect(find.byKey(const Key('onb-pair-none')), findsOneWidget);
      expect(find.text('Nothing found nearby'), findsOneWidget);
      expect(find.textContaining('is charged and switched on'), findsOneWidget);
      expect(find.text('Search again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a phone with no radio is not told to switch one on',
        (tester) async {
      await pumpPhase(tester, const BandScanUpdate(BandScanPhase.unsupported));
      expect(find.byKey(const Key('onb-pair-unsupported')), findsOneWidget);
      expect(find.text('This phone has no Bluetooth'), findsOneWidget);
      // No retry and no "turn it on": both would be lies here. The way on is
      // the manual route, which is on the screen.
      expect(find.text('Search again'), findsNothing);
      expect(find.text('Turn Bluetooth on'), findsNothing);
      expect(find.text('Not yet — I will log by hand'), findsOneWidget);
    });

    testWidgets('a scan that would not start says that, and can be retried',
        (tester) async {
      await pumpPhase(tester, const BandScanUpdate(BandScanPhase.failed));
      expect(find.byKey(const Key('onb-pair-failed')), findsOneWidget);
      expect(find.text('The search did not start'), findsOneWidget);
      expect(find.text('Search again'), findsOneWidget);
    });

    testWidgets('scanning still looks like scanning', (tester) async {
      await pumpPhase(tester, BandScanUpdate.opening);
      expect(find.text('Scanning for devices…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // «выберите из списка» is not printed over an area with no list in it.
      expect(find.text('Pick your band from the list. You can do this later.'),
          findsNothing);
      expect(find.text('Switch the band on and keep it near the phone.'),
          findsOneWidget);
    });

    testWidgets('a found list says the search is still open', (tester) async {
      await pumpPhase(
        tester,
        const BandScanUpdate(
          BandScanPhase.found,
          bands: [(id: 'AA:BB', name: 'AK-08B', rssi: -60)],
          searching: true,
        ),
      );
      expect(find.text('Still looking…'), findsOneWidget);
      // Only here is "pick from the list" a true sentence.
      expect(find.text('Pick your band from the list. You can do this later.'),
          findsOneWidget);
    });

    testWidgets('«I have no band» explains what she keeps, not just what she loses',
        (tester) async {
      final controller = OnboardingController(initialLocale: AppLocale.en);
      await pumpPhase(tester, const BandScanUpdate(BandScanPhase.noneNearby),
          controller: controller);

      await tester.tap(find.byKey(const Key('onb-pair-no-device')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onb-pair-manual')), findsOneWidget);
      expect(find.text('Log it by hand'), findsOneWidget);
      expect(find.textContaining('the diary, the calendars and the reminders'),
          findsOneWidget);
      expect(controller.bandId, isNull);
      // And the step is still finishable — this is the ordinary answer, not an
      // error state.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Add your child'), findsOneWidget);
    });

    testWidgets('retrying starts a NEW scan, not a re-read of the old one',
        (tester) async {
      var scans = 0;
      await tester.pumpWidget(flow(
        OnboardingController(initialLocale: AppLocale.en),
        scanBands: () {
          scans++;
          return Stream.value(const BandScanUpdate(BandScanPhase.noneNearby));
        },
      ));
      await toPairStep(tester);
      expect(scans, 1);

      await tester.tap(find.text('Search again'));
      await tester.pumpAndSettle();
      expect(scans, 2, reason: 'a retry that re-listens to a settled stream '
          'redraws the same answer for ever');
    });
  });

  /// The ids onboarding mints have to be ids the server will accept.
  ///
  /// It used to hand out the literal strings 'child-1', 'home' and 'school'.
  /// POST /children and PUT /children/:id/geofences both require a UUID, so
  /// every one of them was refused with a 400 — and the push is fire-and-
  /// forget, so nothing anywhere said so.
  ///
  /// This is the FIRST child most mothers ever add, and those two zones are
  /// what every "arrived home" and "left school" alert is built on. So the
  /// common path was the one that could never sync: her child was absent from
  /// the back office and from the Dashboard's counts, gone when she changed
  /// phones, and its location could never be fetched.
  group('the ids onboarding produces', () {
    final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

    test('the child gets one the server will take', () {
      final c = OnboardingController()
        ..setDisplayName('Айгерим')
        ..setChildName('Сұлтан')
        ..setHome(const ZoneInput('Дом', 43.2, 76.8));

      final child = c.build().child!;
      expect(child.id, matches(uuid), reason: 'POST /children refuses anything else');
    });

    test('so do the zones every alert is built on', () {
      final c = OnboardingController()
        ..setChildName('Сұлтан')
        ..setHome(const ZoneInput('Дом', 43.2, 76.8))
        ..setSchool(const ZoneInput('Школа', 43.25, 76.95));

      final fences = c.build().child!.geofences;
      expect(fences, hasLength(2));
      for (final f in fences) {
        expect(f.id, matches(uuid), reason: '${f.name} could not sync');
      }
      // Still two DIFFERENT zones, not one id used twice.
      expect(fences[0].id, isNot(fences[1].id));
      expect(fences.map((f) => f.name), ['Дом', 'Школа']);
    });

    test('two mothers setting up do not collide', () {
      ZoneInput home() => const ZoneInput('Дом', 43.2, 76.8);
      OnboardingController set() => OnboardingController()
        ..setChildName('Сұлтан')
        ..setHome(home());

      // Fixed ids meant every account in the database claimed the same child
      // id and the same zone ids.
      expect(set().build().child!.id, isNot(set().build().child!.id));
    });
  });
}
