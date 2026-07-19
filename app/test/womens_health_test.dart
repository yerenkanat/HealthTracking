/// Widget tests for the Women's Health calendar — pregnancy (gestation) vs
/// cycle mode headers.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
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
    // Confirm dialog → tap the neutral confirm ("Finish").
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(c.isPregnant, false);
    expect(find.text('Track your cycle'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
