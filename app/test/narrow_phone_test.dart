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
import 'package:fcs_app/ui/calendar/antenatal_plan_screen.dart';
import 'package:fcs_app/ui/calendar/week_detail_screen.dart';
import 'package:fcs_app/ui/tracking/child_growth_screen.dart';
import 'package:fcs_app/ui/appointments/appointments_screen.dart';
import 'package:fcs_app/ui/calendar/cycle_insights_screen.dart';
import 'package:fcs_app/ui/calendar/medications_screen.dart';
import 'package:fcs_app/ui/calendar/epds_screen.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';
import 'package:fcs_app/ui/settings/legal_screen.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/calendar/hospital_bag_screen.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';
import 'package:fcs_app/ui/calendar/labour_signs_screen.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/emergency/emergency_rescue_screen.dart';
import 'package:fcs_app/ui/tracking/sos_alert_screen.dart';
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
import 'package:fcs_app/ui/tracking/child_tools_sheet.dart';
import 'package:fcs_app/ui/tracking/zones_screen.dart';

/// A Redmi/Galaxy A-series in portrait: the floor this app has to fit.
const double kNarrowWidth = 360;
const double kNarrowHeight = 640;

/// The OTHER floor the spec names — «360 dp и 320 dp — ничего не обрезано».
///
/// Almost no phone reports 320 logical pixels today, which is why it is easy
/// to dismiss. It is what a 360dp phone BECOMES when its owner turns Android's
/// display size up, and the people who turn display size up are the people
/// this app is for: pregnant women reading it at arm's length and grandmothers
/// minding the children.
const double kTinyWidth = 320;

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
    double width = kNarrowWidth,
    /// Drive the screen before measuring — tap into a tab, open a section.
    /// A screen with more than one state only proves the state it opened in.
    Future<void> Function(WidgetTester tester)? afterPump,

    /// Put the locale AND the font scale above the Navigator, so an [afterPump]
    /// that opens a dialog or a bottom sheet measures the right thing.
    ///
    /// Off by default because it changes the harness for every screen in this
    /// file, and the screens that do not push a route cannot tell the
    /// difference. It matters for the ones that do: a route pushed from inside
    /// `home:` sits ABOVE the L10nScope and the MediaQuery, so it renders in
    /// English at 100% — the language and the width the test is named for are
    /// silently not the ones being measured, and `L10nScope.of` returns
    /// `const L10n(AppLocale.en)` rather than throwing.
    bool aboveNavigator = false,
  }) async {
    tester.view.physicalSize = Size(width * 3, kNarrowHeight * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // copyWith, NOT a fresh MediaQueryData: building one from scratch gives it
    // Size.zero, and a screen that asks MediaQuery for the width then lays out
    // against nothing. The first version of this did exactly that, so every
    // screen here was measured against a zero-size viewport — the sweep looked
    // like it was passing 34 screens and was not testing the width it is named
    // after.
    //
    // The system font-size slider. Its users are not an edge case here — this
    // app is read by pregnant women and by grandmothers minding the children,
    // and Android's accessibility settings go well past this.
    Widget scaled(BuildContext context, Widget child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        );

    await tester.pumpWidget(
      aboveNavigator
          ? L10nScope(
              l10n: L10n(locale),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: FcsTheme.light(locale),
                // builder wraps the Navigator, so pushed routes are scaled too.
                builder: (context, child) => scaled(context, child!),
                home: Builder(builder: (_) => build()),
              ),
            )
          : MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: FcsTheme.light(locale),
              home: Builder(
                builder: (context) => scaled(
                    context, L10nScope(l10n: L10n(locale), child: build())),
              ),
            ),
    );
    await tester.pumpAndSettle();
    if (afterPump != null) await afterPump(tester);

    final err = tester.takeException();
    expect(
      err,
      isNull,
      reason: '$label overflows at ${width.toInt()}dp'
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
    double width = kNarrowWidth,
  }) async {
    tester.view.physicalSize = Size(width * 3, kNarrowHeight * 3);
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
      reason: '$label overflows at ${width.toInt()}dp'
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

  testWidgets('the home dashboard fits with no band readings at all',
      (tester) async {
    // The state most users are in permanently — no bracelet — which now shows
    // the whole screen (hero + quick actions + shelf + manual diary) rather
    // than a checklist. Nothing here was ever rendered at 360dp before.
    await fits(
      tester,
      () => HealthDashboardView(
        samples: const [],
        greetingName: 'Айгерім-Гүлнұр',
        gestation: GestationInfo(154, 22, 0, 126),
        kicksToday: 12,
        latestWeightKg: 68.4,
        onLogKick: () {},
        onLogDay: () {},
        onLogWeight: () {},
        onLogSleep: () {},
      ),
      'the home dashboard with no readings',
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
        onCheckIn: () async => true,
        onSos: () async => true,
      ),
      'the child map',
    );
  });

  testWidgets('the child map fits with its whole app bar', (tester) async {
    // Every action at once — the bell, the child card, the safety shield and
    // the add menu — which is what the real shell passes and what none of the
    // fixtures above did. The card icon is the newest of the four, and a
    // fourth icon beside a long «Где …?» title is exactly where an app bar
    // runs out of room.
    await fits(
      tester,
      () => ChildMapScreen(
        childName: 'Айгерім-Гүлнұр',
        childLocation: school.center,
        updatedAt: now.subtract(const Duration(minutes: 1)),
        fences: [home, school],
        now: now,
        mapBuilder: (_, __, ___) => const DsMapPlaceholder(caption: 'map', height: 300),
        childOptions: const [(id: 'c1', name: 'Айгерім-Гүлнұр')],
        selectedChildId: 'c1',
        onSelectChild: (_) {},
        onAddChild: () {},
        onAddDevice: () {},
        onManageZones: () {},
        onOpenAlerts: () {},
        alertCount: 3,
        onOpenChildCard: () {},
        batteryPct: 68,
        zoneEnteredAt: now.subtract(const Duration(minutes: 40)),
        lastCheckInAt: now.subtract(const Duration(hours: 2)),
        onCheckIn: () async => true,
        onSos: () async => true,
        onDayHistory: () {},
      ),
      'the child map with every action',
      width: kTinyWidth,
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

  /// Cycle mode with a period ACTUALLY LOGGED.
  ///
  /// The case above builds cycle mode from a controller with no logs, so it
  /// renders the invitation card and nothing else — the vacuity this file's
  /// header warns about, and it hid a 131px overflow in the phase card at
  /// 402dp, wider than this sweep ever measures. A logged period is what puts
  /// the phase card, the ring and the countdown rows on the screen.
  AppController withPeriod() {
    final c = AppController(now: () => today);
    c.setDayLog(DayLog(
        date: dateKey(today.subtract(const Duration(days: 10))),
        flow: Flow.medium));
    return c;
  }

  testWidgets("women's health fits in cycle mode with a period logged",
      (tester) async {
    final c = withPeriod();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (cycle, logged, kk, 320dp, 130%)",
      locale: AppLocale.kk,
      width: 320,
      textScale: 1.3,
    );
  });

  /// A period marked on a date that has not arrived — TODO §8.5.
  ///
  /// The card that replaces the cycle-day ring in this state carries three
  /// stacked strings and a link, and Kazakh is where they run longest. It is
  /// also the only state of this screen whose copy is new, so it is the one
  /// with no width history at all.
  testWidgets("women's health fits with a period marked in the future",
      (tester) async {
    final c = AppController(now: () => today);
    addTearDown(c.dispose);
    c.setDayLog(DayLog(
        date: dateKey(today.add(const Duration(days: 3))), flow: Flow.medium));
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (future mark, kk, 320dp, 130%)",
      locale: AppLocale.kk,
      width: 320,
      textScale: 1.3,
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

  /// A controller in the state that PUTS her on the development calendar.
  ///
  /// This used to be a 400-day-old toddler plus a tap on the «Ребёнок» chip.
  /// There is no chip now — «Календарь один, вкладок сверху нет» — and a
  /// 400-day-old child does not open the development calendar either: the
  /// middle rung of the priority is bounded by "a birth in the last year with
  /// no period logged since", so a mother whose youngest is over a year is
  /// back on her cycle. The state is the whole reach: no tap, and the test is
  /// faster and less fragile for it.
  AppController withNewborn() {
    final c = AppController(now: () => today);
    c.addChild(ChildProfile(
      id: 'k1',
      name: 'Сұлтан',
      dateOfBirth: today.subtract(const Duration(days: 120)),
    ));
    return c;
  }

  testWidgets("women's health fits on the development calendar", (tester) async {
    final c = withNewborn();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (development)",
    );
  });

  testWidgets("women's health fits on the development calendar in Kazakh",
      (tester) async {
    final c = withNewborn();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      "women's health (development, kk)",
      locale: AppLocale.kk,
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

  /// The calendar switch is the one control that must read in full.
  ///
  /// It used to be three chips sharing a 360dp line, and the guard was that
  /// «Беременность» — twelve characters — could not be ellipsised into
  /// «Беременно…», a control nobody can identify at a glance. The chips are
  /// gone («Календарь один, вкладок сверху нет»), but the property they were
  /// guarded for did not go with them: the switch is now the «⋯» events menu,
  /// and its labels are LONGER than any chip label ever was — «Тест
  /// положительный» is nineteen characters, «Етеккір қайта басталды» is
  /// twenty-two, and each sits on a ListTile beside a leading icon, which is
  /// narrower than the full width the chips had. So the same risk, moved, and
  /// at 320dp rather than 360.
  ///
  /// The overflow check does not catch this on its own: ellipsis IS the
  /// graceful degradation as far as Flutter is concerned, so the screen passes
  /// every other guard while the label is unreadable.
  ///
  /// Asserted STRUCTURALLY, as before, and for the same reason: flutter_test
  /// substitutes a font whose every glyph is a full em square, so measuring the
  /// painted width would call every label in every language truncated. What can
  /// be checked is that the label is laid out in a way that mathematically
  /// cannot truncate — here it WRAPS (no maxLines, no ellipsis) rather than
  /// being scaled down, because a menu row can grow taller and a chip could not.
  ///
  /// Every event in every state she can be in, in both languages: the item is
  /// only in the menu when it can happen next, so one state does not prove
  /// the others.
  for (final (locale, labels) in [
    (
      AppLocale.ru,
      (
        cycle: 'Тест положительный',
        pregnancy: 'Я родила',
        development: 'Месячные вернулись',
      )
    ),
    (
      AppLocale.kk,
      (
        cycle: 'Тест оң нәтиже берді',
        pregnancy: 'Мен босандым',
        development: 'Етеккір қайта басталды',
      )
    ),
  ]) {
    /// The event labels visible on screen must be whole words, not clipped.
    void expectUncuttable(WidgetTester tester, List<String> expected) {
      for (final label in expected) {
        expect(find.text(label), findsOneWidget,
            reason: '«$label» is not on the events menu at all');
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, isNull,
            reason: '«$label» is capped to ${text.maxLines} line(s), so the '
                'rest of it is thrown away — an event nobody can read is an '
                'event nobody taps');
        expect(text.overflow, isNot(TextOverflow.ellipsis),
            reason: '«$label» can be clipped instead of wrapped');
      }
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('the calendar events cannot be cut short in ${locale.name}',
        (tester) async {
      final c = AppController(now: () => today); // cycling
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar events, cycling (${locale.name})',
        locale: locale,
        width: kTinyWidth,
        // The menu is a PUSHED route, so the locale and the font scale have to
        // be above the Navigator or this measures English at 100%.
        aboveNavigator: true,
        afterPump: openMenu,
      );
      expectUncuttable(tester, [labels.cycle]);
    });

    testWidgets(
        'the calendar events cannot be cut short while pregnant in ${locale.name}',
        (tester) async {
      final c = AppController(now: () => today)
        ..setDueDate(today.add(const Duration(days: 140)));
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar events, pregnant (${locale.name})',
        locale: locale,
        width: kTinyWidth,
        aboveNavigator: true,
        afterPump: openMenu,
      );
      expectUncuttable(tester, [labels.pregnancy]);
    });

    testWidgets(
        'the calendar events cannot be cut short after a birth in ${locale.name}',
        (tester) async {
      final c = withNewborn();
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar events, after a birth (${locale.name})',
        locale: locale,
        width: kTinyWidth,
        aboveNavigator: true,
        afterPump: openMenu,
      );
      // Two items here, the longest pairing in the app's longer language.
      expectUncuttable(tester, [labels.cycle, labels.development]);
    });
  }

  testWidgets('the calendar events fit at 320dp in Kazakh with the slider at 130%',
      (tester) async {
    // The worst case this file exists for, applied to the new control: the
    // narrow floor, the longer language, and the font slider up, on a sheet
    // whose height is 9/16 of the screen and whose rows are full sentences.
    //
    // This is also the case that makes `aboveNavigator` load-bearing rather
    // than tidy: without it the sheet is pushed above the MediaQuery this test
    // sets, so it would be measured at 100% and pass while proving nothing.
    final c = withNewborn(); // two events on the menu — the fullest it gets
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      'the calendar events (kk, 130%)',
      locale: AppLocale.kk,
      width: kTinyWidth,
      textScale: 1.3,
      aboveNavigator: true,
      afterPump: (tester) async {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
      },
    );
    expect(find.text('Етеккір қайта басталды'), findsOneWidget);
  });

  testWidgets('the end-of-pregnancy fork fits at 320dp in Kazakh at 130%',
      (tester) async {
    // The sheet BEHIND «Я родила» — a birth on one row and a loss on the other,
    // each with a wrapping subtitle, inside a sheet whose height is 9/16 of the
    // screen. It is the sheet a woman may be reading through tears, and the one
    // place in the app where an overflow bar would be worst.
    final c = AppController(now: () => today)
      ..setDueDate(today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await fits(
      tester,
      () => WomensHealthScreen(controller: c, now: () => today),
      'the end-of-pregnancy fork (kk, 130%)',
      locale: AppLocale.kk,
      width: kTinyWidth,
      textScale: 1.3,
      aboveNavigator: true,
      afterPump: (tester) async {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Мен босандым'));
        await tester.pumpAndSettle();
      },
    );
    // Both doors are on it, and both read in full.
    expect(find.text('Бала дүниеге келді'), findsOneWidget);
    expect(find.text('Бақылауды өшіру'), findsOneWidget);
  });

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

  /// Record two contractions, so the screen is measured with its furniture up.
  ///
  /// Both timer cases used to render the EMPTY screen, which is the vacuity
  /// this file's header warns about: with nothing recorded there is no live
  /// card, no stats bar, no 5-1-1 checklist and no rows, so the two widest
  /// things on the screen were never laid out and the case passed by testing
  /// almost nothing.
  ///
  /// The taps are by ICON-FREE label lookup through the l10n catalogue, because
  /// the button label changes with the locale this runs in.
  Future<void> recordTwo(WidgetTester tester, AppLocale locale) async {
    final l = L10n(locale);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(l.t('contr_start_big')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l.t('contr_stop_big')));
      await tester.pump();
    }
  }

  testWidgets('the contraction timer fits with contractions recorded', (tester) async {
    await fits(
      tester,
      () => const ContractionTimerScreen(),
      'the contraction timer (recording)',
      afterPump: (t) => recordTwo(t, AppLocale.ru),
    );
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

  testWidgets('the contraction timer fits in Kazakh at 130%, mid-session',
      (tester) async {
    // The worst case this screen has: the longer language, the larger type, a
    // 320dp phone, and every card on screen at once. «Толғақ аяқталды» and
    // «Соңғы толғақтар» are both longer than their Russian.
    await fits(
      tester,
      () => const ContractionTimerScreen(),
      'the contraction timer (kk, 130%, recording)',
      locale: AppLocale.kk,
      textScale: 1.3,
      afterPump: (t) => recordTwo(t, AppLocale.kk),
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

  // With a controller, and with four low weeks logged: that is the WIDEST
  // this screen ever gets — the mood row wraps five pills and the amber card
  // carries «Четвёртую неделю подряд так себе» plus a button. Measuring the
  // version without them would measure a screen no mother sees.
  AppController _recoveryController() {
    final c = AppController(now: () => now);
    for (var w = 0; w < 4; w++) {
      for (var d = 0; d < 3; d++) {
        final day = now.subtract(Duration(days: w * 7 + d));
        c.setDayLog(DayLog(date: dateKey(day), mood: Mood.sad));
      }
    }
    return c;
  }

  testWidgets('the postpartum screen fits', (tester) async {
    final c = _recoveryController();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => PostpartumScreen(
        birthDate: now.subtract(const Duration(days: 12)),
        today: now,
        controller: c,
      ),
      'the postpartum screen',
    );
  });

  testWidgets('the postpartum screen fits at 130%', (tester) async {
    final c = _recoveryController();
    addTearDown(c.dispose);
    await fits(
      tester,
      () => PostpartumScreen(
        birthDate: now.subtract(const Duration(days: 12)),
        today: now,
        controller: c,
      ),
      'the postpartum screen',
      textScale: 1.3,
    );
  });

  testWidgets('the screening questionnaire fits', (tester) async {
    // Ten questions, four options each, and the options are whole sentences.
    await fits(tester, () => EpdsScreen(onCompleted: (_) {}), 'the EPDS questionnaire');
  });

  testWidgets('the screening questionnaire fits at 130%', (tester) async {
    await fits(tester, () => EpdsScreen(onCompleted: (_) {}), 'the EPDS questionnaire',
        textScale: 1.3);
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

  // The vitals sheet's three fit tests were HERE. The sheet was deleted with
  // hand entry on 2026-08-17; there is no widget left to measure.

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

  testWidgets('the cry «не отправилось» message fits at 320dp / 130% in Kazakh',
      (tester) async {
    // Nothing reached the analyser. Three clauses long, and the narrowest
    // phone at the largest text in the longest language is where it breaks
    // first — this sweep had never driven the screen into a failure phase.
    const l = L10n(AppLocale.kk);
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _failingCryClient(),
      ),
      'the cry not-sent message',
      locale: AppLocale.kk,
      textScale: 1.3,
      width: 320,
      afterPump: (t) async {
        await t.tap(find.text(l.t('cry_record')));
        await t.pump();
        await t.pump(const Duration(seconds: cryRecordSeconds));
        await t.pumpAndSettle();
        // Measuring the idle screen and calling it "the failure message fits"
        // is the failure mode this whole file exists to stop.
        expect(find.text(l.t('cry_not_sent')), findsOneWidget,
            reason: 'the screen never reached the not-sent state');
      },
    );
  });

  testWidgets('the «service unavailable» card fits at 320dp / 130% in Kazakh',
      (tester) async {
    // The state a mother actually reaches today: there is no trained
    // model.pkl (docs/INTEGRATION_STATUS.md), the classifier answers 503,
    // and the screen now says so instead of inviting another recording. It
    // is the widest thing on this screen — two paragraphs plus a chip.
    const l = L10n(AppLocale.kk);
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _unavailableCryClient(),
      ),
      'the cry service-unavailable card',
      locale: AppLocale.kk,
      textScale: 1.3,
      width: 320,
      afterPump: (t) async {
        await t.pumpAndSettle();
        expect(find.text(l.t('cry_unavailable')), findsOneWidget,
            reason: 'the screen never reached the unavailable state');
        expect(find.text(l.t('cry_recheck')), findsOneWidget);
      },
    );
  });

  testWidgets('the «это было верно?» chips fit at 130%', (tester) async {
    // Кадр 17c's second card, in the state that has the most on screen: she
    // said «нет», so five reason chips and «Не знаю» are laid out at once. The
    // screen has to be DRIVEN there — a card that only exists after a
    // recording is a state this sweep would otherwise never measure.
    const l = L10n(AppLocale.ru);
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _stubCryClient(),
        onVerdict: (_, __) => true,
      ),
      'the cry verdict chips',
      textScale: 1.3,
      afterPump: (t) async {
        await t.tap(find.text(l.t('cry_record')));
        await t.pump();
        await t.pump(const Duration(seconds: cryRecordSeconds));
        await t.pumpAndSettle();
        final no = find.text(l.t('cry_verdict_no'));
        await t.ensureVisible(no);
        await t.pumpAndSettle();
        await t.tap(no);
        await t.pumpAndSettle();
        await t.ensureVisible(find.text(l.t('cry_verdict_dont_know')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('the cry history fits with a verdict on every row at 130%', (tester) async {
    // Кадр 17c added a second line under each history row («Вы отметили:
    // неверно, было «Боль в животе»») and an unnamed row for an analysis below
    // the threshold. The longest of both, at the largest text, on the narrowest
    // phone — the combination that broke the confidence column before.
    await fits(
      tester,
      () => CryInsightScreen(
        recorder: _StubRecorder(),
        client: _stubCryClient(),
        history: [
          CryResult(
              at: now.subtract(const Duration(hours: 2)), reason: 'belly_pain',
              confidence: 0.82, verdict: CryVerdict.wrong, actualReason: 'discomfort'),
          CryResult(
              at: now.subtract(const Duration(days: 1)), reason: 'hungry',
              confidence: 0.91, verdict: CryVerdict.correct),
          // Below the shipped threshold: named as «не уверены», not as a reason.
          CryResult(at: now.subtract(const Duration(days: 2)), reason: 'tired', confidence: 0.21),
        ],
      ),
      'the cry history with verdicts',
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
          onCheckIn: () async => true,
          onSos: () async => true,
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

  /// The other width the checklist names: «360 dp и 320 dp — ничего не
  /// обрезано».
  ///
  /// Not every screen — the 360dp sweep above is already the long one, and
  /// running all of it twice buys a slower suite rather than more information.
  /// These are the four a woman opens every day plus the one she opens when
  /// something is wrong, which is where a clipped row costs the most.
  ///
  /// 320dp is where the layout actually breaks rather than bends: 40dp is a
  /// column of a metric grid, so a row that fits 360 with nothing to spare
  /// fails here — which is the point of testing it separately.
  group('320dp — a phone with the display size turned up', () {
    testWidgets('the dashboard fits', (tester) async {
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
          greetingName: 'Айгерім-Гүлнұр',
          sleepNights: [
            SleepSummary(night: today, deepMin: 95, remMin: 70, lightMin: 280, awakeMin: 12),
          ],
          currentLocale: AppLocale.ru,
        ),
        'the dashboard',
        width: kTinyWidth,
      );
    });

    testWidgets('the calendar fits in cycle mode', (tester) async {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar (cycle)',
        width: kTinyWidth,
      );
    });

    testWidgets('the calendar fits in pregnancy mode', (tester) async {
      // The gestation hero is the widest single element in the app — a week
      // number, a day count and a countdown on one row.
      final c = AppController(now: () => today);
      c.setDueDate(today.add(const Duration(days: 140)));
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar (pregnancy)',
        width: kTinyWidth,
      );
    });

    testWidgets('settings fit', (tester) async {
      final c = AppController(now: () => now);
      addTearDown(c.dispose);
      await fits(tester, () => SettingsScreen(controller: c), 'settings',
          width: kTinyWidth);
    });

    testWidgets('the alerts feed fits', (tester) async {
      final c = withAlerts();
      addTearDown(c.dispose);
      await fits(tester, () => AlertsScreen(controller: c), 'the alerts feed',
          width: kTinyWidth);
    });

    testWidgets('screen 21 — the SOS takeover — fits in Kazakh at 130%',
        (tester) async {
      // The worst case in the app for this check, and the one screen where an
      // overflow is unrecoverable: a red canvas at 320dp, in the longer
      // language, with the font slider up, carrying a headline, a location
      // card, the ambulance block and three stacked actions. Every button on it
      // is something to do in an emergency, so a striped bar over the bottom of
      // the column is the whole feature gone.
      await fits(
        tester,
        () => SosAlertScreen(
          childName: 'Айгерім-Гүлнұр',
          at: DateTime.utc(2026, 7, 15, 8, 41),
          now: now,
          // A parent-typed zone name, not «Дом» — the short case is not the
          // normal one.
          zoneName: 'Мектеп №25, ауладағы алаң',
          coords: const Coordinates(43.25, 76.95),
          coordsAt: DateTime.utc(2026, 7, 15, 8, 55),
          contactName: 'Нұржан ағай',
          contactPhone: '+7 701 123 45 67',
          mapBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFDDE7DE)),
          onOpenMap: () {},
          onCall: (_) async => true,
          onDismissConfirmed: () async {},
        ),
        'the SOS takeover in Kazakh',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
    });

    /// The dashboard app bar with EVERY action on it, in Kazakh, at 130%.
    ///
    /// The bell is the fourth icon on that row — screen 39 had no route from
    /// the tab the app opens on, so a woman with no child could not read a
    /// рассылка at all — and an app bar is where a fourth icon runs out of
    /// room. The badge widens it again, and «Хабарламалар» is the longer word.
    testWidgets('the dashboard fits with the notification bell on it',
        (tester) async {
      await fits(
        tester,
        () => HealthDashboardView(
          samples: [
            for (var i = 0; i < 6; i++)
              HealthSample(
                at: DateTime.utc(2026, 7, 15, 8, i * 5),
                heartRate: 70 + i % 7,
                spo2: 97,
                coreTemp: 36.6,
              ),
          ],
          greetingName: 'Айгерім-Гүлнұр',
          currentLocale: AppLocale.kk,
          onLocaleChange: (_) {},
          onOpenProfile: () {},
          // Two digits, which is the widest the badge ever gets.
          onOpenNotifications: () {},
          notificationCount: 12,
          statusChip: 'Жүктіліктің 22-аптасы',
          statusChipPregnancy: true,
          onOpenStatus: () {},
          gestation: const GestationInfo(154, 22, 0, 126),
          // «Аудио дня» — screens 04 and 55 put it above the shelf.
          audioTrack: 'pregnancy',
          audioDay: 154,
        ),
        'the dashboard with the bell (kk)',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
    });

    /// The peace ring's PARTIAL sentence, in Kazakh, at 320dp and 130%.
    ///
    /// «Барлық көрсеткіш ескерілмеді: 4 ішінен 2.» is the everyday state of a
    /// band user — a wrist temperature and a wrist blood pressure carry no
    /// grade — and it sits in a column 74dp of ring narrower than the card, in
    /// the language that runs longest, under a headline that wraps. It is the
    /// tightest place any new string on this screen can land.
    ///
    /// The readings are pinned CURRENT against `nowForAppointment`: left stale
    /// they fall to `db_ring_ungraded` and this test would measure a different,
    /// shorter sentence while claiming to measure this one.
    testWidgets('the partial-ring sentence fits in Kazakh', (tester) async {
      final now = DateTime.utc(2026, 7, 15, 9);
      await fits(
        tester,
        () => HealthDashboardView(
          samples: [
            for (var i = 0; i < 6; i++)
              HealthSample(
                at: now.subtract(Duration(minutes: i * 2)),
                heartRate: 72,
                spo2: 98,
                coreTemp: 36.6,
                source: ReadingSource.sensor,
              ),
          ],
          nowForAppointment: now,
          greetingName: 'Айгерім-Гүлнұр',
          currentLocale: AppLocale.kk,
        ),
        'the dashboard with a partial ring (kk)',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
      // …and it is the sentence this test is named for that was on the screen.
      expect(
        find.text(const L10n(AppLocale.kk)
            .t('db_ring_partial', {'n': 2, 'total': 4})),
        findsOneWidget,
      );
    });

    /// The child map carrying screen 15a's labelled tools control.
    ///
    /// It is a full-width row over the map, above the check-in / история дня /
    /// SOS trio, and «Күтім және денсаулық» is the longest label on it.
    testWidgets('the child map fits with the tools control', (tester) async {
      await fits(
        tester,
        () => ChildMapScreen(
          childName: 'Айгерім-Гүлнұр',
          childLocation: school.center,
          updatedAt: now.subtract(const Duration(minutes: 1)),
          fences: [home, school],
          now: now,
          mapBuilder: (_, __, ___) =>
              const DsMapPlaceholder(caption: 'map', height: 300),
          childOptions: const [(id: 'c1', name: 'Айгерім-Гүлнұр')],
          selectedChildId: 'c1',
          onSelectChild: (_) {},
          onAddChild: () {},
          onAddDevice: () {},
          onManageZones: () {},
          onOpenAlerts: () {},
          alertCount: 3,
          onOpenChildCard: () {},
          onOpenTools: () {},
          batteryPct: 68,
          zoneEnteredAt: now.subtract(const Duration(minutes: 40)),
          lastCheckInAt: now.subtract(const Duration(hours: 2)),
          onCheckIn: () async => true,
          onSos: () async => true,
          onDayHistory: () {},
        ),
        'the child map with the tools control (kk)',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
    });

    /// Screen 15a's sheet itself — nine rows, in the longer language, with the
    /// font slider up. It scrolls rather than growing past the screen, which is
    /// the thing that has to be true here.
    testWidgets('the child tools sheet fits', (tester) async {
      final c = AppController(now: () => now, locale: AppLocale.kk)
        ..addChild(ChildProfile(
            id: 'c1',
            name: 'Айгерім-Гүлнұр',
            dateOfBirth: DateTime(2026, 1, 15)));
      addTearDown(c.dispose);
      await sheetFits(
        tester,
        (ctx) => showChildToolsSheet(ctx, c, childId: 'c1', now: now),
        'the child tools sheet (kk)',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
    });

    /// The profile with «Поддержка» on it, badge and all.
    testWidgets('the profile fits with the support row', (tester) async {
      final c = AppController(now: () => now, locale: AppLocale.kk);
      addTearDown(c.dispose);
      await fits(
        tester,
        () => ProfileScreen(
          controller: c,
          onOpenSupport: () async {},
          loadSupportUnread: () async => 3,
          onOpenFamilyAccess: () {},
        ),
        'the profile with support (kk)',
        locale: AppLocale.kk,
        width: kTinyWidth,
        textScale: 1.3,
      );
    });

    testWidgets('and in Kazakh, which is the longer language', (tester) async {
      // 320dp AND the language whose words are longest AND the locale nobody
      // on the team reads back. Three things that each hide a clipped row.
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await fits(
        tester,
        () => WomensHealthScreen(controller: c, now: () => today),
        'the calendar in Kazakh',
        locale: AppLocale.kk,
        width: kTinyWidth,
      );
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
      // The availability probe the screen fires before it opens a microphone.
      // Answered explicitly so this test drives a KNOWN state rather than
      // whatever flutter_test's HTTP stub happens to return.
      prober: (url, headers) async => (status: 200, body: '{"available":true}'),
    );

/// Nothing reached the analyser — no signal, a dropped connection, a 502.
/// Drives the screen into `_Phase.notSent`.
CryClassifierClient _failingCryClient() => CryClassifierClient(
      baseUrl: Uri.parse('http://stub.local'),
      authToken: () async => 'tok',
      uploader: (url, bytes, name, headers) async =>
          throw const CryClassifierException('HTTP 502',
              failure: CryFailure.unreachable),
      // The availability probe the screen fires before it opens a microphone.
      // Answered explicitly so this test drives a KNOWN state rather than
      // whatever flutter_test's HTTP stub happens to return.
      prober: (url, headers) async => (status: 200, body: '{"available":true}'),
    );

/// What production answers TODAY: no trained model.pkl, so the classifier
/// answers 503, the proxy preserves it, and the probe says so before the
/// microphone ever opens. Drives the screen into `_Phase.unavailable`.
CryClassifierClient _unavailableCryClient() => CryClassifierClient(
      baseUrl: Uri.parse('http://stub.local'),
      authToken: () async => 'tok',
      uploader: (url, bytes, name, headers) async =>
          throw const CryClassifierException('HTTP 503',
              failure: CryFailure.unavailable),
      prober: (url, headers) async => (status: 200, body: '{"available":false}'),
    );
