/// Every main screen on a 360dp phone.
///
/// The goldens all render at 402dp — an iPhone 14 Pro — and the widget tests
/// use viewports up to 1000dp wide and 12000dp tall so nothing ever runs out of
/// room. Nothing in the suite rendered the app at 360dp, which is the width of
/// the cheap Android phones this product is actually sold to, and the width the
/// clipped-headline screenshot came from.
///
/// A horizontal overflow is not a cosmetic diff: Flutter paints the yellow-and-
/// black barber pole over the content, so a row that does not fit destroys the
/// screen rather than degrading it. Two-pixel borders and outlined chips make
/// every row wider than it used to be, so this whole class of failure was
/// introduced by the design-system conversion and had nothing watching for it.
///
/// The check is simply "did Flutter report an overflow", which is what
/// tester.takeException() carries — so this fails for the real reason and names
/// the widget, rather than comparing an image.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/domain/battery.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/tracking/child_map_screen.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';

/// A Redmi/Galaxy A-series in portrait: the floor this app has to fit.
const double kNarrowWidth = 360;
const double kNarrowHeight = 640;

void main() {
  final today = DateTime.utc(2026, 7, 15);
  final now = DateTime.utc(2026, 7, 15, 9, 0);
  final home = Geofence.circle('home', 'Дом', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'Школа', const Coordinates(43.25, 76.95), 120);

  /// Render [build] at 360x640 and fail if anything overflowed.
  ///
  /// The viewport is a REAL phone's, not the tall one the golden tests use:
  /// a 12000dp-high surface hides every vertical overflow there is, which is
  /// precisely what let these through.
  Future<void> fits(
    WidgetTester tester,
    Widget Function() build,
    String label, {
    AppLocale locale = AppLocale.ru,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(kNarrowWidth * 3, kNarrowHeight * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FcsTheme.light(locale),
      home: MediaQuery(
        // The system font-size slider. Its users are not an edge case here —
        // this app is read by pregnant women and by grandmothers minding the
        // children, and Android's accessibility settings go well past this.
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: L10nScope(l10n: L10n(locale), child: build()),
      ),
    ));
    await tester.pumpAndSettle();

    final err = tester.takeException();
    expect(
      err,
      isNull,
      reason: '$label overflows at ${kNarrowWidth.toInt()}dp'
          '${textScale == 1.0 ? '' : ' with text at ${(textScale * 100).round()}%'}'
          ' — the striped overflow bar covers this screen on a cheap Android '
          'phone.\n$err',
    );
  }

  testWidgets('the home dashboard fits', (tester) async {
    final samples = [
      for (var i = 0; i < 12; i++)
        HealthSample(
          at: DateTime.utc(2026, 7, 15, 8, i * 5),
          heartRate: 70 + i % 7,
          spo2: 97 + i % 2,
          coreTemp: 36.5 + (i % 3) * 0.1,
        ),
    ];
    await fits(
      tester,
      () => HealthDashboardView(
        samples: samples,
        // A long name on a narrow screen: the greeting is the widest single
        // line on this screen and the first thing to run out of room.
        greetingName: 'Айгерім-Гүлнұр',
        sleepNights: [
          SleepSummary(night: today, deepMin: 95, remMin: 70, lightMin: 280, awakeMin: 12),
        ],
        wearable: WearableMetrics(
          at: now, steps: 8200, meters: 6100, kcal: 420,
          sleepMinutes: 465, stress: 34, breathRate: 15, worn: true,
        ),
      ),
      'the home dashboard',
    );
  });

  testWidgets('the child map fits', (tester) async {
    // The densest screen in the app: floating pills, a battery chip and two
    // action buttons over a map, and the one whose action row already
    // overflowed once when the borders went from 1px to 2px.
    await fits(
      tester,
      () => ChildMapScreen(
        childName: 'Сұлтан',
        childLocation: school.center,
        updatedAt: now.subtract(const Duration(minutes: 1)),
        fences: [home, school],
        now: now,
        mapBuilder: (_, __, ___) => const DsMapPlaceholder(caption: 'map', height: 300),
        batteryPct: 68,
        batteryHistory: const <BatteryReading>[],
        zoneEnteredAt: now.subtract(const Duration(minutes: 40)),
        lastCheckInAt: now.subtract(const Duration(hours: 2)),
        onCheckIn: () {},
        onSos: () {},
      ),
      'the child map',
    );
  });

  testWidgets('safe zones fit', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => ZonesScreen(controller: c, childId: 'demo'), 'safe zones');
  });

  testWidgets('the alerts feed fits', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => AlertsScreen(controller: c), 'the alerts feed');
  });

  testWidgets("women's health fits in cycle mode", (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (cycle)",
    );
  });

  testWidgets("women's health fits in pregnancy mode", (tester) async {
    final c = AppController(now: () => today)..setDueDate(today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (pregnancy)",
    );
  });

  testWidgets('the profile fits', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => ProfileScreen(controller: c), 'the profile');
  });

  testWidgets('settings fit', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => SettingsScreen(controller: c), 'settings');
  });

  testWidgets('the profile fits in Kazakh too', (tester) async {
    // Kazakh is the longer language almost everywhere — "Хабарландырулар"
    // against "Уведомления" — so a row that just fits in Russian is the normal
    // way a Kazakh screen breaks.
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => ProfileScreen(controller: c), 'the profile (kk)', locale: AppLocale.kk);
  });

  testWidgets('settings fit in Kazakh too', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => SettingsScreen(controller: c), 'settings (kk)', locale: AppLocale.kk);
  });

  // ---- 360dp with the font-size slider turned up -------------------------
  //
  // The combination that actually breaks layouts: the narrowest screen and the
  // largest text. Anything that only just fitted above has no room left here.
  group('with the system font size at 130%', () {
    testWidgets('the home dashboard still fits', (tester) async {
      await fits(
        tester,
        () => HealthDashboardView(
          samples: [
            for (var i = 0; i < 12; i++)
              HealthSample(
                at: DateTime.utc(2026, 7, 15, 8, i * 5),
                heartRate: 70 + i % 7, spo2: 97 + i % 2, coreTemp: 36.5 + (i % 3) * 0.1,
              ),
          ],
          greetingName: 'Айгерім-Гүлнұр',
          sleepNights: [
            SleepSummary(night: today, deepMin: 95, remMin: 70, lightMin: 280, awakeMin: 12),
          ],
          wearable: WearableMetrics(
            at: now, steps: 8200, meters: 6100, kcal: 420,
            sleepMinutes: 465, stress: 34, breathRate: 15, worn: true,
          ),
        ),
        'the home dashboard',
        textScale: 1.3,
      );
    });

    testWidgets('the child map still fits', (tester) async {
      await fits(
        tester,
        () => ChildMapScreen(
          childName: 'Сұлтан',
          childLocation: school.center,
          updatedAt: now.subtract(const Duration(minutes: 1)),
          fences: [home, school],
          now: now,
          mapBuilder: (_, __, ___) => const DsMapPlaceholder(caption: 'map', height: 300),
          batteryPct: 68,
          batteryHistory: const <BatteryReading>[],
          zoneEnteredAt: now.subtract(const Duration(minutes: 40)),
          lastCheckInAt: now.subtract(const Duration(hours: 2)),
          onCheckIn: () {},
          onSos: () {},
        ),
        'the child map',
        textScale: 1.3,
      );
    });

    testWidgets("women's health still fits in pregnancy mode", (tester) async {
      final c = AppController(now: () => today)..setDueDate(today.add(const Duration(days: 140)));
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        "women's health (pregnancy)",
        textScale: 1.3,
      );
    });

    testWidgets('the profile still fits', (tester) async {
      final c = AppController(now: () => now);
      addTearDown(c.dispose);
      await fits(tester, () => ProfileScreen(controller: c), 'the profile', textScale: 1.3);
    });

    testWidgets('settings still fit', (tester) async {
      final c = AppController(now: () => now);
      addTearDown(c.dispose);
      await fits(tester, () => SettingsScreen(controller: c), 'settings', textScale: 1.3);
    });

    testWidgets('the alerts feed still fits', (tester) async {
      final c = AppController(now: () => now);
      addTearDown(c.dispose);
      await fits(tester, () => AlertsScreen(controller: c), 'the alerts feed', textScale: 1.3);
    });
  });
}
