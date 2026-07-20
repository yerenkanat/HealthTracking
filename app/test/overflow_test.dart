/// Layout overflow across locales, on a small screen.
///
/// The UI is written and eyeballed in English, but the app ships with Russian
/// as its DEFAULT and Kazakh alongside. 422 of 701 Russian strings are longer
/// than their English source and 193 keys exceed 140% of the English length —
/// "Reset" is 14 characters in English and 36 in Russian. A row that fits in
/// English can therefore overflow in the language most users actually see.
///
/// Everything here renders at 360x640 logical pixels, a common budget Android
/// size, because overflow shows up at the small end and that is the hardware
/// this app is aimed at.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/domain/weight.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/appointments/appointments_screen.dart';
import 'package:fcs_app/ui/calendar/medications_screen.dart';
import 'package:fcs_app/ui/calendar/weight_card.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/sleep_card.dart';
import 'package:fcs_app/ui/dashboard/sleep_detail_screen.dart';
import 'package:fcs_app/ui/dashboard/water_card.dart';
import 'package:fcs_app/ui/settings/journey_screen.dart';
import 'package:fcs_app/ui/settings/reminders_center_screen.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';

/// A small-but-real phone: 360x640 dp.
const _smallPhone = Size(360, 640);

void main() {
  final today = DateTime(2026, 7, 16);

  final samples = [
    for (var i = 0; i < 8; i++)
      HealthSample(
        at: DateTime(2026, 7, 15, 8 + i),
        heartRate: 72 + i.toDouble(),
        spo2: 97,
        systolic: 118,
        diastolic: 76,
        coreTemp: 36.6,
      ),
  ];
  final nights = [
    SleepSummary(night: DateTime(2026, 7, 15), deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25),
    SleepSummary(night: DateTime(2026, 7, 14), deepMin: 70, remMin: 90, lightMin: 250, awakeMin: 35),
  ];

  setUp(() {
    // A fresh error list per test; overflow is reported through FlutterError.
    _overflows.clear();
  });

  /// Render [build] at a small size in every shipped locale and fail listing
  /// any locale that overflowed.
  Future<void> checkAllLocales(
    WidgetTester tester,
    String name,
    Widget Function() build, {
    bool scroll = false,
  }) async {
    final failures = <String>[];
    for (final locale in AppLocale.values) {
      _overflows.clear();
      tester.view.physicalSize = _smallPhone * tester.view.devicePixelRatio;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = _smallPhone;
      addTearDown(tester.view.reset);

      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('overflowed')) {
          _overflows.add(text.split('\n').first);
        } else {
          previous?.call(details);
        }
      };
      // A UniqueKey forces a fresh element tree per locale. Reusing one lets
      // Flutter update the existing render objects in place, and it only
      // re-reports an overflow when the amount CHANGES — so the second and
      // third locales looked clean when they were overflowing identically.
      await tester.pumpWidget(
        MaterialApp(key: UniqueKey(), home: L10nScope(l10n: L10n(locale), child: build())),
      );
      await tester.pumpAndSettle();
      if (scroll) {
        // Some overflow only appears once a lower row is laid out.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      FlutterError.onError = previous;

      if (_overflows.isNotEmpty) {
        failures.add('${locale.name}: ${_overflows.first}');
      }
    }
    expect(failures, isEmpty,
        reason: '$name overflowed at ${_smallPhone.width.toInt()}x'
            '${_smallPhone.height.toInt()} in:\n  ${failures.join('\n  ')}');
  }

  Widget card(Widget child) => Scaffold(body: ListView(children: [child]));

  testWidgets('sleep card fits every locale', (tester) async {
    await checkAllLocales(tester, 'SleepCard', () => card(SleepCard(nights: nights, onLog: () {})));
  });

  testWidgets('empty sleep card fits every locale', (tester) async {
    await checkAllLocales(
        tester, 'SleepCard (empty)', () => card(SleepCard(nights: const [], onLog: () {})));
  });

  testWidgets('sleep detail fits every locale', (tester) async {
    await checkAllLocales(
        tester, 'SleepDetailScreen', () => SleepDetailScreen(nights: nights, onLog: () {}));
  });

  testWidgets('water card fits every locale', (tester) async {
    await checkAllLocales(tester, 'WaterCard',
        () => card(WaterCard(count: 3, goal: 8, onAdd: () {}, onRemove: () {}, onSetGoal: (_) {})));
  });

  testWidgets('weight card fits every locale', (tester) async {
    const entries = [
      WeightEntry(date: '2026-07-01', kg: 62.0),
      WeightEntry(date: '2026-07-15', kg: 63.4),
    ];
    await checkAllLocales(tester, 'WeightCard',
        () => card(WeightCard(entries: entries, onLog: (_) {}, onSetGoal: (_) {})));
  });

  testWidgets('dashboard fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'HealthDashboardView',
      () => HealthDashboardView(
        samples: samples,
        sleepNights: nights,
        greetingName: 'Aigerim',
        onLogVitals: () {},
        onLogSleep: () {},
        onAddWater: () {},
        onRemoveWater: () {},
        onSetWaterGoal: (_) {},
      ),
      scroll: true,
    );
  });

  testWidgets('empty dashboard fits every locale', (tester) async {
    await checkAllLocales(tester, 'HealthDashboardView (empty)',
        () => HealthDashboardView(samples: const [], onLogVitals: () {}));
  });

  testWidgets('the repeat-reading prompt fits every locale', (tester) async {
    // The longest body copy on the dashboard, and it appears at the moment a
    // user is most likely to be anxious — a clipped sentence here reads far
    // worse than one anywhere else.
    await checkAllLocales(
      tester,
      'HealthDashboardView (awaiting a repeat reading)',
      () => HealthDashboardView(
        samples: samples,
        greetingName: 'Aigerim',
        awaitingRepeat: 'bp',
        onLogVitals: () {},
      ),
      scroll: true,
    );
  });

  testWidgets('medications screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'MedicationsScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      c.addMedication('Folic acid', dose: '400 mcg');
      c.addMedication('Iron', dose: '27 mg', perDay: 2);
      return MedicationsScreen(controller: c, now: () => today);
    });
  });

  testWidgets('appointments screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'AppointmentsScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      c.addAppointment('Приём у врача-гинеколога', today.add(const Duration(days: 3)));
      return AppointmentsScreen(controller: c);
    });
  });

  testWidgets('alerts screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'AlertsScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      c.logChildEvent(AlertKind.sos);
      c.logChildEvent(AlertKind.checkIn);
      return AlertsScreen(controller: c);
    });
  });

  testWidgets('reminders centre fits every locale', (tester) async {
    await checkAllLocales(tester, 'RemindersCenterScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      return RemindersCenterScreen(controller: c);
    });
  });

  testWidgets('journey screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'JourneyScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      return JourneyScreen(controller: c);
    });
  });
}

final List<String> _overflows = [];
