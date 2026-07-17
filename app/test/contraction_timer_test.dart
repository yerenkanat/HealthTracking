/// Widget tests for the contraction timer (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';

void main() {
  Widget wrap() => const MaterialApp(
        home: L10nScope(l10n: L10n(AppLocale.en), child: ContractionTimerScreen()),
      );

  testWidgets('starts empty with a Start button and hint', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('No contractions recorded yet.'), findsOneWidget);
  });

  testWidgets('start → stop records one contraction with stats', (tester) async {
    await tester.pumpWidget(wrap());
    // Start a contraction.
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Stop'), findsWidgets); // button now reads Stop
    // Let ~2 seconds of the periodic ticker elapse, then stop.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Stop').first);
    await tester.pump();

    // One row recorded; back to Start; stats bar shows Total.
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('first'), findsOneWidget); // first contraction has no interval
  });

  testWidgets('reset asks to confirm and clears', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Stop').first);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restart_alt_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Reset contractions?'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('No contractions recorded yet.'), findsOneWidget);
  });
}
