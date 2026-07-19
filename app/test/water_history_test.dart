/// Widget tests for the weekly water history screen.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/hydration.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/dashboard/water_history_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        home: L10nScope(l10n: const L10n(AppLocale.en), child: child),
      );

  final today = DateTime(2026, 7, 15);
  final log = <String, int>{
    '2026-07-15': 8, '2026-07-14': 9, '2026-07-13': 8, '2026-07-12': 3, '2026-07-11': 8,
  };

  testWidgets('shows the streak and weekly totals', (tester) async {
    final week = lastNDays(log, today, 7);
    final streak = waterStreak(log, today, 8); // 3
    await tester.pumpWidget(wrap(WaterHistoryScreen(week: week, goal: 8, streak: streak)));

    expect(find.text('3-day streak'), findsOneWidget);
    expect(find.text('Total glasses'), findsOneWidget);
    // Total = 8+9+8+3+8 = 36 across the 7-day window (two empty days).
    expect(find.text('36'), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget); // days meeting the goal
  });

  testWidgets('no-streak state', (tester) async {
    await tester.pumpWidget(wrap(WaterHistoryScreen(week: lastNDays(const {}, today, 7), goal: 8, streak: 0)));
    expect(find.text('No streak yet'), findsOneWidget);
  });

  testWidgets('read-only without a controller', (tester) async {
    await tester.pumpWidget(wrap(WaterHistoryScreen(week: lastNDays(const {}, today, 7), goal: 8, streak: 0)));
    expect(find.text('CORRECT A DAY'), findsNothing);
  });

  testWidgets('a past day can be corrected and the totals follow', (tester) async {
    final c = AppController(now: () => today);
    c.addWater(today.subtract(const Duration(days: 1)), 3); // yesterday: 3
    await tester.pumpWidget(wrap(WaterHistoryScreen(
      week: lastNDays(c.waterLog, today, 7),
      goal: 8,
      streak: 0,
      controller: c,
      now: () => today,
    )));

    await tester.scrollUntilVisible(find.text('CORRECT A DAY'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('CORRECT A DAY'), findsOneWidget);

    // Add a glass to yesterday — the stored log and the weekly total both move.
    final addYesterday = find.byTooltip('Add a glass').at(1); // row 0 = today, 1 = yesterday
    await tester.ensureVisible(addYesterday);
    await tester.pumpAndSettle();
    await tester.tap(addYesterday);
    await tester.pumpAndSettle();
    expect(c.waterFor(today.subtract(const Duration(days: 1))), 4);
    expect(find.text('4'), findsWidgets);
    addTearDown(c.dispose);
  });

  testWidgets('a day with nothing logged cannot go negative', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(WaterHistoryScreen(
      week: lastNDays(c.waterLog, today, 7),
      goal: 8,
      streak: 0,
      controller: c,
      now: () => today,
    )));
    // Every day is empty, so every remove control is disabled.
    final removes = tester.widgetList<IconButton>(
      find.ancestor(of: find.byIcon(Icons.remove_circle_outline_rounded), matching: find.byType(IconButton)),
    );
    expect(removes, isNotEmpty);
    expect(removes.every((b) => b.onPressed == null), isTrue);
    addTearDown(c.dispose);
  });
}
