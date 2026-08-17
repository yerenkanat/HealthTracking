/// Hand entry of vitals is GONE from the app, and the manual PROVENANCE is not.
///
/// Owner's decision, 2026-08-17: users do not type readings; the watch measures
/// them. Five routes were removed together —
///
///   · the «Записывайте вручную» card and its four chips (Давление, Пульс,
///     Вес, Сон),
///   · the dark «Сфотографировать тонометр» card,
///   · the dashboard app-bar «Записать показатели» icon,
///   · the typed-vitals sheet those three opened,
///   · the `/vitals/extract` photo path that pre-filled it.
///
/// This file replaces test/manual_diary_front_door_test.dart, which asserted the
/// exact opposite — that the card must survive her first typed reading. That
/// test was right about the defect it was written for and is now wrong about the
/// product, so it is inverted rather than deleted: the same screens, the same
/// real [AppController], the same finders, the other verdict.
///
/// THE SECOND HALF IS THE IMPORTANT ONE. Removing the entry path is not the same
/// as removing the concept. Rows already on real phones are labelled
/// [ReadingSource.manual], `/vitals/manual` restores them onto a new device, and
/// provenance still decides what may be graded, coloured, put in a visit summary
/// and escalated on. If a later cleanup deletes [AppController.logManualVitals]
/// and the branches behind it, every reading a user has already typed is
/// silently re-graded as a wrist estimate — and the tests below are what notices.
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
  // The four entries of the deleted card, in English.
  const chips = ['Pressure', 'Pulse', 'Weight', 'Sleep'];

  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required List<HealthSample> samples,
    List<SleepSummary> sleepNights = const [],
    bool wireSleep = true,
  }) async {
    // Tall enough that the whole page is laid out and built. A ListView only
    // builds what is near the viewport, and "the card is absent" and "the card
    // was never built" are the same finder result — which would make the
    // negative assertions below pass for the wrong reason.
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
          onLogWeight: () {},
          onLogSleep: wireSleep ? () {} : null,
        ),
      ),
    ));
    await tester.pump();
  }

  /// One hand-typed blood pressure, through the real logging path — which is
  /// still the path a restored row takes its shape from.
  List<HealthSample> typedOneReading() {
    final c = AppController(now: () => DateTime(2026, 8, 14, 9));
    final ok = c.logManualVitals(
        const ManualVitals(systolic: 118, diastolic: 76, heartRate: 70));
    expect(ok, isTrue, reason: 'the reading must actually have been accepted');
    final samples = [...c.samples];
    expect(samples, hasLength(1));
    addTearDown(c.dispose);
    return samples;
  }

  group('the entry surface is gone', () {
    testWidgets('with nothing logged, none of the four chips are offered',
        (tester) async {
      await pumpDashboard(tester, samples: const [], wireSleep: false);
      for (final chip in chips) {
        expect(find.text(chip), findsNothing,
            reason: '«$chip» is a manual-entry chip and should be gone');
      }
      expect(find.text('Log it yourself'), findsNothing);
    });

    testWidgets('the тонометр camera card is gone', (tester) async {
      await pumpDashboard(tester, samples: const [], wireSleep: false);
      expect(find.text('Photograph your monitor'), findsNothing);
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    });

    testWidgets('the app bar has no «Log a reading» action', (tester) async {
      await pumpDashboard(tester, samples: typedOneReading());
      expect(find.byIcon(Icons.add_chart_rounded), findsNothing);
      expect(find.byTooltip(const L10n(AppLocale.en).t('vitals_log')),
          findsNothing);
    });

    testWidgets('nor after a reading has been recorded', (tester) async {
      // The removed card was gated on provenance, so "a manual reading exists"
      // was the state that used to bring the whole surface back.
      await pumpDashboard(tester, samples: typedOneReading());
      for (final chip in const ['Pressure', 'Pulse', 'Weight']) {
        expect(find.text(chip), findsNothing);
      }
      expect(find.text('Log it yourself'), findsNothing);
      expect(find.text('Photograph your monitor'), findsNothing);
    });
  });

  group('what the removal must NOT have taken with it', () {
    testWidgets('a recorded reading is still charted', (tester) async {
      await pumpDashboard(tester, samples: typedOneReading());
      expect(find.text('VITAL SIGNS'), findsOneWidget);
    });

    test('a typed reading keeps its manual provenance', () {
      // The load-bearing one. `HealthSample.fromJson` reads an absent source as
      // a device estimate ON PURPOSE, so if the manual label ever stopped being
      // written, every stored row would quietly become a wrist estimate.
      final s = typedOneReading().single;
      expect(s.source, ReadingSource.manual);
      expect(s.isDeviceEstimate, isFalse);
    });

    test('and provenance still governs what may be graded', () {
      // 118/76 from a cuff is gradeable; the same numbers off a wrist are not.
      // This is the rule that would be silently reversed by "tidying up" the
      // manual branch along with the entry path.
      final typed = typedOneReading().single;
      expect(latestSourceFor([typed], 'systolic'), ReadingSource.manual);
      final wrist = HealthSample(
        at: DateTime(2026, 8, 14, 9),
        systolic: 118,
        diastolic: 76,
        source: ReadingSource.sensor,
      );
      expect(wrist.isDeviceEstimate, isTrue);
    });

    testWidgets('sleep can still be logged with no band and no nights',
        (tester) async {
      // «Сон» was one of the four chips, and the sleep card used to hide itself
      // whenever that card was on screen. Removing the card without widening
      // the sleep gate would have taken sleep logging away from every user
      // without a paired watch — collateral damage, not the decision.
      await pumpDashboard(tester, samples: const []);
      expect(find.text('Log sleep'), findsOneWidget);
    });

    testWidgets('a night she has recorded still gets its card', (tester) async {
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
  });
}
