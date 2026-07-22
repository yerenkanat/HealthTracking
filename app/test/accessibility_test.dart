/// Whole-screen accessibility audits using Flutter's own guideline checkers.
///
/// touch_targets_test.dart measures specific controls that were once too small.
/// This is the complement: instead of naming controls, it renders a screen and
/// asks the framework to audit everything on it — tap-target size, contrast,
/// and whether tappables expose a label to a screen reader. A new control that
/// is too small or unlabelled fails here without anyone adding an assertion.
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
import 'package:fcs_app/ui/settings/journey_screen.dart';
import 'package:fcs_app/ui/settings/reminders_center_screen.dart';
import 'package:fcs_app/ui/tracking/alerts_screen.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/sleep_card.dart';
import 'package:fcs_app/ui/dashboard/sleep_detail_screen.dart';
import 'package:fcs_app/ui/dashboard/water_card.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/ui/content/timeline_content_screen.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';
import 'package:fcs_app/ui/profile/profile_screen.dart';
import 'package:fcs_app/ui/settings/settings_screen.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/calendar/cycle_insights_screen.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';
import 'package:fcs_app/ui/calendar/weight_history_screen.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/dashboard/water_history_screen.dart';
import 'package:fcs_app/ui/tracking/child_detail_screen.dart';
import 'package:fcs_app/domain/onboarding_controller.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';
import 'package:fcs_app/ui/tracking/home_safety_screen.dart';
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';
import 'package:fcs_app/ui/settings/legal_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: Scaffold(body: ListView(children: [child])),
        ),
      );

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

  /// Run every guideline the framework offers for a screen.
  Future<void> audit(WidgetTester tester, Widget screen) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  testWidgets('the sleep card meets the accessibility guidelines', (tester) async {
    await audit(tester, wrap(SleepCard(nights: nights, onLog: () {})));
  });

  // The empty state is what a user without a band sees permanently, and its
  // button is their only way into the feature — it has to be reachable.
  testWidgets('the empty sleep card meets the guidelines', (tester) async {
    await audit(tester, wrap(SleepCard(nights: const [], onLog: () {})));
  });

  testWidgets('the sleep detail screen meets the guidelines', (tester) async {
    await audit(
      tester,
      MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: SleepDetailScreen(nights: nights, onLog: () {}),
        ),
      ),
    );
  });

  testWidgets('the water card meets the guidelines', (tester) async {
    await audit(
      tester,
      wrap(WaterCard(count: 3, goal: 8, onAdd: () {}, onRemove: () {}, onSetGoal: (_) {})),
    );
  });

  testWidgets('the weight card meets the guidelines', (tester) async {
    const entries = [
      WeightEntry(date: '2026-07-01', kg: 62.0),
      WeightEntry(date: '2026-07-15', kg: 63.4),
    ];
    await audit(tester, wrap(WeightCard(entries: entries, onLog: (_) {}, onSetGoal: (_) {})));
  });

  testWidgets('the health dashboard meets the guidelines', (tester) async {
    await audit(
      tester,
      MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: HealthDashboardView(
            samples: samples,
            sleepNights: nights,
            greetingName: 'Aigerim',
            onLogVitals: () {},
            onLogSleep: () {},
            onAddWater: () {},
            onRemoveWater: () {},
            onSetWaterGoal: (_) {},
          ),
        ),
      ),
    );
  });

  // With no readings the dashboard shows its empty state instead of the grid —
  // a different tree, and the first thing a new user ever sees.
  testWidgets('the empty dashboard meets the guidelines', (tester) async {
    await audit(
      tester,
      MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: HealthDashboardView(samples: const [], onLogVitals: () {}),
        ),
      ),
    );
  });

  // ---- Controller-driven screens ----
  final today = DateTime(2026, 7, 16);

  Widget screen(Widget child) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: child),
      );

  testWidgets('the medications screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.addMedication('Folic acid', dose: '400 mcg');
    c.addMedication('Iron', dose: '27 mg', perDay: 2);
    await audit(tester, screen(MedicationsScreen(controller: c, now: () => today)));
  });

  testWidgets('the empty medications screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await audit(tester, screen(MedicationsScreen(controller: c, now: () => today)));
  });

  testWidgets('the appointments screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.addAppointment('OB visit', today.add(const Duration(days: 3)));
    await audit(tester, screen(AppointmentsScreen(controller: c)));
  });

  testWidgets('the alerts screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.logChildEvent(AlertKind.sos);
    c.logChildEvent(AlertKind.checkIn);
    await audit(tester, screen(AlertsScreen(controller: c)));
  });

  testWidgets('the reminders centre meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await audit(tester, screen(RemindersCenterScreen(controller: c)));
  });

  testWidgets('the journey screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await audit(tester, screen(JourneyScreen(controller: c)));
  });

  // ---- Screens the audit had never rendered ----

  testWidgets('the emergency screen meets the guidelines', (tester) async {
    // The one screen a user may reach while frightened, possibly one-handed,
    // possibly with a screen reader. Its controls have to be reachable and
    // named even when nothing else is.
    await audit(
      tester,
      screen(EmergencyRescueScreen(
        message: 'Обнаружено высокое давление — признак преэклампсии.',
        details: const ['Ваше давление: 152/96 мм рт. ст.'],
        callButtons: const [
          EmergencyCallButton('Вызвать скорую', '103'),
          EmergencyCallButton('Позвонить врачу', '+77011234567'),
        ],
        onCall: (_) async => true,
        onDismissConfirmed: () async {},
      )),
    );
  });

  testWidgets('the settings screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await audit(tester, screen(SettingsScreen(controller: c)));
  });

  testWidgets('the profile screen meets the guidelines', (tester) async {
    final c = AppController(now: () => today);
    c.updateProfile(const UserProfile(
      displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233'));
    addTearDown(c.dispose);
    await audit(tester, screen(ProfileScreen(controller: c)));
  });

  testWidgets('the timeline content screen meets the guidelines', (tester) async {
    await audit(
      tester,
      screen(TimelineContentScreen(
        stage: TimelineStage.pregnancyWeek(20),
        items: const [
          ContentItem(
            id: 'l1', kind: ContentKind.lesson,
            title: LocalizedText({'en': 'Week 20: what happens'}),
            summary: LocalizedText({'en': 'What changes and what to check.'}),
            durationMin: 12,
          ),
        ],
        onOpen: (_) {},
      )),
    );
  });

  // ---- The rest of the app ----
  // Completing the sweep so every screen is audited by something.

  AppController seededA11y() {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.updateProfile(const UserProfile(
      displayName: 'Aigerim', dialCode: '+7', phoneNumber: '7001112233'));
    c.configureChild(name: 'Sultan', dateOfBirth: DateTime(2024, 3, 4), fences: const []);
    return c;
  }

  testWidgets('the advisor screen meets the guidelines', (tester) async {
    await audit(tester, screen(AdvisorScreen(
        samples: samples, lastNight: nights.first, waterCount: 3, waterGoal: 8)));
  });

  testWidgets('the cycle insights screen meets the guidelines', (tester) async {
    await audit(tester, screen(CycleInsightsScreen(controller: seededA11y(), now: () => today)));
  });

  testWidgets("the women's health screen meets the guidelines", (tester) async {
    await audit(tester, screen(WomensHealthScreen(controller: seededA11y(), now: () => today)));
  });

  testWidgets('the child detail screen meets the guidelines', (tester) async {
    final c = seededA11y();
    await audit(tester, screen(
        ChildDetailScreen(controller: c, childId: c.selectedChild!.id, now: () => today)));
  });

  testWidgets('the water history screen meets the guidelines', (tester) async {
    await audit(tester, screen(WaterHistoryScreen(
      week: [for (var i = 0; i < 7; i++)
        (day: today.subtract(Duration(days: 6 - i)), glasses: 5 + i)],
      goal: 8, streak: 3, now: () => today,
    )));
  });

  testWidgets('the weight history screen meets the guidelines', (tester) async {
    await audit(tester, screen(WeightHistoryScreen(
      entries: const [
        WeightEntry(date: '2026-07-01', kg: 62.0),
        WeightEntry(date: '2026-07-15', kg: 63.4),
      ],
      onDelete: (_) {},
    )));
  });

  testWidgets('the kick session screen meets the guidelines', (tester) async {
    await audit(tester, screen(KickSessionScreen(onSave: (_, __) {})));
  });

  testWidgets('the contraction timer meets the guidelines', (tester) async {
    await audit(tester, screen(ContractionTimerScreen(onSave: (_, __, ___) {})));
  });

  testWidgets('the zones screen meets the guidelines', (tester) async {
    final c = seededA11y();
    await audit(tester, screen(ZonesScreen(controller: c, childId: c.selectedChild!.id)));
  });

  testWidgets('the privacy & terms screens meet the guidelines', (tester) async {
    await audit(tester, screen(const LegalScreen(doc: LegalDoc.privacy)));
    await audit(tester, screen(const LegalScreen(doc: LegalDoc.terms)));
  });

  testWidgets('the antenatal-plan screen meets the guidelines', (tester) async {
    await audit(tester, screen(const AntenatalPlanScreen(week: 28)));
  });

  testWidgets('the home-safety screen meets the guidelines', (tester) async {
    await audit(tester, screen(HomeSafetyScreen(
        ageMonths: 12, done: const {'stair_gates'}, onToggle: (_) {})));
  });

  // Onboarding — the first thing every user sees, audited step by step.
  for (final step in OnboardingStep.values) {
    if (step == OnboardingStep.done) continue;
    testWidgets('onboarding "${step.name}" meets the guidelines', (tester) async {
      final oc = OnboardingController();
      addTearDown(oc.dispose);
      oc.setDisplayName('Aigerim');
      oc.setPhoneNumber('7001112233');
      oc.setChildName('Sultan');
      oc.setHome(const ZoneInput('Дом', 43.238949, 76.889709));
      for (var guard = 0; oc.step != step && guard < 10; guard++) {
        oc.next();
      }
      expect(oc.step, step, reason: 'could not reach $step');
      await audit(tester, screen(OnboardingFlow(controller: oc, onComplete: (_) {})));
    });
  }
}
