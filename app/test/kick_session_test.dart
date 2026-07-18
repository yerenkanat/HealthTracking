/// Widget tests for the timed kick session (run with `flutter test`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';

void main() {
  Future<void> pumpAndOpen(WidgetTester tester, void Function(int, Duration) onSave) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => KickSessionScreen(onSave: onSave)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('counting movements, undo, then saving reports the count', (tester) async {
    int? saved;
    await pumpAndOpen(tester, (n, _) => saved = n);

    expect(find.text('0'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
    expect(saved, 2);
  });

  testWidgets('reaching the goal shows the goal-reached state', (tester) async {
    await pumpAndOpen(tester, (_, __) {});
    // Ten taps on the counter (label is "movement" until the goal is reached).
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    expect(find.text('10'), findsOneWidget); // count reached the goal
    expect(find.text('Goal reached 🎉'), findsOneWidget);
    // Clean up the running timer.
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
  });

  testWidgets('closing an empty session does not save and needs no confirmation', (tester) async {
    int? saved;
    await pumpAndOpen(tester, (n, _) => saved = n);

    // Nothing counted → the primary button reads "Close" and skips saving.
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('open'), findsOneWidget); // back on the launcher
  });

  testWidgets('leaving a non-empty session asks to discard', (tester) async {
    int? saved;
    await pumpAndOpen(tester, (n, _) => saved = n);

    await tester.tap(find.text('movement'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Confirmation dialog appears; cancelling keeps the session.
    expect(find.text('Discard this session?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(saved, isNull);

    // Clean up: save & leave so no timer is left pending.
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
  });
}
