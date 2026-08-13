/// The manual diary must not delete its own front door.
///
/// Screen 05 is «Записывайте вручную» — four buttons and a тонометр camera —
/// and it was gated on `samples.isEmpty`. Hand-typed readings go into the same
/// store as band telemetry, so the very first reading she entered made
/// `samples` non-empty and took the whole card off the screen: the four
/// buttons that had just taken it, the camera, and the sleep entry. What was
/// left was one unlabelled `add_chart` icon in the app bar.
///
/// So the feature deleted itself at the exact moment it started being used, for
/// exactly the users it exists for — «Без устройства приложение полноценно»,
/// and for most of them that is the permanent state of this app.
///
/// These tests drive the real path: a real [AppController], a real
/// [ManualVitals] logged through [AppController.logManualVitals], and the
/// controller's own `samples` handed to the dashboard. Nothing here constructs
/// a HealthSample by hand — the whole defect lived in the fact that a typed
/// reading is indistinguishable from a measured one unless you ask.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/manual_vitals.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';

void main() {
  // The four entries of screen 05, in English.
  const chips = ['Pressure', 'Pulse', 'Weight', 'Sleep'];

  setUp(() {
    // Tall enough that the whole page is laid out and built. A ListView only
    // builds what is near the viewport, and "the card is absent" and "the card
    // was never built" are the same finder result — which would make the
    // negative assertions below pass for the wrong reason.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required List<HealthSample> samples,
    List<SleepSummary> sleepNights = const [],
  }) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // L10nScope ABOVE MaterialApp: below the Navigator it does not reach a
    // pushed route, and this screen pushes.
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: HealthDashboardView(
          samples: samples,
          sleepNights: sleepNights,
          onLogVitals: () {},
          onLogWeight: () {},
          onLogSleep: () {},
        ),
      ),
    ));
    await tester.pump();
  }

  /// One hand-typed blood pressure, through the real logging path.
  List<HealthSample> typedOneReading() {
    final c = AppController(now: () => DateTime(2026, 8, 14, 9));
    final ok = c.logManualVitals(
        const ManualVitals(systolic: 118, diastolic: 76, heartRate: 70));
    expect(ok, isTrue, reason: 'the reading must actually have been accepted');
    final samples = [...c.samples];
    expect(samples, hasLength(1),
        reason: 'a typed reading lands in the SAME store as band telemetry — '
            'which is the whole reason samples.isEmpty was the wrong question');
    addTearDown(c.dispose);
    return samples;
  }

  testWidgets('with nothing logged, the four manual entries are on the screen',
      (tester) async {
    await pumpDashboard(tester, samples: const []);
    for (final chip in chips) {
      expect(find.text(chip), findsOneWidget, reason: '«$chip» is missing');
    }
  });

  testWidgets('after her FIRST hand-typed reading they are all still there',
      (tester) async {
    // THE regression. Before the fix every one of these found nothing.
    await pumpDashboard(tester, samples: typedOneReading());
    for (final chip in chips) {
      expect(find.text(chip), findsOneWidget,
          reason: '«$chip» disappeared the moment she used it — the manual '
              'diary deleting its own front door');
    }
    // And her reading is charted, so the card sits above her own numbers
    // rather than replacing them.
    expect(find.text('VITAL SIGNS'), findsOneWidget);
  });

  testWidgets('the тонометр camera survives the first reading too',
      (tester) async {
    // The dark card is offered only when there is a server to read the photo,
    // so it is driven by its own callback rather than by the sample list.
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(L10nScope(
      l10n: const L10n(AppLocale.en),
      child: MaterialApp(
        home: HealthDashboardView(
          samples: typedOneReading(),
          onLogVitals: () {},
          onLogWeight: () {},
          onLogSleep: () {},
          onScanMonitor: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Photograph your monitor'), findsOneWidget);
  });

  testWidgets('a reading off a band still replaces the card with the grid',
      (tester) async {
    // The other half of the fix: the card is for a woman whose readings are her
    // own. A band supplying them is exactly when it should step aside, and this
    // is the assertion that stops "always show it" passing as a fix.
    await pumpDashboard(tester, samples: [
      HealthSample(
        at: DateTime(2026, 8, 14, 9),
        heartRate: 72,
        spo2: 98,
        source: ReadingSource.sensor,
      ),
    ]);
    expect(find.text('VITAL SIGNS'), findsOneWidget);
    // The card's own heading is the unambiguous witness.
    expect(find.text('Log it yourself'), findsNothing,
        reason: 'the manual-entry card is showing over band readings');
    // «Сон» is deliberately not in this list: with a band supplying readings
    // the SleepCard is on the page and its title is also "Sleep", so its
    // absence would be asserting the wrong widget.
    for (final chip in const ['Pressure', 'Pulse', 'Weight']) {
      expect(find.text(chip), findsNothing,
          reason: '«$chip» is the manual card, shown over band readings');
    }
  });

  testWidgets('the card says something that is true for the person reading it',
      (tester) async {
    // With nothing logged it introduces the app. That sentence answers a
    // question about buying a band.
    await pumpDashboard(tester, samples: const []);
    expect(
        find.text(
            'The app works without a band: the diary, the calendars and the reminders are all the same.'),
        findsOneWidget);

    // Once she has been typing readings, that question is settled, and the
    // useful sentence is where the readings went. Repeating the introduction
    // over her own numbers every morning is addressed to nobody.
    await pumpDashboard(tester, samples: typedOneReading());
    expect(
        find.text('Your readings are in the diary and the calendars. Add another:'),
        findsOneWidget);
    expect(
        find.text(
            'The app works without a band: the diary, the calendars and the reminders are all the same.'),
        findsNothing);
    // The heading is true either way and does not move.
    expect(find.text('Log it yourself'), findsOneWidget);
  });

  testWidgets('«Сон» is offered once, not twice', (tester) async {
    // The sleep card's own gate said `samples.isNotEmpty` and MEANT "the manual
    // card is not on screen". Left as it was, one typed blood pressure put a
    // sleep entry in the manual card AND a log-sleep button six lines below it.
    await pumpDashboard(tester, samples: typedOneReading());
    expect(find.text('Sleep'), findsOneWidget);
  });

  testWidgets('a night she has logged still gets its card', (tester) async {
    // Suppressing the sleep card must not cost her the nights she recorded.
    await pumpDashboard(
      tester,
      samples: typedOneReading(),
      sleepNights: [
        SleepSummary(
            night: DateTime(2026, 8, 13),
            deepMin: 95,
            remMin: 70,
            lightMin: 280,
            awakeMin: 0),
      ],
    );
    expect(find.text('Last night'), findsOneWidget);
  });
}
