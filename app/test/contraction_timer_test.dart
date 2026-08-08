/// Widget tests for the contraction timer (run with `flutter test`).
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/contraction_timer_screen.dart';

void main() {
  _wakelockTests();

  Widget wrap() => const MaterialApp(
        home: L10nScope(l10n: L10n(AppLocale.en), child: ContractionTimerScreen()),
      );

  testWidgets('recorded contractions are saved on close (onSave)', (tester) async {
    int? savedCount;
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(onSave: (count, _, __) => savedCount = count),
      ),
    ));
    // Record two contractions.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(i == 0 ? 'Start' : 'Start'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Stop').first);
      await tester.pump();
    }
    // Dispose the screen (replace it) → onSave fires with the count.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(savedCount, 2);
  });

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

  testWidgets('5-1-1 card appears after two contractions', (tester) async {
    await tester.pumpWidget(wrap());
    // No card with a single contraction.
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Stop').first);
    await tester.pump();
    expect(find.text('5-1-1 pattern'), findsNothing);
    // A second contraction brings the informational 5-1-1 card in.
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Stop').first);
    await tester.pump();
    expect(find.text('5-1-1 pattern'), findsOneWidget);
    expect(find.textContaining('not medical advice'), findsOneWidget);
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

/// «Экран не гаснет» — screen 10.
///
/// A phone that sleeps mid-labour loses the interval she is timing, and she is
/// in no position to keep tapping it awake. The whole value of this screen is
/// the gap between contractions, which is exactly what a screen timeout
/// destroys.
void _wakelockTests() {
  testWidgets('holds the screen awake while it is open', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(keepAwake: (on) async => calls.add(on)),
      ),
    ));
    expect(calls, [true]);
  });

  testWidgets('lets it sleep again on the way out', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(keepAwake: (on) async => calls.add(on)),
      ),
    ));
    // Replace the screen — dispose runs.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(calls, [true, false]);
  });

  testWidgets('releases it even when nothing was recorded', (tester) async {
    // Leaving the wakelock on because the session was empty would flatten the
    // battery of a phone she is relying on to call somebody.
    final calls = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: ContractionTimerScreen(
          keepAwake: (on) async => calls.add(on),
          onSave: (_, __, ___) {},
        ),
      ),
    ));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(calls.last, false);
  });
}
