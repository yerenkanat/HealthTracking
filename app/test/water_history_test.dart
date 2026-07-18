/// Widget tests for the weekly water history screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
