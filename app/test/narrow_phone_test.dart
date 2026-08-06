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
///
/// Every screen is given REAL data. An empty list cannot overflow, so a screen
/// rendered in its empty state passes while testing nothing — two did exactly
/// that until the vacuity check in [fits] caught them. Fixtures are long for
/// the same reason: a medication is typed off a pharmacy label and a safe zone
/// is named by the parent, so "Школа" is the short case, not the normal one.
///
/// The modal sheets are covered too, via [sheetFits], and were worth it: the
/// day-log sheet held the worst overflow in the app at 69px. A sheet is laid
/// out against a partial height it asks for itself, so a row that fits the
/// whole screen can still not fit there.
///
/// The assistant chat and the cry insight screen are covered too, over stubbed
/// transports — their overflows were the sixth and seventh this sweep found.
/// Every screen and sheet in the app is now in here.
///
/// Two things overflow cannot catch, and which are checked here anyway:
///   * a screen with more than one state proves only the state it opened in,
///     so [fits] takes an `afterPump` to tap into the others — the Calendar
///     tab's three calendars are three different screens behind one widget;
///   * a label that ELLIPSISES has degraded gracefully as far as the overflow
///     check is concerned, while «Беременность» rendered as «Беременно…» is a
///     control nobody can identify. That one is asserted structurally.
library;

