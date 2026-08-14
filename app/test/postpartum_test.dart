/// The postpartum recovery screen.
///
/// Three things that must hold: the calm "what is normal now" notes that change
/// with the days, the warning list that must ALWAYS be present and complete —
/// it is the part a mother's safety turns on — and, between them, the mood row
/// and the screening offer that only appear once there is a controller to read
/// her own entries from.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/epds.dart';
import 'package:fcs_app/domain/postpartum.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/epds_screen.dart';
import 'package:fcs_app/ui/calendar/postpartum_screen.dart';

final today = DateTime(2026, 7, 22);
DateTime birthDaysAgo(int days) => DateTime(2026, 7, 22 - days);

Future<void> pump(WidgetTester tester, int daysAgo,
    [AppLocale loc = AppLocale.ru, AppController? controller]) async {
  tester.view.physicalSize = const Size(880, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  // L10nScope ABOVE MaterialApp, not at `home:`.
  //
  // Under `home:` it sits below the Navigator, so a PUSHED route — which this
  // screen now has, the questionnaire — resolves `L10nScope.of` to the default
  // `const L10n(AppLocale.en)` instead of throwing. The pushed screen then
  // renders in English while every assertion here is in Russian, and the
  // failure reads as "the string is missing" rather than "the locale was lost".
  await tester.pumpWidget(L10nScope(
    l10n: L10n(loc),
    child: MaterialApp(
      home: PostpartumScreen(
          birthDate: birthDaysAgo(daysAgo), today: today, controller: controller),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A controller carrying [weeks] weeks of low moods, [perWeek] days each,
/// counting back from [today].
AppController lowWeeks(int weeks, {int perWeek = 3, Mood mood = Mood.sad}) {
  final c = AppController(now: () => today);
  for (var w = 0; w < weeks; w++) {
    for (var d = 0; d < perWeek; d++) {
      final day = addDays(today, -(w * 7 + d));
      c.setDayLog(DayLog(date: dateKey(day), mood: mood));
    }
  }
  return c;
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('it always leads with the disclaimer', (tester) async {
    await pump(tester, 3);
    expect(find.text(ru.t('pp_disclaimer')), findsOneWidget);
  });

  testWidgets('early on, the baby-blues note is shown', (tester) async {
    await pump(tester, 3);
    expect(find.text(ru.t('pp_note_blues')), findsOneWidget);
    expect(find.text(ru.t('pp_note_lochia_early')), findsOneWidget);
    // The after-check clearance note is not relevant yet.
    expect(find.text(ru.t('pp_note_clearance')), findsNothing);
  });

  testWidgets('after the six-week check, the notes move on', (tester) async {
    await pump(tester, 50);
    expect(find.text(ru.t('pp_note_clearance')), findsOneWidget);
    // And the acute early notes are gone.
    expect(find.text(ru.t('pp_note_lochia_early')), findsNothing);
  });

  testWidgets('the check counts down, then says have it if you have not', (tester) async {
    await pump(tester, 0);
    expect(find.text(ru.t('pp_check_in', {'n': 42})), findsOneWidget);

    await pump(tester, 50); // past the check
    expect(find.text(ru.t('pp_check_past')), findsOneWidget);
  });

  testWidgets('the whole warning list is present, at every stage', (tester) async {
    // The warnings do not depend on the day — a haemorrhage at week six is as
    // urgent as at week one.
    for (final day in [1, 30, 90]) {
      await pump(tester, day);
      expect(find.text(ru.t('pp_warn_title')), findsOneWidget, reason: 'day $day');
      for (final id in warningSigns) {
        expect(find.text(ru.t('pp_warn_$id')), findsOneWidget, reason: 'pp_warn_$id at day $day');
      }
    }
  });

  testWidgets('the mental-health red flag is never omitted', (tester) async {
    await pump(tester, 10);
    expect(find.text(ru.t('pp_warn_harm')), findsOneWidget);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await pump(tester, 20, loc);
      expect(find.textContaining('pp_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the recovery screen in the first weeks', (tester) async {
    await pump(tester, 10);
    await expectLater(
      find.byType(PostpartumScreen),
      matchesGoldenFile('goldens/postpartum_early.png'),
    );
  });

  // ---- «Как вы себя чувствуете» ------------------------------------------

  group('the mood row', () {
    testWidgets('a tap persists into the SAME day log the calendar writes',
        (tester) async {
      // Not a new store and not a new sync: the recovery screen writes the
      // day log, which is what already reaches the back office's «Дневник».
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await pump(tester, 10, AppLocale.ru, c);

      expect(c.logFor(today).mood, isNull);
      await tester.tap(find.text(ru.t('mood_sad')));
      await tester.pumpAndSettle();

      expect(c.logFor(today).mood, Mood.sad);
      expect(c.dayLogs[dateKey(today)]?.mood, Mood.sad);
    });

    testWidgets('and it reaches the sync hook /cycle/days is wired to',
        (tester) async {
      // The hook main.dart attaches on sign-in. If the row wrote the map
      // directly instead of going through setDayLog, this would stay empty and
      // the tap would never reach the server.
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      final pushed = <DayLog>[];
      c.attachCycleSync(upsert: (log) async => pushed.add(log));
      await pump(tester, 10, AppLocale.ru, c);

      await tester.tap(find.text(ru.t('mood_anxious')));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(pushed.single.mood, Mood.anxious);
      expect(pushed.single.date, dateKey(today));
    });

    testWidgets('tapping the chosen mood again clears it', (tester) async {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await pump(tester, 10, AppLocale.ru, c);

      await tester.tap(find.text(ru.t('mood_tired')));
      await tester.pumpAndSettle();
      expect(c.logFor(today).mood, Mood.tired);

      await tester.tap(find.text(ru.t('mood_tired')));
      await tester.pumpAndSettle();
      expect(c.logFor(today).mood, isNull);
    });

    testWidgets('it says «отметить» before and «отмечено» after', (tester) async {
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await pump(tester, 10, AppLocale.ru, c);

      expect(find.text(ru.t('pp_mood_cta')), findsOneWidget);
      await tester.tap(find.text(ru.t('mood_calm')));
      await tester.pumpAndSettle();
      expect(find.text(ru.t('pp_mood_saved')), findsOneWidget);
    });

    testWidgets('every mood the diary can hold is tappable here', (tester) async {
      // A mood offered on the calendar but missing here is one she cannot
      // record on the screen she actually opens after a birth.
      final c = AppController(now: () => today);
      addTearDown(c.dispose);
      await pump(tester, 10, AppLocale.ru, c);
      for (final m in Mood.values) {
        expect(find.text(ru.t('mood_${m.name}')), findsOneWidget, reason: m.name);
      }
    });
  });

  // ---- The amber card ----------------------------------------------------

  group('the four-low-weeks card', () {
    testWidgets('four low weeks raise it', (tester) async {
      final c = lowWeeks(4);
      addTearDown(c.dispose);
      await pump(tester, 30, AppLocale.ru, c);
      expect(find.text(ru.t('pp_low_run_title')), findsOneWidget);
      expect(find.text(ru.t('pp_low_run_body')), findsOneWidget);
    });

    testWidgets('three do NOT', (tester) async {
      final c = lowWeeks(3);
      addTearDown(c.dispose);
      await pump(tester, 30, AppLocale.ru, c);
      expect(find.text(ru.t('pp_low_run_title')), findsNothing);
      // The quiet offer is still there — a screening she can reach without
      // having earned an amber card.
      expect(find.text(ru.t('pp_screen_offer_title')), findsOneWidget);
    });

    testWidgets('the questionnaire is one tap away either way', (tester) async {
      for (final weeks in [0, 4]) {
        final c = lowWeeks(weeks);
        addTearDown(c.dispose);
        await pump(tester, 30, AppLocale.ru, c);
        expect(find.text(ru.t('epds_entry')), findsOneWidget, reason: '$weeks weeks');
      }
    });

    testWidgets('and it opens the questionnaire', (tester) async {
      final c = lowWeeks(4);
      addTearDown(c.dispose);
      await pump(tester, 30, AppLocale.ru, c);
      await tester.tap(find.text(ru.t('epds_entry')));
      await tester.pumpAndSettle();
      expect(find.byType(EpdsScreen), findsOneWidget);
      expect(find.text(ru.t('epds_q1')), findsNothing); // numbered on screen
      expect(find.textContaining(ru.t('epds_q1')), findsOneWidget);
    });

    testWidgets('a screening she has taken is shown with its date and score',
        (tester) async {
      final c = lowWeeks(4);
      addTearDown(c.dispose);
      c.recordEpds(EpdsResult(
          id: 'e1', takenAt: DateTime(2026, 7, 20), score: 15));
      await pump(tester, 30, AppLocale.ru, c);
      expect(find.textContaining('15'), findsWidgets);
    });
  });

  // ---- The screen without a controller ------------------------------------

  testWidgets('without a controller the recovery half still renders whole',
      (tester) async {
    // The layout suites build it this way; the calm and warning halves must
    // not depend on the new section existing.
    await pump(tester, 10);
    expect(find.text(ru.t('pp_disclaimer')), findsOneWidget);
    expect(find.text(ru.t('pp_warn_title')), findsOneWidget);
    expect(find.text(ru.t('pp_mood_title')), findsNothing);
  });
}
