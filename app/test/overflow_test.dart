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
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';
import 'package:fcs_app/domain/child_tracker_state.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/calendar/cycle_insights_screen.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';
import 'package:fcs_app/ui/calendar/notes_browser_screen.dart';
import 'package:fcs_app/ui/calendar/symptom_days_screen.dart';
import 'package:fcs_app/ui/calendar/weight_history_screen.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/dashboard/metric_detail_screen.dart';
import 'package:fcs_app/ui/dashboard/water_history_screen.dart';
import 'package:fcs_app/ui/theme.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';
import 'package:fcs_app/ui/tracking/child_safety_screen.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';
import 'package:fcs_app/ui/settings/legal_screen.dart';
import 'package:fcs_app/ui/settings/help_support_screen.dart';
import 'package:fcs_app/ui/calendar/pregnancy_weight_screen.dart';
import 'package:fcs_app/ui/calendar/pregnancy_warnings.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';
import 'package:fcs_app/ui/tracking/safe_sleep_screen.dart';
import 'package:fcs_app/ui/tracking/solids_screen.dart';
import 'package:fcs_app/ui/tracking/child_illness_screen.dart';
import 'package:fcs_app/ui/tracking/teething_screen.dart';
import 'package:fcs_app/ui/tracking/home_safety_screen.dart';
import 'package:fcs_app/ui/tracking/child_emergency_screen.dart';
import 'package:fcs_app/domain/child_emergency.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';

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
      if (scroll && find.byType(Scrollable).evaluate().isNotEmpty) {
        // Some overflow only appears once a lower row is laid out.
        //
        // Guarded because a screen that fits without scrolling has no
        // Scrollable to drag, and `.first` on an empty finder throws "Bad
        // state: No element" — which reads as a failure of the SCREEN when it
        // is a failure of the harness. Asking to scroll something that does
        // not scroll is a no-op, not an error.
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
        onCall: (_) async => true,
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

  // ---- The remaining screens ----
  // Finishing the sweep, so every screen in the app is rendered at 360dp in
  // all three languages by something.

  AppController seeded() {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.updateProfile(const UserProfile(
      displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233'));
    c.configureChild(name: 'Sultan', dateOfBirth: DateTime(2024, 3, 4), fences: const []);
    return c;
  }

  testWidgets('the advisor screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'AdvisorScreen',
      () => AdvisorScreen(samples: samples, lastNight: nights.first, waterCount: 3, waterGoal: 8),
      scroll: true,
    );
  });

  testWidgets('the cycle insights screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'CycleInsightsScreen',
        () => CycleInsightsScreen(controller: seeded(), now: () => today), scroll: true);
  });

  testWidgets("the women's health screen fits every locale", (tester) async {
    await checkAllLocales(tester, 'WomensHealthScreen',
        () => WomensHealthScreen(controller: seeded(), now: () => today), scroll: true);
  });

  testWidgets('the child detail screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'ChildDetailScreen', () {
      final c = seeded();
      return ChildDetailScreen(controller: c, childId: c.selectedChild!.id, now: () => today);
    }, scroll: true);
  });

  testWidgets('the child safety screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'ChildSafetyScreen',
      () => const ChildSafetyScreen(
        childName: 'Sultan', ageMonths: 28, currentZone: 'Дом',
        freshness: Freshness.live, hasLocation: true,
      ),
      scroll: true,
    );
  });

  testWidgets('the water history screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'WaterHistoryScreen',
      () => WaterHistoryScreen(
        week: [for (var i = 0; i < 7; i++) (day: today.subtract(Duration(days: 6 - i)), glasses: 5 + i)],
        goal: 8, streak: 3, now: () => today,
      ),
      scroll: true,
    );
  });

  testWidgets('the weight history screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'WeightHistoryScreen',
      () => WeightHistoryScreen(
        entries: const [
          WeightEntry(date: '2026-07-01', kg: 62.0),
          WeightEntry(date: '2026-07-15', kg: 63.4),
        ],
        onDelete: (_) {},
      ),
      scroll: true,
    );
  });

  testWidgets('the metric detail screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'MetricDetailScreen',
      () => MetricDetailScreen(
        metricKey: 'hr', unit: 'bpm', icon: Icons.favorite_rounded,
        color: Palette.pink, samples: samples,
      ),
      scroll: true,
    );
  });

  testWidgets('the kick session screen fits every locale', (tester) async {
    await checkAllLocales(
        tester, 'KickSessionScreen', () => KickSessionScreen(onSave: (_, __) {}), scroll: true);
  });

  testWidgets('the contraction timer fits every locale', (tester) async {
    await checkAllLocales(
        tester, 'ContractionTimerScreen', () => ContractionTimerScreen(onSave: (_, __, ___) {}),
        scroll: true);
  });

  testWidgets('the notes browser fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'NotesBrowserScreen',
      () => const NotesBrowserScreen(logs: [
        DayLog(date: '2026-07-15', note: 'Чувствовала себя хорошо, гуляла час.'),
      ]),
      scroll: true,
    );
  });

  testWidgets('the symptom days screen fits every locale', (tester) async {
    await checkAllLocales(
      tester,
      'SymptomDaysScreen',
      () => const SymptomDaysScreen(
        logs: [DayLog(date: '2026-07-15', symptoms: {Symptom.cramps})],
        symptom: Symptom.cramps,
      ),
      scroll: true,
    );
  });


  // ---- Onboarding ----
  // The first thing every user sees, and it was in neither suite. Each step is
  // rendered separately: the flow is one widget with five faces, and only the
  // visible one can overflow.
  for (final step in OnboardingStep.values) {
    if (step == OnboardingStep.done) continue; // no UI of its own
    testWidgets('onboarding "${step.name}" fits every locale', (tester) async {
      await checkAllLocales(tester, 'OnboardingFlow.${step.name}', () {
        final oc = OnboardingController();
        addTearDown(oc.dispose);
        // Fill what each step REQUIRES before walking past it. next() is a
        // no-op while canProceed is false, so a bare loop here spins forever —
        // it did, and took the whole suite past its timeout.
        oc.setDisplayName('Aigerim');
        oc.setPhoneNumber('7001112233');
        oc.setChildName('Sultan');
        oc.setHome(const ZoneInput('Дом', 43.238949, 76.889709));
        for (var guard = 0; oc.step != step && guard < 10; guard++) {
          oc.next();
        }
        expect(oc.step, step, reason: 'could not reach ');
        return OnboardingFlow(controller: oc, onComplete: (_) {});
      }, scroll: true);
    });
  }

  // ---- Large accessibility text ----
  //
  // Nothing in the app or its tests had ever considered textScaler. Android and
  // iOS both let a user enlarge every font system-wide, and the people most
  // likely to do it — anyone whose sight is not perfect — are squarely among
  // this app's users. A layout tuned at 1.0 has no reason to survive 1.5.
  //
  // 1.5 rather than the maximum: past that, essentially every mobile layout
  // needs a different design, and pretending otherwise would make this a test
  // nobody can keep passing. This is the setting a real user plausibly picks.
  Future<void> checkScaled(WidgetTester tester, String name, Widget Function() build,
      {double scale = 1.5, bool scroll = false}) async {
    _overflows.clear();
    tester.view.physicalSize = _smallPhone;
    tester.view.devicePixelRatio = 1.0;
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
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        // Russian: the default language AND the longest strings, so this is the
        // combination a real user is most likely to be in.
        child: L10nScope(l10n: const L10n(AppLocale.ru), child: build()),
      ),
    ));
    await tester.pumpAndSettle();
    if (scroll && find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    FlutterError.onError = previous;
    expect(_overflows, isEmpty,
        reason: '$name overflowed at ${scale}x text in Russian:\n  ${_overflows.join('\n  ')}');
  }

  testWidgets('the emergency screen survives large text', (tester) async {
    // The screen someone with poor sight most needs to read.
    await checkScaled(
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
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      ),
    );
  });

  testWidgets('the dashboard survives large text', (tester) async {
    await checkScaled(
      tester,
      'HealthDashboardView',
      () => HealthDashboardView(
        samples: samples, sleepNights: nights, greetingName: 'Aigerim',
        awaitingRepeat: 'bp', onLogVitals: () {}, onLogSleep: () {},
        onAddWater: () {}, onRemoveWater: () {}, onSetWaterGoal: (_) {},
      ),
      scroll: true,
    );
  });

  testWidgets('the settings screen survives large text', (tester) async {
    await checkScaled(tester, 'SettingsScreen', () {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      return SettingsScreen(controller: c);
    }, scroll: true);
  });

  testWidgets('onboarding survives large text', (tester) async {
    for (final step in [OnboardingStep.welcome, OnboardingStep.profile, OnboardingStep.child]) {
      await checkScaled(tester, 'OnboardingFlow.${step.name}', () {
        final oc = OnboardingController();
        addTearDown(oc.dispose);
        oc.setDisplayName('Aigerim');
        oc.setPhoneNumber('7001112233');
        oc.setChildName('Sultan');
        oc.setHome(const ZoneInput('Дом', 43.238949, 76.889709));
        for (var g = 0; oc.step != step && g < 10; g++) {
          oc.next();
        }
        return OnboardingFlow(controller: oc, onComplete: (_) {});
      }, scroll: true);
    }
  });

  // ---- The guides and records added this session ----
  testWidgets('the postpartum screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'PostpartumScreen',
        () => PostpartumScreen(birthDate: DateTime(2026, 6, 20), today: today), scroll: true);
  });

  testWidgets('the pregnancy weight guide fits every locale', (tester) async {
    await checkAllLocales(tester, 'PregnancyWeightScreen',
        () => const PregnancyWeightScreen(weeklyRateKg: 0.42), scroll: true);
  });

  testWidgets('the pregnancy warnings screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'PregnancyWarningsScreen', () => const PregnancyWarningsScreen(), scroll: true);
  });

  testWidgets('the signs-of-labour screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'LabourSignsScreen', () => const LabourSignsScreen(), scroll: true);
  });

  testWidgets('the safe-sleep screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'SafeSleepScreen', () => const SafeSleepScreen(), scroll: true);
  });

  testWidgets('the solids screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'SolidsScreen', () => const SolidsScreen(ageMonths: 8), scroll: true);
  });

  testWidgets('the child-illness screen fits every locale', (tester) async {
    // Age 1 so the under-3-months fever banner renders too.
    await checkAllLocales(tester, 'ChildIllnessScreen', () => const ChildIllnessScreen(ageMonths: 1), scroll: true);
  });

  testWidgets('the teething screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'TeethingScreen', () => const TeethingScreen(ageMonths: 7), scroll: true);
  });

  testWidgets('the help & support screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'HelpSupportScreen',
        () => const HelpSupportScreen(diagnostics: 'locale ru'), scroll: true);
  });

  testWidgets('the legal screens fit every locale', (tester) async {
    await checkAllLocales(tester, 'LegalScreen_privacy',
        () => const LegalScreen(doc: LegalDoc.privacy), scroll: true);
    await checkAllLocales(tester, 'LegalScreen_terms',
        () => const LegalScreen(doc: LegalDoc.terms), scroll: true);
  });

  testWidgets('the antenatal-plan screen fits every locale', (tester) async {
    // Week 11: visit 1 leads and is expanded by default — its 24 items include
    // the longest labels (aspirin, anti-D). The widest content on the screen.
    await checkAllLocales(
        tester, 'AntenatalPlanScreen_w11', () => const AntenatalPlanScreen(week: 11),
        scroll: true);
    // Week 28: the OGTT and anti-D windows are open, exercising the rose
    // windows block and the risk tags.
    await checkAllLocales(
        tester, 'AntenatalPlanScreen_w28', () => const AntenatalPlanScreen(week: 28),
        scroll: true);
  });

  testWidgets('the home-safety screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'HomeSafetyScreen',
        () => HomeSafetyScreen(ageMonths: 12, done: const {'stair_gates'}, onToggle: (_) {}), scroll: true);
  });

  testWidgets('the emergency-info screen fits every locale', (tester) async {
    await checkAllLocales(tester, 'ChildEmergencyScreen',
        () => ChildEmergencyScreen(
              childName: 'Сұлтан',
              info: const ChildEmergencyInfo(
                allergies: 'Арахис, пенициллин', conditions: 'Астма', bloodType: 'A+',
                doctorName: 'Др. Алиева', doctorPhone: '+7 700 000 0000',
                contactName: 'Бабушка', contactPhone: '+7 700 111 1111',
              ),
              onSave: (_) {},
            ),
        scroll: true);
  });

  testWidgets('the emergency-info edit form fits every locale', (tester) async {
    // Open the edit form (the invite → form path) and check it too.
    await checkAllLocales(tester, 'ChildEmergencyScreen (empty invite)',
        () => ChildEmergencyScreen(childName: 'Сұлтан', info: const ChildEmergencyInfo(), onSave: (_) {}), scroll: true);
  });

  testWidgets('the activity & wellness dashboard panel fits every locale', (tester) async {
    await checkAllLocales(tester, 'Dashboard (activity panel)', () {
      return HealthDashboardView(
        samples: samples,
        wearable: WearableMetrics(
          at: today, steps: 12345, meters: 8200, kcal: 640, sleepMinutes: 465,
          stress: 34, breathRate: 15, bloodSugarTenths: 55, worn: false,
        ),
      );
    }, scroll: true);
  });
}

final List<String> _overflows = [];