import 'dart:convert';

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/cry_classifier_client.dart';
import 'package:fcs_app/data/cry_recorder.dart';
import 'package:fcs_app/domain/cry_analysis.dart';
import 'package:fcs_app/ui/tracking/cry_insight_screen.dart';
import 'package:fcs_app/domain/course_lesson.dart';
import 'package:fcs_app/ui/content/course_video_screen.dart';
import 'package:fcs_app/ui/content/mama_course_screen.dart';
import 'package:fcs_app/domain/ai_chat_service.dart';
import 'package:fcs_app/domain/chat_controller.dart';
import 'package:fcs_app/domain/health_monitor.dart';
import 'package:fcs_app/ui/chat/assistant_chat_screen.dart';
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
import 'package:fcs_app/domain/child_growth.dart';
import 'package:fcs_app/ui/advisor/advisor_screen.dart';
import 'package:fcs_app/ui/calendar/day_log_sheet.dart';
import 'package:fcs_app/ui/calibration/bp_calibration_sheet.dart';
import 'package:fcs_app/ui/dashboard/log_sleep_sheet.dart';
import 'package:fcs_app/ui/dashboard/log_vitals_sheet.dart';
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';
import 'package:fcs_app/ui/calendar/week_detail_screen.dart';
import 'package:fcs_app/ui/tracking/child_growth_screen.dart';
import 'package:fcs_app/ui/appointments/appointments_screen.dart';
import 'package:fcs_app/ui/calendar/cycle_insights_screen.dart';
import 'package:fcs_app/ui/calendar/medications_screen.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';
import 'package:fcs_app/ui/settings/legal_screen.dart';
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
    /// Drive the screen before measuring — tap into a tab, open a section.
    /// A screen with more than one state only proves the state it opened in.
    Future<void> Function(WidgetTester tester)? afterPump,
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
    if (afterPump != null) await afterPump(tester);

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

  /// Open a modal sheet on a 360dp phone and fail if it overflowed.
  ///
  /// Sheets are the likeliest home for this bug and the hardest to see: they
  /// are laid out against a PARTIAL height that the sheet itself asks for, so
  /// a row or column that fits the full screen can still not fit here. None of
  /// them was covered.
  Future<void> sheetFits(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
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
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: L10nScope(
            l10n: L10n(locale),
            // The sheet needs a Navigator BELOW the MediaQuery/L10nScope, or
            // it is pushed without either and renders at the wrong scale in
            // the wrong language — which would look like a pass.
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (inner) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => open(inner),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final err = tester.takeException();
    expect(
      err,
      isNull,
      reason: '$label overflows at ${kNarrowWidth.toInt()}dp'
          '${textScale == 1.0 ? '' : ' with text at ${(textScale * 100).round()}%'}'
          '.\n$err',
    );
    // The sheet actually opened — a tap that did nothing would otherwise pass.
    expect(
      find.byType(BottomSheet),
      findsOneWidget,
      reason: '$label never opened, so "it fits" means nothing',
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

  /// A controller with a child old enough to have a development calendar.
  AppController withToddler() {
    final c = AppController(now: () => today);
    c.addChild(ChildProfile(
      id: 'k1',
      name: 'Сұлтан',
      dateOfBirth: today.subtract(const Duration(days: 400)),
    ));
    return c;
  }

  testWidgets("women's health fits in child-development mode", (tester) async {
    final c = withToddler();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (child)",
      afterPump: (tester) async {
        await tester.tap(find.text('Ребёнок'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets("women's health fits in child mode in Kazakh", (tester) async {
    final c = withToddler();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (child, kk)",
      locale: AppLocale.kk,
      afterPump: (tester) async {
        await tester.tap(find.text('Бала'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets("women's health fits with the text slider at 130%", (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (cycle, 130%)",
      textScale: 1.3,
    );
  });

  /// The calendar switch is the one row that must read in full.
  ///
  /// Three chips share a 360dp line and the default language's word for the
  /// middle one — «Беременность» — is twelve characters. Ellipsised it reads
  /// «Беременно…», a control nobody can identify at a glance. The overflow
  /// check above does not catch it: ellipsis IS the graceful degradation, so
  /// the screen passes every other guard while the label is unreadable.
  ///
  /// Asserted STRUCTURALLY, on purpose. Measuring the painted width here
  /// proves nothing: flutter_test substitutes a font whose every glyph is a
  /// full em square, so «Беременность» measures 144dp at 12px and every label
  /// in every language would look truncated. What can be checked, and is
  /// stronger than a measurement, is that the label is laid out in a way that
  /// mathematically cannot truncate — scaled down to fit rather than clipped.
  for (final (locale, labels) in [
    (AppLocale.ru, ['Цикл', 'Беременность', 'Ребёнок']),
    (AppLocale.kk, ['Цикл', 'Жүктілік', 'Бала']),
  ]) {
    testWidgets('the calendar switch cannot be cut short in ${locale.name}', (tester) async {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar switch (${locale.name})',
        locale: locale,
      );
      for (final label in labels) {
        expect(find.text(label), findsOneWidget,
            reason: '«$label» is not on the switch at all');
        final box = tester.widget<FittedBox>(find.ancestor(
            of: find.text(label), matching: find.byType(FittedBox)).first);
        expect(box.fit, BoxFit.scaleDown,
            reason: '«$label» can be clipped instead of shrunk — '
                'a segment nobody can read is a segment nobody taps');
      }
    });
  }

  /// Lesson titles are typed by staff in the back office, so they are as long
  /// as somebody felt like making them — not as long as this layout wants.
  final courseLessons = [
    const CourseLesson(
      id: 'l1',
      titleRu: 'Первые 40 дней: восстановление после родов и уход за собой',
      titleKk: 'Алғашқы 40 күн: босанғаннан кейінгі қалпына келу',
      youtubeUrl: 'https://youtu.be/aaaaaaaaaaa',
      summaryRu: 'Что происходит с телом, чего ждать и когда обращаться к врачу.',
      sort: 1,
    ),
    const CourseLesson(
      id: 'l2',
      titleRu: 'Грудное вскармливание без боли',
      youtubeUrl: 'https://youtu.be/bbbbbbbbbbb',
      sort: 2,
    ),
  ];

  testWidgets('the Ма!Ма! course fits when she owns it', (tester) async {
    await fits(
      tester,
      () => MamaCourseScreen(
        access: CourseAccess(entitled: true, lessons: courseLessons),
        launch: (_) async => true,
      ),
      'the Ма!Ма! course (entitled)',
    );
  });

  /// The state a returning customer actually opens: a progress line, a bar and
  /// a Continue button carrying a lesson title staff typed at whatever length
  /// they felt like. Every one of those is new width on a row that already fit
  /// only just, and the case above has no progress at all — so none of it was
  /// being measured.
  testWidgets('the Ма!Ма! course fits once she has watched some of it',
      (tester) async {
    await fits(
      tester,
      () => MamaCourseScreen(
        access: CourseAccess(
          entitled: true,
          lessons: courseLessons,
          progress: const {
            'l1': LessonProgress(lessonId: 'l1', completed: true),
            'l2': LessonProgress(
                lessonId: 'l2', positionSeconds: 450, durationSeconds: 1200),
          },
        ),
      ),
      'the Ма!Ма! course (in progress)',
    );
  });

  testWidgets('the Ма!Ма! course in progress fits at 130%', (tester) async {
    // "Продолжить · Первые 40 дней: восстановление…" at 130% is the longest
    // single line the course has.
    await fits(
      tester,
      () => MamaCourseScreen(
        access: CourseAccess(
          entitled: true,
          lessons: courseLessons,
          progress: const {'l1': LessonProgress(lessonId: 'l1', completed: true)},
        ),
      ),
      'the Ма!Ма! course (in progress, 130%)',
      textScale: 1.3,
    );
  });

  testWidgets('the lesson player fits', (tester) async {
    // debugWithoutPlayer: the real IFrame player needs a webview, which needs a
    // device. Everything laid out AROUND it is what can overflow.
    await fits(
      tester,
      () => CourseVideoScreen(
        lesson: courseLessons.first,
        progress: const LessonProgress(
            lessonId: 'l1', positionSeconds: 754, durationSeconds: 1200),
        debugWithoutPlayer: true,
        launch: (_) async => true,
      ),
      'the lesson player',
    );
  });

  testWidgets('the lesson player fits with a link we cannot play', (tester) async {
    // The longest copy on the screen, and the state a customer hits when a
    // lesson was authored before links were validated.
    await fits(
      tester,
      () => CourseVideoScreen(
        lesson: const CourseLesson(
          id: 'l9',
          titleRu: 'Первые 40 дней: восстановление после родов и уход за собой',
          // A lesson authored before links were validated: the summary is
          // there, the link is a channel page, and there is nothing to play.
          summaryRu: 'Что происходит с телом, чего ждать и когда обращаться к врачу.',
          youtubeUrl: 'https://www.youtube.com/@anabala',
          sort: 9,
        ),
        launch: (_) async => true,
      ),
      'the lesson player (bad link)',
      textScale: 1.3,
    );
  });

  testWidgets('the Ма!Ма! course offer fits when she does not', (tester) async {
    // The commercially important state: this is the pitch for the комплект,
    // and a broken-looking one costs a 39 000 ₸ sale.
    await fits(
      tester,
      () => const MamaCourseScreen(access: CourseAccess.none),
      'the Ма!Ма! course (offer)',
    );
  });

  testWidgets('the Ма!Ма! course offer fits at 130%', (tester) async {
    await fits(
      tester,
      () => const MamaCourseScreen(access: CourseAccess.none),
      'the Ма!Ма! course (offer, 130%)',
      textScale: 1.3,
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

  // ---- The list and history screens --------------------------------------
  //
  // All seeded with data. An empty list cannot overflow, and every one of
  // these has an empty state that would have passed while testing nothing.

  /// A controller with medications, appointments and a weight history.
  AppController wellUsed() {
    final c = AppController(now: () => now);
    // Long names on purpose: a medication is typed in by the user, and the
    // pharmacy label is what she copies from.
    c.addMedication('Фолиевая кислота (Фолацин)', dose: '400 мкг', perDay: 1);
    c.addMedication('Железо + витамин C', dose: '27 мг', perDay: 2);
    c.addAppointment('Приём у акушера-гинеколога, каб. 214', now.add(const Duration(days: 3)),
        note: 'Взять результаты анализов');
    c.addAppointment('УЗИ второго триместра', now.subtract(const Duration(days: 20)));
    c.logWeight(DateTime(2026, 7, 1), 64.5);
    c.logWeight(DateTime(2026, 7, 8), 65.1);
    return c;
  }

  testWidgets('the medications screen fits', (tester) async {
    final c = wellUsed();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => MedicationsScreen(controller: c, now: () => now),
      'the medications screen',
    );
  });

  testWidgets('the medications screen fits at 130%', (tester) async {
    final c = wellUsed();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => MedicationsScreen(controller: c, now: () => now),
      'the medications screen',
      textScale: 1.3,
    );
  });

  testWidgets('appointments fit', (tester) async {
    final c = wellUsed();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => AppointmentsScreen(controller: c, now: () => now),
      'appointments',
    );
  });

  testWidgets('appointments fit at 130%', (tester) async {
    final c = wellUsed();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => AppointmentsScreen(controller: c, now: () => now),
      'appointments',
      textScale: 1.3,
    );
  });

  testWidgets('cycle insights fit', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    // Two logged cycles, so the insights have something to summarise.
    for (final d in ['2026-05-04', '2026-05-05', '2026-06-02', '2026-06-03']) {
      c.setDayLog(DayLog(date: d, flow: Flow.medium, symptoms: const {Symptom.cramps}));
    }
    await fits(
      tester,
      () => CycleInsightsScreen(controller: c, now: () => today),
      'cycle insights',
    );
  });

  testWidgets('the postpartum screen fits', (tester) async {
    await fits(
      tester,
      () => PostpartumScreen(
        birthDate: now.subtract(const Duration(days: 12)),
        today: now,
      ),
      'the postpartum screen',
    );
  });

  testWidgets('the postpartum screen fits at 130%', (tester) async {
    await fits(
      tester,
      () => PostpartumScreen(
        birthDate: now.subtract(const Duration(days: 12)),
        today: now,
      ),
      'the postpartum screen',
      textScale: 1.3,
    );
  });

  testWidgets('the privacy policy fits', (tester) async {
    await fits(tester, () => const LegalScreen(doc: LegalDoc.privacy), 'the privacy policy');
  });

  // ---- The content and chart screens -------------------------------------

  testWidgets('the antenatal plan fits', (tester) async {
    // A long list of visits with expandable detail. Every row carries a week
    // number, a title and a chip.
    await fits(
      tester,
      () => AntenatalPlanScreen(week: 24, dueDate: today.add(const Duration(days: 112))),
      'the antenatal plan',
    );
  });

  testWidgets('the antenatal plan fits at 130%', (tester) async {
    await fits(
      tester,
      () => AntenatalPlanScreen(week: 24, dueDate: today.add(const Duration(days: 112))),
      'the antenatal plan',
      textScale: 1.3,
    );
  });

  testWidgets('the week detail fits', (tester) async {
    final g = gestationFor(today.add(const Duration(days: 112)), today)!;
    await fits(tester, () => WeekDetailScreen(gestation: g), 'the week detail');
  });

  testWidgets('the week detail fits at 130%', (tester) async {
    final g = gestationFor(today.add(const Duration(days: 112)), today)!;
    await fits(tester, () => WeekDetailScreen(gestation: g), 'the week detail', textScale: 1.3);
  });

  testWidgets('the week detail fits in Kazakh', (tester) async {
    final g = gestationFor(today.add(const Duration(days: 112)), today)!;
    await fits(tester, () => WeekDetailScreen(gestation: g), 'the week detail (kk)',
        locale: AppLocale.kk);
  });

  testWidgets('the growth chart fits', (tester) async {
    await fits(
      tester,
      () => ChildGrowthScreen(
        childName: 'Сұлтан',
        points: [
          GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6, heightCm: 51),
          GrowthPoint(at: DateTime(2026, 3, 10), weightKg: 5.4, heightCm: 58),
          GrowthPoint(at: DateTime(2026, 6, 10), weightKg: 7.2, heightCm: 66),
        ],
        onAdd: () {},
        onDelete: (_) {},
      ),
      'the growth chart',
    );
  });

  testWidgets('the growth chart fits at 130%', (tester) async {
    await fits(
      tester,
      () => ChildGrowthScreen(
        childName: 'Сұлтан',
        points: [
          GrowthPoint(at: DateTime(2026, 1, 10), weightKg: 3.6, heightCm: 51),
          GrowthPoint(at: DateTime(2026, 3, 10), weightKg: 5.4, heightCm: 58),
          GrowthPoint(at: DateTime(2026, 6, 10), weightKg: 7.2, heightCm: 66),
        ],
        onAdd: () {},
        onDelete: (_) {},
      ),
      'the growth chart',
      textScale: 1.3,
    );
  });

  // ---- The sheets --------------------------------------------------------

  testWidgets('the vitals sheet fits', (tester) async {
    await sheetFits(tester, (ctx) => showLogVitalsSheet(ctx), 'the vitals sheet');
  });

  testWidgets('the vitals sheet fits at 130%', (tester) async {
    await sheetFits(tester, (ctx) => showLogVitalsSheet(ctx), 'the vitals sheet', textScale: 1.3);
  });

  testWidgets('the vitals sheet fits in Kazakh', (tester) async {
    await sheetFits(tester, (ctx) => showLogVitalsSheet(ctx), 'the vitals sheet (kk)',
        locale: AppLocale.kk);
  });

  testWidgets('the sleep sheet fits', (tester) async {
    await sheetFits(tester, (ctx) => showLogSleepSheet(ctx, now: now), 'the sleep sheet');
  });

  testWidgets('the sleep sheet fits at 130%', (tester) async {
    await sheetFits(tester, (ctx) => showLogSleepSheet(ctx, now: now), 'the sleep sheet',
        textScale: 1.3);
  });

  testWidgets('the BP calibration sheet fits', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await sheetFits(tester, (ctx) => showCalibrateBpSheet(ctx, c), 'the BP calibration sheet');
  });

  testWidgets('the BP calibration sheet fits at 130%', (tester) async {
    final c = AppController(now: () => now);
    addTearDown(c.dispose);
    await sheetFits(tester, (ctx) => showCalibrateBpSheet(ctx, c), 'the BP calibration sheet',
        textScale: 1.3);
  });

  testWidgets('the day-log sheet fits', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await sheetFits(tester, (ctx) => showDayLogSheet(ctx, c, today), 'the day-log sheet');
  });

  testWidgets('the day-log sheet fits at 130%', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await sheetFits(tester, (ctx) => showDayLogSheet(ctx, c, today), 'the day-log sheet',
        textScale: 1.3);
  });

  testWidgets('the day-log sheet fits in Kazakh', (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    await sheetFits(tester, (ctx) => showDayLogSheet(ctx, c, today), 'the day-log sheet (kk)',
        locale: AppLocale.kk);
  });

  // ---- The assistant chat ------------------------------------------------
  //
  // Needs a ChatController over a stubbed transport, which is why it sat
  // uncovered. It is also the screen most likely to be read at 130%: someone
  // asking a health question is often doing it because something is wrong.

  ChatController chatController() {
    final monitor = HealthMonitor(
      deviceId: 'd',
      enqueue: (_, {required urgent}) {},
      onEmergency: (_, __) {},
    );
    return ChatController(
      service: AiChatService(
        api: ApiClient(_StubTransport()),
        userId: 'u',
        locale: () => 'ru',
        monitor: monitor,
        onEmergency: (_) {},
      ),
      networkErrorText: () => 'Нет связи',
      emergencyNoteText: () => 'Открываю экстренную помощь',
    );
  }

  testWidgets('the assistant chat fits', (tester) async {
    final c = chatController();
    await fits(tester, () => AssistantChatScreen(controller: c), 'the assistant chat');
  });

  testWidgets('the assistant chat fits at 130%', (tester) async {
    final c = chatController();
    await fits(
      tester,
      () => AssistantChatScreen(controller: c),
      'the assistant chat',
      textScale: 1.3,
    );
  });

  testWidgets('a long answer still fits', (tester) async {
    // The bubble is the widest thing on the screen and its content comes from
    // the model, so its length is not something the layout controls.
    final c = chatController();
    await fits(tester, () => AssistantChatScreen(controller: c), 'the assistant chat');
    await tester.enterText(find.byType(TextField).first, 'Почему кружится голова?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ---- The cry insight screen --------------------------------------------

  testWidgets('the cry insight screen fits', (tester) async {
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _stubCryClient(),
        history: [
          CryResult(at: now.subtract(const Duration(hours: 2)), reason: 'hunger', confidence: 0.82),
          CryResult(at: now.subtract(const Duration(days: 1)), reason: 'discomfort', confidence: 0.61),
        ],
      ),
      'the cry insight screen',
    );
  });

  testWidgets('the cry insight screen fits at 130%', (tester) async {
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _stubCryClient(),
        history: [
          CryResult(at: now.subtract(const Duration(hours: 2)), reason: 'hunger', confidence: 0.82),
        ],
      ),
      'the cry insight screen',
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

/// Answers every chat request with a long, realistic reply.
///
/// Long on purpose: the answer bubble is the widest thing on that screen and
/// its length comes from the model, not from the layout.
class _StubTransport implements HttpTransport {
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);

  @override
  Future<HttpResponse> post(String path, Object body) async => HttpResponse(
        200,
        jsonEncode({
          'kind': 'chat',
          'message': 'Головокружение во втором триместре часто связано с '
              'падением давления, когда вы резко встаёте. Попробуйте вставать '
              'медленнее, пить больше воды и не пропускать приёмы пищи. Если '
              'оно повторяется каждый день или сопровождается потемнением в '
              'глазах — сообщите об этом врачу на ближайшем приёме.',
          'grounded': true,
        }),
      );
}

/// A recorder that never touches hardware.
class _StubRecorder implements CryRecorder {
  @override
  Future<bool> start() async => true;
  @override
  Future<List<int>?> stopAndRead() async => const [1, 2, 3];
  @override
  Future<void> dispose() async {}
}

/// A classifier that answers without a network, with a long reason label —
/// the label sits beside a confidence figure on one row, so a short one would
/// not exercise the layout this sweep is about.
CryClassifierClient _stubCryClient() => CryClassifierClient(
      baseUrl: Uri.parse('http://stub.local'),
      authToken: () async => 'tok',
      uploader: (url, bytes, name, headers) async =>
          '{"reason":"discomfort","confidence":0.74}',
    );
