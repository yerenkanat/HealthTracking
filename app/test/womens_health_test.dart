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
    expect(find.text('Recovery after birth'), findsOneWidget);
  });

  testWidgets('no recovery card once the postpartum window has passed', (tester) async {
    // A child born long ago is not a postpartum context.
    final c = controllerFor();
    c.addChild(ChildProfile(id: 'k', name: 'Baby', dateOfBirth: DateTime(2024, 1, 1)));
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    expect(find.text('Recovery after birth'), findsNothing);
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

    await tester.tap(find.text('Recovery after birth'));
    await tester.pumpAndSettle();
    // The recovery screen's app-bar title is a reliable landing marker that
    // sits at the top, above the fold on the default test viewport.
    expect(find.text('After birth'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);
  });

  testWidgets('cycle mode shows the current phase card', (tester) async {
    final c = controllerFor(); // cycle mode, today = Jul 16
    // A period Jul 10–12 → today (Jul 16) lands after the period, before the
    // fertile window → follicular phase.
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c));
    expect(find.text('Follicular'), findsOneWidget);
    expect(find.textContaining('Day 4 of'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('cycle mode shows the fertile-window countdown when upcoming', (tester) async {
    final c = controllerFor(); // cycle mode, today = Jul 16
    // Period Jul 10–12 → fertile window opens Jul 19 (still upcoming on Jul 16).
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11), DateTime(2026, 7, 12)]) {
      c.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c));
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

    expect(find.text('Around now you often log'), findsOneWidget);
    expect(find.textContaining('Headache'), findsWidgets);
    addTearDown(c.dispose);
  });

  testWidgets('predictions show a confidence chip that grows with history', (tester) async {
    // One logged period → no completed cycles → low confidence.
    final c1 = controllerFor();
    for (final d in [DateTime(2026, 7, 10), DateTime(2026, 7, 11)]) {
      c1.toggleFlowFor(d, Flow.medium);
    }
    await tester.pumpWidget(wrap(c1));
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
    expect(find.text('building'), findsOneWidget);
    addTearDown(c2.dispose);
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

  testWidgets('pregnancy view shows the weekly baby-size card', (tester) async {
    // Due in 140 days → ~40 - 20 = week 20 → banana.
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(find.text('BABY SIZE'), findsOneWidget);
    expect(find.textContaining('About the size of a'), findsOneWidget);
    // The card also carries this week's development highlight — week 20 is the
    // hear-your-voice one — so the overview shows the wonder of the week too.
    expect(find.text('The baby can begin to hear your voice.'), findsOneWidget);
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

  testWidgets('the "No longer pregnant?" action returns to cycle mode', (tester) async {
    final c = controllerFor(dueDate: today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    expect(c.isPregnant, true);

    await tester.tap(find.text('No longer pregnant?'));
    await tester.pumpAndSettle();
    // This used to be a yes/no confirm. It is a fork now — a birth carries the
    // date into a child record, and this path just turns tracking off — so the
    // test takes the branch it was always about. birth_transition_test covers
    // the other one.
    await tester.tap(find.text('Just turn tracking off'));
    await tester.pumpAndSettle();
    expect(c.isPregnant, false);
    expect(c.children, isEmpty, reason: 'this path creates no child');
    expect(find.text('Track your cycle'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
