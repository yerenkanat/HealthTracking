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
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';

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

  // ---- Screens that had no coverage at all ----
  // Twenty of the app's screens were never rendered by this suite. These are
  // the ones where a clipped line does the most damage.

  testWidgets('the emergency screen fits every locale', (tester) async {
    // The screen that matters most, and the one most likely to hold long text:
    // Russian triage copy runs half again as long as the English it was written
    // against, and it now carries the triggering reading underneath.
    await checkAllLocales(
      tester,
      'EmergencyRescueScreen',
      () => EmergencyRescueScreen(
        message: 'Обнаружено высокое давление — признак преэклампсии. '
            'Немедленно свяжитесь с врачом.',
        details: const ['Ваше давление: 152/96 мм рт. ст.'],
        callButtons: const [
          EmergencyCallButton('Вызвать скорую', '103'),
          EmergencyCallButton('Позвонить врачу', '+77011234567'),
        ],
        onCall: (_) async {},
        onDismissConfirmed: () async {},
      ),
    );
  });

  testWidgets('the settings screen fits every locale', (tester) async {
    // Holds the longest body copy in the app — the export warning naming
    // everything inside the backup file.
    await checkAllLocales(tester, 'SettingsScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      return SettingsScreen(controller: c);
    }, scroll: true);
  });

  testWidgets('the profile screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'ProfileScreen', () {
      final c = AppController(now: () => today);
      c.updateProfile(const UserProfile(
        displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233'));
      addTearDown(c.dispose);
      return ProfileScreen(controller: c);
    }, scroll: true);
  });

  testWidgets('the timeline content screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'TimelineContentScreen',
      () => TimelineContentScreen(
        stage: TimelineStage.pregnancyWeek(20),
        items: const [
          ContentItem(
            id: 'l1', kind: ContentKind.lesson,
            title: LocalizedText({'ru': 'Двадцатая неделя беременности: что происходит'}),
            summary: LocalizedText({'ru': 'Подробный разбор изменений и что важно проверить.'}),
            durationMin: 12,
          ),
          ContentItem(
            id: 'p1', kind: ContentKind.product,
            title: LocalizedText({'ru': 'Компрессионные чулки для беременных'}),
            summary: LocalizedText({'ru': 'Помогают при отёках и тяжести в ногах.'}),
            priceMinor: 1290000, currency: 'KZT',
          ),
        ],
        onOpen: (_) {},
      ),
      scroll: true,
    );
  });

  testWidgets('the zones screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'ZonesScreen', () {
      final c = AppController(now: () => today);
      c.configureChild(name: 'Sultan', fences: const []);
      addTearDown(c.dispose);
      return ZonesScreen(controller: c, childId: c.selectedChild!.id);
    }, scroll: true);
  });
}

final List<String> _overflows = [];
