/// Widget tests for the Women's Health calendar — pregnancy (gestation) vs
/// cycle mode headers.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  AppController controllerFor({DateTime? dueDate}) {
    final c = AppController(now: () => today);
    if (dueDate != null) c.setDueDate(dueDate);
    return c;
  }

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: WomensHealthScreen(controller: c, now: () => today),
        ),
      );

  testWidgets('pregnancy mode shows the gestation header', (tester) async {
    // Due in 140 days → 280-140 = 140 gestational days = week 20.
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(find.text('Week 20, Day 0'), findsOneWidget);
    expect(find.textContaining('days to go'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('the pregnancy hero has prev/next week chevrons that open the browser on the adjacent week', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140))); // week 20
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    // Discoverable right on the hero — no hunting for "More" first.
    expect(find.byTooltip('Next week'), findsOneWidget);
    expect(find.byTooltip('Previous week'), findsOneWidget);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    // Opened directly on week+1 (both the app-bar title and the stepper show it).
    expect(find.text('Week 21'), findsWidgets);
  });

  testWidgets('cycle mode (no due date) invites tracking the cycle', (tester) async {
    final c = controllerFor(); // no due date → cycle mode
    await tester.pumpWidget(wrap(c));
    expect(find.text('Track your cycle'), findsOneWidget);
    expect(find.textContaining('Week 20'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('pregnancy mode has an always-reachable when-to-call action', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.byIcon(Icons.health_and_safety_outlined), findsOneWidget);
  });

  testWidgets('the when-to-call action is not shown in cycle mode', (tester) async {
    final c = controllerFor(); // cycle mode
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.byIcon(Icons.health_and_safety_outlined), findsNothing);
  });

  testWidgets('the when-to-call action opens the warning list', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    // L10nScope above the Navigator so the pushed warnings screen has a scope.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.en), child: child!),
      home: WomensHealthScreen(controller: c, now: () => today),
    ));

    await tester.tap(find.byIcon(Icons.health_and_safety_outlined));
    await tester.pumpAndSettle();
    // The reduced-movement sign is the one most often missed; its presence is a
    // reliable marker that the list rendered.
    expect(find.text('The baby is moving noticeably less than usual'), findsOneWidget);
  });

  testWidgets('the hospital bag appears in the third trimester and persists a tick', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    // Due in 42 days → week 34, third trimester.
    final c = controllerFor(dueDate: today.add(const Duration(days: 42)));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.en), child: child!),
      home: WomensHealthScreen(controller: c, now: () => today),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Hospital bag'));
    await tester.tap(find.text('Hospital bag'));
    await tester.pumpAndSettle();

    // Tick the car seat; the controller should remember it.
    await tester.ensureVisible(find.text('Car seat'));
    await tester.tap(find.text('Car seat'));
    await tester.pumpAndSettle();
    expect(c.isHospitalBagItemPacked('car_seat'), isTrue);
  });

  testWidgets('no hospital-bag card before the third trimester', (tester) async {
    // Week 20 — too early.
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.text('Hospital bag'), findsNothing);
  });

  testWidgets('the weight-gain guide is reachable in pregnancy mode and opens', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.en), child: child!),
      home: WomensHealthScreen(controller: c, now: () => today),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('How much to gain?'));
    await tester.tap(find.text('How much to gain?'));
    await tester.pumpAndSettle();
    // The guide's ranges heading is a reliable landing marker.
    expect(find.text('Typical range for the whole pregnancy'.toUpperCase()), findsOneWidget);
  });

  testWidgets('a recent birth surfaces the postpartum recovery card', (tester) async {
    // Cycle mode after a birth 30 days ago: her body is still recovering, and
    // the app should say so.
    final c = controllerFor();
    c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 30))));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('Recovery after birth'), findsOneWidget);
  });

  testWidgets('no recovery card once the postpartum window has passed', (tester) async {
    // A child born long ago is not a postpartum context.
    final c = controllerFor();
    c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: DateTime(2024, 1, 1)));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('Recovery after birth'), findsNothing);
  });

  testWidgets('opening the recovery card reaches the guide', (tester) async {
    final c = controllerFor();
    c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 10))));
    addTearDown(c.dispose);
    // L10nScope ABOVE the Navigator (via builder), so the pushed recovery
    // screen has a scope ancestor. wrap() nests it inside home, which is fine
    // until a route is pushed.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.en), child: child!),
      home: WomensHealthScreen(controller: c, now: () => today),
    ));

    await tester.tap(find.textContaining('Recovery after birth'));
    await tester.pumpAndSettle();
    // The recovery screen's app-bar title is a reliable landing marker that
    // sits at the top, above the fold on the default test viewport.
    expect(find.text('After birth'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);
  });

  group('a birth pauses cycle predictions (no phantom period)', () {
    void logPeriod(AppController c, DateTime start) {
      for (int i = 0; i < 4; i++) {
        c.toggleFlowFor(start.add(Duration(days: i)), Flow.medium);
      }
    }

    test('a recent birth suppresses cycle predictions from pre-pregnancy logs', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      logPeriod(c, DateTime(2025, 9, 1)); // pre-pregnancy history
      c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 2))));
      expect(c.isPostpartum, isTrue);
      expect(c.cycle.hasData, isFalse, reason: 'no "period in N days" right after birth');
      expect(c.cycle.nextPeriodStart, isNull);
    });

    test('a period logged after the birth means the cycle is back', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 60))));
      expect(c.isPostpartum, isTrue);
      logPeriod(c, today.subtract(const Duration(days: 6))); // her cycle returns
      expect(c.isPostpartum, isFalse);
      expect(c.cycle.hasData, isTrue);
    });

    test('an older child (>1y) is not a postpartum context', () {
      final c = controllerFor();
      addTearDown(c.dispose);
      logPeriod(c, today.subtract(const Duration(days: 6)));
      c.addChild(ChildProfile(id: 'k', name: 'Big kid', dateOfBirth: today.subtract(const Duration(days: 800))));
      expect(c.isPostpartum, isFalse);
      expect(c.cycle.hasData, isTrue);
    });

    testWidgets('after a birth there is no cycle calendar to explain away',
        (tester) async {
      // «Родила — развитие вместо беременности. Цикл возвращается после первых
      // месячных.» Her stale pre-pregnancy period is still in the log, and the
      // controller already refuses to predict from it — but the stronger answer
      // is that the cycle calendar is not on screen at all until it comes back.
      final c = controllerFor();
      logPeriod(c, DateTime(2025, 9, 1)); // before the pregnancy
      c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 2))));
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      // Her recovery is on the screen she actually lands on — it is about HER,
      // not about which calendar she is reading.
      expect(find.textContaining('Recovery after birth'), findsOneWidget);
      expect(find.text('Log period'), findsNothing);
      expect(c.cycle.hasData, isFalse, reason: 'and no phantom prediction under it');
    });

    test('adding a newborn while still marked pregnant ends the pregnancy', () {
      final c = controllerFor(dueDate: today.subtract(const Duration(days: 3))); // overdue = "pregnant"
      addTearDown(c.dispose);
      expect(c.isPregnant, isTrue);
      c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 2))));
      expect(c.isPregnant, isFalse, reason: 'a newborn means the pregnancy is over');
      expect(c.isPostpartum, isTrue);
    });

    test('adding an older child never clears a real pregnancy', () {
      final c = controllerFor(dueDate: today.add(const Duration(days: 60))); // genuinely pregnant
      addTearDown(c.dispose);
      c.addChild(ChildProfile(id: 'k', name: 'Big kid', dateOfBirth: today.subtract(const Duration(days: 400))));
      expect(c.isPregnant, isTrue);
    });
  });

  /// Scroll the cycle calendar until [label] is built.
  ///
  /// The month grid now leads the cycle calendar (frame 09: «сетка месяца →
  /// легенда → карточка "День 3 · менструация"»), so the cards that explain
  /// the month sit below it — and a ListView only builds what is near the
  /// visible window. These three assertions used to pass on a 600px viewport
  /// only because the grid was FIFTH on the screen, which is the layout the
  /// spec says is wrong.
  Future<void> scrollToLabel(WidgetTester tester, String label) =>
      tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);

  testWidgets('cycle mode shows the current phase card', (tester) async {
    final c = controllerFor(); // cycle mode, today = Jul 16
    // A period Jul 10–12 → today (Jul 16) lands after the period, before the
    // fertile window → follicular phase.
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c));
    await scrollToLabel(tester, 'Follicular');
    expect(find.text('Follicular'), findsOneWidget);
    expect(find.textContaining('Day 4 of'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('the cycle calendar leads with the month, and draws it once',
      (tester) async {
    // Frame 09: «шапка + Август ▾ → сетка месяца → легенда → карточка
    // "День 3 · менструация" → Отметить день».
    //
    // The grid used to be FIFTH — below the phase card, the usual-symptoms
    // card, the fertile countdown and the predictions card. On a screen titled
    // «Календарь» the calendar was off the bottom of the fold, which is a
    // hierarchy defect no widget test would ever have noticed, because every
    // widget worked.
    // A TALL viewport, so the whole list is laid out.
    //
    // This matters more than it looks. On the default 600px surface a ListView
    // builds only what is near the visible window, so the "exactly one grid"
    // assertion passed even with the duplicate restored — the second grid was
    // never built, and the test was green about a defect it was written to
    // catch. Verified by reverting: with 600px, rendering the grid twice still
    // passed. It does not now.
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = controllerFor();
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    // Exactly one grid on the page. Placing it twice — once per mode — would
    // have put two sets of day targets on one screen, both opening the same
    // sheet, which is the duplicate-control defect this repo keeps shipping.
    expect(find.byKey(const ValueKey(monthGridKey)), findsOneWidget,
        reason: 'one month grid per screen');

    // …and it is above the card that explains the month.
    final gridY = tester.getTopLeft(find.byKey(const ValueKey(monthGridKey))).dy;
    final phaseY = tester.getTopLeft(find.text('Follicular')).dy;
    expect(gridY, lessThan(phaseY),
        reason: 'the month grid is drawn above the phase card — frame 09');
  });

  testWidgets('cycle mode shows the fertile-window countdown when upcoming', (tester) async {
    final c = controllerFor(); // cycle mode, today = Jul 16
    // Period Jul 10–12 → fertile window opens Jul 19 (still upcoming on Jul 16).
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c));
    await scrollToLabel(tester, 'Fertile window in 3 days');
    expect(find.text('Fertile window in 3 days'), findsOneWidget);
    expect(find.textContaining('Ovulation in about'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('shows the symptoms usually logged in the current phase', (tester) async {
    final c = controllerFor(); // cycle mode, today = Jul 16
    // Two periods (Jun 12–14, Jul 10–12) → today (Jul 16) is follicular.
    for (final start in [DateTime(2026, 6, 12), DateTime(2026, 7, 10)]) {
      for (var i = 0; i < 3; i++) {
        c.toggleFlowFor(start.add(Duration(days: i)), Flow.medium);
      }
    }
    // A headache logged on Jun 17 — the follicular stretch of the prior cycle.
    c.setDayLog(DayLog(date: dateKey(DateTime(2026, 6, 17)), symptoms: const {Symptom.headache}));
    await tester.pumpWidget(wrap(c));

    await scrollToLabel(tester, 'Around now you often log');
    expect(find.text('Around now you often log'), findsOneWidget);
    expect(find.textContaining('Headache'), findsWidgets);
    addTearDown(c.dispose);
  });

  testWidgets('predictions show a confidence chip that grows with history', (tester) async {
    /// Scroll the calendar until [label] is built.
    ///
    /// The predictions card sits below the fold on a 600px test viewport, and
    /// a ListView only builds what is near the visible window — so asserting
    /// on it directly passed only by accident of how much room was left over.
    Future<void> scrollTo(WidgetTester tester, String label) =>
        tester.scrollUntilVisible(find.text(label), 200,
            scrollable: find.byType(Scrollable).first);

    // One logged period → no completed cycles → low confidence.
    final c1 = controllerFor();
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11)]) {
      c1.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c1));
    await scrollTo(tester, 'low data');
    expect(find.text('low data'), findsOneWidget);
    addTearDown(c1.dispose);

    // Two logged periods → one completed cycle → still building.
    final c2 = controllerFor();
    for (final start in [DateTime(2026, 7, 10), DateTime(2026, 6, 12)]) {
      for (var i = 0; i < 2; i++) {
        c2.toggleFlowFor(start.add(Duration(days: i)), Flow.medium);
      }
    }
    await tester.pumpWidget(wrap(c2));
    await scrollTo(tester, 'building');
    expect(find.text('building'), findsOneWidget);
    addTearDown(c2.dispose);
  });

  testWidgets('the period button never covers the month grid', (tester) async {
    // It used to be a FloatingActionButton, parked on the last week of the
    // month. This screen is barely taller than a phone, so at rest — which is
    // how it is nearly always seen — the dates underneath were unreadable and
    // untappable.
    final c = controllerFor(); // cycle mode
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));

    expect(find.byType(FloatingActionButton), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Log period');
    expect(button, findsOneWidget);

    // Below the scrolling list, not on top of it.
    final listBottom = tester.getRect(find.byType(ListView).first).bottom;
    expect(tester.getRect(button).top, greaterThanOrEqualTo(listBottom),
        reason: 'the period button overlaps the calendar it belongs to');
  });

  testWidgets('cycle mode with data can share a copied summary', (tester) async {
    final c = controllerFor(); // cycle mode
    // Log a period so predictions exist (hasData → the share action appears).
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(wrap(c));
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cycle summary copied to clipboard'), findsOneWidget);
    expect(copied, contains('Cycle forecast'));
    expect(copied, contains('Next period:'));
    addTearDown(c.dispose);
  });

  testWidgets('"See all" opens the full kick-session history', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140))); // pregnancy mode
    for (var i = 0; i < 6; i++) {
      c.logKickSession(today, i + 1, const Duration(seconds: 30)); // 6 > 5 shown
    }
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('See all (6)'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('See all (6)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all (6)'));
    await tester.pumpAndSettle();
    // Full-history screen lists every session (6 rows) under the history title.
    expect(find.text('Session history'), findsOneWidget); // app bar
    expect(find.textContaining('movements'), findsNWidgets(6));
    addTearDown(c.dispose);
  });

  testWidgets('baby size + weekly highlight are not duplicated on the overview', (tester) async {
    // They live on the "Подробнее" week-detail page (see week_detail_test.dart),
    // so the calendar overview must not repeat them.
    final c = controllerFor(dueDate: today.add(const Duration(days: 140))); // week 20 → banana
    await tester.pumpWidget(wrap(c));
    expect(find.text('BABY SIZE'), findsNothing);
    expect(find.textContaining('About the size of a'), findsNothing);
    expect(find.text('The baby can begin to hear your voice.'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('kick history shows a summary strip and goal badge', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140))); // pregnancy mode
    c.logKickSession(today, 12, const Duration(seconds: 600)); // reaches goal (10)
    c.logKickSession(today, 8, const Duration(seconds: 400)); // misses goal
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('SESSION HISTORY'), 200, scrollable: find.byType(Scrollable).first);
    // Summary strip: labels + goals-met fraction (1 of 2 reached the goal).
    expect(find.text('Avg movements'), findsOneWidget);
    expect(find.text('Goals met'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget); // one of two reached the goal
    addTearDown(c.dispose);
  });

  testWidgets('kick session history can be cleared (with confirm)', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140))); // pregnancy mode
    c.logKickSession(today, 5, const Duration(seconds: 30));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('SESSION HISTORY'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('5 movements'), findsOneWidget);
    // scrollUntilVisible stops as soon as the target is barely on screen, so
    // the header action beside it can still sit below the fold — it did, the
    // moment the week strip grew by a line. ensureVisible puts the thing being
    // tapped fully in view, which is what a user does before tapping it.
    await tester.ensureVisible(find.text('Clear').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear').first); // header action
    await tester.pumpAndSettle();
    expect(find.text('Clear session history?'), findsOneWidget);
    await tester.tap(find.text('Clear').last); // dialog confirm
    await tester.pumpAndSettle();
    expect(c.kickSessions, isEmpty);
    expect(find.text('SESSION HISTORY'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('an appointment on a visible day shows a dot on the month grid', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0)); // same month as today
    await tester.pumpWidget(wrap(c));
    // The month grid is below the fold in the test viewport — scroll it in.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('appt-dot-20')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('appt-dot-20')), findsOneWidget);
    expect(find.byKey(const ValueKey('appt-dot-19')), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('the end-of-pregnancy event returns to the cycle calendar', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(c.isPregnant, true);

    // Through the «⋯» events menu — «Переключение — событием в «⋯»». It used to
    // be an underlined link parked under the pregnancy hero.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I have given birth'));
    await tester.pumpAndSettle();
    // This used to be a yes/no confirm. It is a fork now — a birth carries the
    // date into a child record, and this path just turns tracking off — so the
    // test takes the branch it was always about. birth_transition_test covers
    // the other one.
    await tester.tap(find.text('Just turn tracking off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off')); // the confirm, naming what changes
    await tester.pumpAndSettle();
    expect(c.isPregnant, false);
    expect(c.children, isEmpty, reason: 'this path creates no child');
    expect(find.text('Track your cycle'), findsOneWidget);
    addTearDown(c.dispose);
  });

  /// One subject, one card.
  ///
  /// After a birth the screen used to open with «Цикл на паузе после родов» and
  /// «Восстановление после родов» directly under it — "после родов" twice
  /// before she reached anything she could act on, and two cards for one
  /// thought. The pause card is gone with the cycle calendar it explained (see
  /// the group above); her recovery is not, and must still be exactly one card
  /// on the calendar she actually lands on.
  testWidgets('her recovery is one card on the calendar she lands on',
      (tester) async {
    final c = controllerFor();
    addTearDown(c.dispose);
    c.addChild(ChildProfile(
        id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 30))));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    // Once, not twice, and without a second card repeating «после родов».
    expect(find.textContaining('Recovery after birth'), findsOneWidget);
    expect(find.text('Cycle paused after birth'), findsNothing,
        reason: 'there is no cycle calendar on screen to explain the pause in');
  });

  /// An empty month grid explains itself.
  ///
  /// With nothing logged it is thirty grey numbers and one circle, taking
  /// nearly half the screen, with no legend under it — because there is
  /// nothing to explain. So it reads as broken rather than empty, and nothing
  /// tells her that tapping a day is how anything gets into it.
  group('the month grid with nothing in it', () {
    /// The hint sits below the grid, and a ListView only builds what is near
    /// the viewport — so asserting on it without scrolling proves nothing in
    /// either direction. The first version of these tests did exactly that.
    Future<void> toBottom(WidgetTester tester) async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('says how to fill it', (tester) async {
      final c = controllerFor(); // cycle mode, nothing logged
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      await toBottom(tester);

      expect(find.textContaining('Tap a day'), findsOneWidget);
    });

    testWidgets('and stops saying it once there is something to show', (tester) async {
      final c = controllerFor();
      addTearDown(c.dispose);
      for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11)]) {
        c.toggleFlowFor(d, Flow.medium);
      }
      await tester.pumpWidget(wrap(c));
      await toBottom(tester);

      // The legend replaces it — an explanation of what the colours mean is
      // more use than an invitation she has already accepted.
      expect(find.textContaining('Tap a day'), findsNothing);
    });

    testWidgets('never in pregnancy mode, which has no grid to fill', (tester) async {
      final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      await toBottom(tester);

      expect(find.textContaining('Tap a day'), findsNothing);
    });
  });

  /// The month grid's column headers.
  ///
  /// They came from DateFormat.E(Intl.getCurrentLocale()) — Intl's GLOBAL
  /// locale, which this app never sets — so a Russian screen was headed
  /// «Mo Tu We Th Fr Sa Su» underneath «август 2026 г.». Invisible to anyone
  /// developing in English, which is everyone who looked at it.
  group('the month grid speaks her language', () {
    Widget inLocale(AppController c, AppLocale locale) => MaterialApp(
          home: L10nScope(
            l10n: L10n(locale),
            child: WomensHealthScreen(controller: c, now: () => today),
          ),
        );

    testWidgets('Russian headers on a Russian screen', (tester) async {
      final c = controllerFor();
      addTearDown(c.dispose);
      await tester.pumpWidget(inLocale(c, AppLocale.ru));

      for (final day in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']) {
        expect(find.text(day), findsOneWidget, reason: '$day is missing');
      }
      expect(find.text('Mo'), findsNothing, reason: 'English leaked onto a Russian screen');
    });

    testWidgets('and Kazakh on a Kazakh one', (tester) async {
      final c = controllerFor();
      addTearDown(c.dispose);
      await tester.pumpWidget(inLocale(c, AppLocale.kk));

      // Дс Сс Ср Бс Жм Сн Жс — and all seven distinct, which the platform's
      // narrow names are not.
      //
      // Saturday used to be asserted here as «Сб», the Russian Суббота, because
      // that is what the catalogue held; the test locked the bug in rather than
      // catching it. Сенбі abbreviates to «Сн». Wednesday «Ср» genuinely is the
      // same string in both languages (Сәрсенбі / Среда).
      for (final day in ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сн', 'Жс']) {
        expect(find.text(day), findsOneWidget, reason: '$day is missing');
      }
    });

    testWidgets('seven columns, none of them the same', (tester) async {
      // The reason these are ours and not MaterialLocalizations.narrowWeekdays:
      // the Russian narrow set is В П В С Ч П С, and three columns cannot be
      // told apart from their header.
      final c = controllerFor();
      addTearDown(c.dispose);
      await tester.pumpWidget(inLocale(c, AppLocale.ru));

      final labels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      expect(labels.toSet(), hasLength(7));
    });
  });

  /// WHICH calendar is on screen, when more than one could apply.
  ///
  /// docs/CLAUDE-app-design.md, ЧАСТЬ 4 rule 2: «Приоритет: беременность →
  /// развитие → цикл.» One calendar, derived. The three chips that briefly let
  /// her override this are gone — the rule forbids them in terms, and they let
  /// a pregnant woman open a cycle calendar. calendar_one_test.dart is the
  /// guard on that; these are the priority order itself.
  group('the calendar opens on the stage she is at', () {
    testWidgets('pregnant outranks everything', (tester) async {
      final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
      c.addChild(ChildProfile(
          id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 400))));
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      expect(find.text('Week 20, Day 0'), findsOneWidget);
    });

    testWidgets('a child with a birth date outranks the cycle', (tester) async {
      final c = controllerFor();
      c.addChild(ChildProfile(
          id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 120))));
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      // The development timeline, not the month grid: no cycle legend is drawn
      // because no cycle calendar is on screen.
      expect(find.text('Cycle paused after birth'), findsNothing);
      expect(find.textContaining('Recovery after birth'), findsOneWidget);
    });

    testWidgets('a child with no birth date falls through to the cycle', (tester) async {
      // There is no age to place her on the timeline, so a development calendar
      // is not possible — falling through is right rather than a hole.
      final c = controllerFor();
      c.addChild(const ChildProfile(id: 'k', name: 'Baby'));
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      // 'Log period' is the cycle screen's own action — it is rendered only in
      // cycle mode, so it is a marker that cannot be true of the other two.
      expect(find.text('Log period'), findsOneWidget);
    });

    testWidgets('neither: the cycle', (tester) async {
      final c = controllerFor();
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      // 'Log period' is the cycle screen's own action — it is rendered only in
      // cycle mode, so it is a marker that cannot be true of the other two.
      expect(find.text('Log period'), findsOneWidget);
    });
  });

  group('the development calendar, when it is the one she is on', () {
    testWidgets('shows what the baby can do now', (tester) async {
      final c = controllerFor();
      addTearDown(c.dispose);
      c.addChild(ChildProfile(
          id: 'k', name: 'Baby', dateOfBirth: today.subtract(const Duration(days: 270))));
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      // The development timeline, not the cycle grid. No tap: she is on it
      // because of where she is, not because she picked it.
      expect(find.text('Track your cycle'), findsNothing);
      expect(find.text('Log period'), findsNothing);
      expect(find.textContaining('Baby'), findsWidgets);
    });
  });
  group('«История» on the contraction timer', () {
    // The timer renders the action only when it is given a callback, so an
    // unwired call site produced no visible defect — just a capability nobody
    // could reach. That is this repository's dominant failure mode, so it gets
    // a test rather than a note.

    testWidgets('is absent before she has ever finished a session',
        (tester) async {
      // An action that opens an empty page is worse than no action.
      final c = controllerFor(dueDate: today.add(const Duration(days: 42)));
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.timer_outlined));
      await tester.pumpAndSettle();

      expect(find.text(const L10n(AppLocale.en).t('contr_history_short')),
          findsNothing,
          reason: 'the timer offers a history she does not have yet');
    });

    testWidgets('opens the log ON TOP of the timer, which keeps running',
        (tester) async {
      // She is in labour with a clock running. Taking the timer away to show
      // her a list is not a trade she asked for, so the history is pushed over
      // it rather than replacing it.
      final c = controllerFor(dueDate: today.add(const Duration(days: 42)));
      c.logContractionSession(3, const Duration(seconds: 52),
          const Duration(minutes: 4, seconds: 45));
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.timer_outlined));
      await tester.pumpAndSettle();

      final action = find.text(const L10n(AppLocale.en).t('contr_history_short'));
      expect(action, findsOneWidget,
          reason: 'she has a finished session and no way to see it');
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text(const L10n(AppLocale.en).t('contr_history')),
          findsOneWidget,
          reason: 'the history did not open');
      // The timer is still mounted underneath, not popped.
      // skipOffstage: false — a pushed opaque route puts the one beneath it
      // offstage, and the default finder would report the timer as gone when
      // it is merely covered. Asserting the wrong thing here would have made
      // this test pass for a fix that popped the timer.
      expect(find.byType(ContractionTimerScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'the running timer was replaced by the list, not covered by it');
    });
  });

}
