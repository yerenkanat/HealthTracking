/// Widget tests for the timed kick session (run with `flutter test`).
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/kick_session_screen.dart';

void main() {
  Future<void> pumpAndOpen(
    WidgetTester tester,
    void Function(int, Duration) onSave, {
    DateTime Function()? clock,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => KickSessionScreen(
                    onSave: onSave,
                    clock: clock ?? DateTime.now,
                  ),
                ),
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
    // Seconds in, not two hours: the method has said nothing, so nothing is
    // modal and nothing has to be dismissed.
    expect(find.text('Take note of the movements'), findsNothing);
  });

  testWidgets('reaching the goal shows the goal-reached state', (tester) async {
    await pumpAndOpen(tester, (_, __) {});
    // Ten taps on the counter (label is "movement" until the goal is reached).
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    expect(find.text('10'), findsOneWidget); // count reached the goal
    expect(find.text('Goal reached'), findsOneWidget);
    // Clean up the running timer.
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
  });

  // ---- Two hours, fewer than ten ----
  //
  // The regression this covers: the count-to-ten method's own trigger was met
  // and the app said «Записано шевелений: 4» and nothing more. Reduced fetal
  // movement is the most time-critical sign she reports herself, and the app
  // already owned the sentence for it two screens away.
  testWidgets('two hours short of the goal shows the guidance and the way to the warnings', (tester) async {
    int? saved;
    var now = DateTime(2026, 3, 1, 9, 0);
    await pumpAndOpen(tester, (n, _) => saved = n, clock: () => now);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    // The window passes with the count still short of ten.
    now = now.add(const Duration(hours: 2, minutes: 5));
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();

    // The movements are saved either way — guidance never costs her the data.
    expect(saved, 4);
    expect(find.text('Take note of the movements'), findsOneWidget);
    expect(
      find.textContaining('Logged 4 movements in'),
      findsOneWidget,
      reason: 'her own numbers, stated as fact',
    );
    expect(
      find.textContaining('contact your clinic today'),
      findsOneWidget,
      reason: 'the action the method attaches to its own threshold',
    );
    expect(
      find.textContaining('tell your clinic straight away'),
      findsOneWidget,
      reason: 'the guidance the app already owns (preg_note_movement_pattern)',
    );

    // The route to the warning-signs screen, from inside the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'When to call your doctor'));
    await tester.pumpAndSettle();
    expect(find.text('The baby is moving noticeably less than usual'), findsOneWidget);

    // Coming back finishes the save and leaves the counter.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Logged 4 movements'), findsOneWidget); // the save snackbar
    expect(find.text('open'), findsOneWidget); // back on the launcher
  });

  testWidgets('dismissing the guidance still saves and leaves', (tester) async {
    int? saved;
    var now = DateTime(2026, 3, 1, 9, 0);
    await pumpAndOpen(tester, (n, _) => saved = n, clock: () => now);

    await tester.tap(find.text('movement'));
    await tester.pump();
    now = now.add(const Duration(hours: 2, minutes: 30));
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.text('Take note of the movements'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  // ---- …and NOT before the window is up ----
  //
  // Four movements in twenty minutes is a session she ended, not a signal the
  // method gave. Escalating there would train her to dismiss the dialog, so the
  // session that matters would land on a numbed reader.
  testWidgets('a session ended before two hours gets a neutral note, no escalation', (tester) async {
    int? saved;
    var now = DateTime(2026, 3, 1, 9, 0);
    await pumpAndOpen(tester, (n, _) => saved = n, clock: () => now);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    now = now.add(const Duration(minutes: 20));
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();

    expect(saved, 4);
    // No dialog, no clinic instruction, no route to the warning signs…
    expect(find.text('Take note of the movements'), findsNothing);
    expect(find.textContaining('contact your clinic today'), findsNothing);
    expect(find.widgetWithText(TextButton, 'When to call your doctor'), findsNothing);
    // …but not silence either: what the method looks for, stated neutrally.
    expect(find.text('Logged 4 movements'), findsOneWidget);
    expect(
      find.textContaining('The count-to-ten method looks for ten movements'),
      findsOneWidget,
    );
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('reaching the goal promptly saves with no guidance and no note', (tester) async {
    await pumpAndOpen(tester, (_, __) {});
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('movement'));
      await tester.pump();
    }
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
    expect(find.text('Take note of the movements'), findsNothing);
    expect(find.textContaining('The count-to-ten method looks for'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  // The guidance is medical copy, and it is read in Russian and Kazakh — never
  // in the English these tests default to. L10nScope goes ABOVE MaterialApp:
  // under `home:` it sits below the Navigator, so the PUSHED warnings screen
  // would silently fall back to English and this would prove nothing.
  for (final locale in [AppLocale.ru, AppLocale.kk]) {
    final l = L10n(locale);
    testWidgets('the guidance reads in ${locale.name} and fits a 360dp phone', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      var now = DateTime(2026, 3, 1, 9, 0);
      await tester.pumpWidget(L10nScope(
        l10n: l,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => KickSessionScreen(
                      onSave: (_, __) {},
                      clock: () => now,
                    ),
                  )),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text(l.t('kick_session_tap')));
        await tester.pump();
      }
      now = now.add(const Duration(hours: 2, minutes: 5));
      await tester.tap(find.text(l.t('kick_session_save')));
      await tester.pumpAndSettle();

      expect(find.text(l.t('kick_low_title')), findsOneWidget);
      expect(find.text(l.t('kick_low_action')), findsOneWidget);
      expect(find.text(l.t('preg_note_movement_pattern')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the guidance overflows at 360dp');

      // …and the warning-signs screen it leads to speaks the same language.
      await tester.tap(find.widgetWithText(TextButton, l.t('preg_warn_title')));
      await tester.pumpAndSettle();
      expect(find.text(l.t('preg_warn_movement')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    });
  }

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

    // Clean up: save and leave so no timer is left pending.
    await tester.tap(find.text('Save session'));
    await tester.pumpAndSettle();
  });
}
