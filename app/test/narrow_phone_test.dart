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
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/geofence_alerts.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/calendar/hospital_bag_screen.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';
import 'package:fcs_app/ui/settings/help_support_screen.dart';
import 'package:fcs_app/ui/settings/journey_screen.dart';
import 'package:fcs_app/ui/settings/reminders_center_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/ds_widgets.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';
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
      // copyWith, NOT a fresh MediaQueryData: building one from scratch gives
      // it Size.zero, and a screen that asks MediaQuery for the width then
      // lays out against nothing. The first version of this did exactly that,
      // so every screen here was measured against a zero-size viewport — the
      // sweep looked like it was passing 34 screens and was not testing the
      // width it is named after.
      home: Builder(
        builder: (context) => MediaQuery(
          // The system font-size slider. Its users are not an edge case here —
          // this app is read by pregnant women and by grandmothers minding the
          // children, and Android's accessibility settings go well past this.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: L10nScope(l10n: L10n(locale), child: build()),
        ),
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

    // A screen that rendered nothing cannot overflow, so without this the
    // whole sweep could pass by testing blank pages — a screen whose data
    // failed to load, or a constructor given empty fixtures, would read as
    // "fits". Every screen here shows at least a title and some body copy.
    expect(
      find.byType(Text),
      findsAtLeast(3),
      reason: '$label rendered almost nothing, so "it fits" means nothing',
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

  /// The alerts feed WITH alerts in it.
  ///
  /// An empty feed is one line of placeholder copy and cannot overflow, so
  /// testing it proves nothing about the rows that actually render — which is
  /// what the vacuity check below caught.
  AppController withAlerts() {
    final c = AppController(now: () => now);
    c.mergeRemoteAlerts([
      SafetyAlert(
        kind: AlertKind.left,
        childName: 'Сұлтан',
        // Long, because a zone is named by the parent and "Школа" is the short
        // case, not the normal one.
        zoneName: 'Школа-гимназия №158 имени Абая',
        at: now.subtract(const Duration(minutes: 12)),
      ),
      SafetyAlert(
        kind: AlertKind.entered,
        childName: 'Сұлтан',
        zoneName: 'Дом',
        at: now.subtract(const Duration(hours: 3)),
      ),
      SafetyAlert(
        kind: AlertKind.lowBattery,
        childName: 'Сұлтан',
        zoneName: '15',
        at: now.subtract(const Duration(hours: 5)),
      ),
    ]);
    return c;
  }

  testWidgets('the alerts feed fits', (tester) async {
    final c = withAlerts();
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

  // ---- The screens reached from inside the app ---------------------------
  //
  // Second batch: the ones a user navigates to rather than lands on. The
  // emergency screen leads because it is the only one somebody reads while
  // frightened, and a striped overflow bar across the ambulance number is the
  // worst version of this bug in the product.

  Widget emergency() => EmergencyRescueScreen(
        message: 'Обнаружено высокое давление — признак преэклампсии.',
        details: const ['Ваше давление: 152/96 мм рт. ст.'],
        callButtons: const [
          EmergencyCallButton('Вызвать скорую', '103'),
          EmergencyCallButton('Позвонить врачу', '+77011234567'),
        ],
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      );

  testWidgets('the emergency screen fits', (tester) async {
    await fits(tester, emergency, 'the emergency screen');
  });

  testWidgets('the emergency screen fits at 130%', (tester) async {
    // Whoever has the font size turned up is likelier, not less likely, to be
    // the person who needs this screen legible.
    await fits(tester, emergency, 'the emergency screen', textScale: 1.3);
  });

  testWidgets('the emergency screen fits in Kazakh', (tester) async {
    await fits(tester, emergency, 'the emergency screen (kk)', locale: AppLocale.kk);
  });

  testWidgets('the hospital bag fits', (tester) async {
    await fits(
      tester,
      () => HospitalBagScreen(checked: const {'docs', 'clothes'}, onToggle: (_) {}),
      'the hospital bag',
    );
  });

  testWidgets('labour signs fit', (tester) async {
    await fits(tester, () => const LabourSignsScreen(), 'labour signs');
  });

  testWidgets('labour signs fit at 130%', (tester) async {
    await fits(tester, () => const LabourSignsScreen(), 'labour signs', textScale: 1.3);
  });

  testWidgets('help & support fits', (tester) async {
    await fits(tester, () => const HelpSupportScreen(), 'help & support');
  });

  testWidgets('the journey screen fits', (tester) async {
    // With totals in it. Empty, this screen is one line of placeholder copy
    // that cannot overflow — the tile grid only exists once something has been
    // tracked, and the grid is the part that has to fit.
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    c.setDayLog(const DayLog(date: '2026-07-10', mood: Mood.happy, note: 'хороший день'));
    c.setDayLog(const DayLog(date: '2026-07-11', symptoms: {Symptom.cramps}));
    c.addWater(DateTime(2026, 7, 12), 6);
    await fits(tester, () => JourneyScreen(controller: c), 'the journey screen');
  });

  testWidgets('the journey screen fits at 130%', (tester) async {
    // The tile grid derives its height from the width AND the font scale, so
    // this is the case that formula exists for.
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    c.setDayLog(const DayLog(date: '2026-07-10', mood: Mood.happy, note: 'хороший день'));
    c.setDayLog(const DayLog(date: '2026-07-11', symptoms: {Symptom.cramps}));
    c.addWater(DateTime(2026, 7, 12), 6);
    await fits(tester, () => JourneyScreen(controller: c), 'the journey screen', textScale: 1.3);
  });

  testWidgets('the reminders centre fits', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(tester, () => RemindersCenterScreen(controller: c), 'the reminders centre');
  });

  testWidgets('the reminders centre fits at 130%', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(
      tester,
      () => RemindersCenterScreen(controller: c),
      'the reminders centre',
      textScale: 1.3,
    );
  });

  testWidgets('the kick counter fits', (tester) async {
    await fits(tester, () => KickSessionScreen(onSave: (_, __) {}), 'the kick counter');
  });

  testWidgets('the contraction timer fits', (tester) async {
    await fits(tester, () => const ContractionTimerScreen(), 'the contraction timer');
  });

  testWidgets('the contraction timer fits at 130%', (tester) async {
    // Read during labour, one-handed. Worth the extra case.
    await fits(
      tester,
      () => const ContractionTimerScreen(),
      'the contraction timer',
      textScale: 1.3,
    );
  });

  testWidgets("the child's detail screen fits", (tester) async {
    final c = AppController(now: () => now, locale: AppLocale.ru)
      ..addChild(ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2019, 3, 8)));
    addTearDown(c.dispose);
    await fits(
      tester,
      () => ChildDetailScreen(controller: c, childId: 'c1', now: () => now),
      "the child's detail screen",
    );
  });

  testWidgets("the child's detail screen fits at 130%", (tester) async {
    final c = AppController(now: () => now, locale: AppLocale.ru)
      ..addChild(ChildProfile(id: 'c1', name: 'Сұлтан', dateOfBirth: DateTime(2019, 3, 8)));
    addTearDown(c.dispose);
    await fits(
      tester,
      () => ChildDetailScreen(controller: c, childId: 'c1', now: () => now),
      "the child's detail screen",
      textScale: 1.3,
    );
  });

  testWidgets('the advisor fits', (tester) async {
    await fits(tester, () => const AdvisorScreen(samples: []), 'the advisor');
  });

  testWidgets('onboarding fits', (tester) async {
    // The very first screen anyone sees. It is also the one shown before the
    // user has picked a language, so it must survive both.
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(
      tester,
      () => OnboardingFlow(
        controller: c.onboarding,
        onLocaleChange: c.setLocale,
        onComplete: (_) {},
      ),
      'onboarding',
    );
  });

  testWidgets('onboarding fits at 130%', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await fits(
      tester,
      () => OnboardingFlow(
        controller: c.onboarding,
        onLocaleChange: c.setLocale,
        onComplete: (_) {},
      ),
      'onboarding',
      textScale: 1.3,
    );
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
      final c = withAlerts();
      addTearDown(c.dispose);
      await fits(tester, () => AlertsScreen(controller: c), 'the alerts feed', textScale: 1.3);
    });
  });
}
