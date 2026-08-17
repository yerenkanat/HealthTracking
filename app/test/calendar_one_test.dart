/// «Календарь один, вкладок сверху нет.»
///
/// docs/CLAUDE-app-design.md, ЧАСТЬ 4 rule 2, in full:
///
///   «Календарь один, вкладок сверху нет. Беременна — цикл скрыт полностью.
///    Родила — развитие вместо беременности. Цикл возвращается после первых
///    месячных. Переключение — событием в «⋯» («Тест положительный», «Я
///    родила»), не табом. Приоритет: беременность → развитие → цикл.»
///
/// The screen shipped a three-chip bar — Цикл · Беременность · Ребёнок — across
/// the top, which the rule forbids in terms. The reason the rule exists is the
/// first clause: a pregnant woman could tap «Цикл» and be handed ovulation
/// predictions and a fertile window for a body that is not producing them. A
/// tab is a hole straight through the one thing the rule is protecting.
///
/// So these tests assert the DERIVATION and the EVENTS, not the widgets:
///   · exactly one calendar is on screen, and which one follows her state,
///   · the other two are not reachable — not dimmed, not behind a tab, absent,
///   · and each transition happens because she reported something.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/pregnancy_hero.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';
import 'package:fcs_app/ui/tracking/child_development_screen.dart'
    show ChildDevelopmentTimeline;

void main() {
  final today = DateTime(2026, 7, 16);
  const en = L10n(AppLocale.en);

  AppController blank() => AppController(now: () => today);

  // L10nScope ABOVE MaterialApp, not at `home:`. Half these tests open a date
  // picker or a bottom sheet, which are PUSHED routes: under `home:` the scope
  // sits below the Navigator and every one of them falls back to English
  // silently. See lib/app/app.dart, which gets this right.
  Widget wrap(AppController c) => L10nScope(
        l10n: en,
        child: MaterialApp(
          home: WomensHealthScreen(controller: c, now: () => today),
        ),
      );

  // The three calendars, identified by something only they render.
  Finder pregnancyCalendar() => find.byType(PregnancyHero);
  Finder developmentCalendar() => find.byType(ChildDevelopmentTimeline);
  // The one-tap period bar is cycle-mode-only, and it is the control the whole
  // cycle calendar is for. It carries either label depending on whether today
  // is already marked, and both mean the same thing here: the cycle calendar
  // is on screen.
  Finder cycleCalendar() => find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == en.t('cyc_log_period') ||
                w.data == en.t('cyc_period_logged')),
        description: "the cycle calendar's period bar",
      );

  ChildProfile babyBornDaysAgo(int days) => ChildProfile(
        id: 'c1',
        name: 'Aisha',
        dateOfBirth: today.subtract(Duration(days: days)),
      );

  Future<void> openEvents(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
  }

  // ---- the tabs are gone ---------------------------------------------------

  testWidgets('there is no tab bar: exactly one calendar is on screen',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(cycleCalendar(), findsOneWidget);
    expect(pregnancyCalendar(), findsNothing);
    expect(developmentCalendar(), findsNothing);
    // And nothing to switch it with. The bar was three chips in a Row at the
    // very top of the list; these were its labels.
    for (final label in ['Cycle', 'Pregnancy', 'Child']) {
      expect(find.text(label), findsNothing,
          reason: '«вкладок сверху нет» — $label is a mode tab');
    }
  });

  testWidgets('pregnant: the cycle is hidden completely, not one tap away',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.setDueDate(today.add(const Duration(days: 140))); // week 20
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(pregnancyCalendar(), findsOneWidget);
    // «Беременна — цикл скрыт полностью.» This is the clause the tab bar broke.
    expect(cycleCalendar(), findsNothing);
    expect(find.text(en.t('cyc_no_data_title')), findsNothing);
    expect(developmentCalendar(), findsNothing);
    // "not one tap away" is the half the assertions above do NOT cover: the
    // tab bar never rendered a cycle HEADER in pregnancy mode either, so all of
    // the above passed while the chip that opened one sat at the top of the
    // screen. The chip is what has to be absent.
    expect(find.text('Cycle'), findsNothing,
        reason: 'a control that opens a cycle calendar from pregnancy mode');
  });

  testWidgets('pregnant: the «⋯» menu offers no way back to a cycle calendar',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.setDueDate(today.add(const Duration(days: 140)));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();
    await openEvents(tester);

    // The only event that can happen next is the end of the pregnancy.
    expect(find.text(en.t('evt_gave_birth')), findsOneWidget);
    expect(find.text(en.t('evt_test_positive')), findsNothing);
    expect(find.text(en.t('evt_period_back')), findsNothing,
        reason: 'a cycle event during pregnancy would reopen the cycle '
            'calendar the rule hides');
  });

  // ---- priority: pregnancy → development → cycle ---------------------------

  testWidgets('pregnancy outranks a newborn when both could apply',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(40)); // development would otherwise win
    c.setDueDate(today.add(const Duration(days: 100)));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(pregnancyCalendar(), findsOneWidget);
    expect(developmentCalendar(), findsNothing);
    expect(cycleCalendar(), findsNothing);
  });

  testWidgets('after a birth: development instead of pregnancy, and no cycle',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(40));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(developmentCalendar(), findsOneWidget);
    expect(pregnancyCalendar(), findsNothing);
    // Her cycle has not restarted; predicting from the pre-pregnancy logs would
    // be a prediction about a body that is not producing one.
    expect(cycleCalendar(), findsNothing);
  });

  testWidgets('the development calendar is a phase, not a life sentence',
      (tester) async {
    // A mother whose youngest is four is not postpartum. Bounding the middle
    // rung by "a child with a birth date exists" — which is true forever —
    // would have left her with a toddler timeline and NO cycle calendar, with
    // no tab left to escape through.
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(4 * 365));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(cycleCalendar(), findsOneWidget);
    expect(developmentCalendar(), findsNothing);
  });

  testWidgets('the cycle returns once a period is logged after the birth',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(200));
    c.toggleFlowFor(today.subtract(const Duration(days: 5)), Flow.medium);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    expect(cycleCalendar(), findsOneWidget, reason: '«цикл возвращается после '
        'первых месячных»');
    expect(developmentCalendar(), findsNothing);
  });

  // ---- the events -----------------------------------------------------------

  testWidgets('«The test is positive» opens the pregnancy calendar',
      (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();
    await openEvents(tester);

    await tester.tap(find.text(en.t('evt_test_positive')));
    await tester.pumpAndSettle();
    // A due-date picker, not a silent mode flip: the calendar needs the date.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(c.dueDate, isNotNull);
    expect(pregnancyCalendar(), findsOneWidget);
    expect(cycleCalendar(), findsNothing);
  });

  testWidgets('«My period is back» is reachable, and is the only way it can be',
      (tester) async {
    // The development calendar has no month grid and no period bar, so without
    // this event a mother could not log her first period at all, and the rule
    // «цикл возвращается после первых месячных» would be unimplementable — she
    // would sit in the development calendar until the child's first birthday.
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(120));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();
    expect(cycleCalendar(), findsNothing, reason: 'no period bar in this mode');

    await openEvents(tester);
    await tester.tap(find.text(en.t('evt_period_back')));
    await tester.pumpAndSettle();

    expect(c.logFor(today).hasPeriod, isTrue);
    expect(c.isPostpartum, isFalse);
    expect(cycleCalendar(), findsOneWidget);
    expect(developmentCalendar(), findsNothing);
  });

  // ---- every event is reversible ------------------------------------------

  testWidgets('«My period is back» can be undone', (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    c.addChild(babyBornDaysAgo(120));
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();
    await openEvents(tester);
    await tester.tap(find.text(en.t('evt_period_back')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(en.t('act_undo')));
    await tester.pumpAndSettle();

    expect(c.logFor(today).hasPeriod, isFalse);
    expect(developmentCalendar(), findsOneWidget);
    expect(cycleCalendar(), findsNothing);
  });

  testWidgets('undoing a birth restores the pregnancy AND removes the child',
      (tester) async {
    // A claim about her body, tapped by mistake, must not cost her the calendar
    // she has been counting on for months. Restoring one half without the other
    // would leave a phantom newborn in the family list beside a live pregnancy.
    final c = blank();
    addTearDown(c.dispose);
    final due = today.subtract(const Duration(days: 2));
    c.setDueDate(due);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    await openEvents(tester);
    await tester.tap(find.text(en.t('evt_gave_birth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t('birth_born')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // the birth date, defaulted to the due date
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t('birth_save'))); // no name yet
    await tester.pumpAndSettle();
    expect(c.children, hasLength(1));

    await tester.tap(find.text(en.t('act_undo')));
    await tester.pumpAndSettle();

    expect(c.children, isEmpty);
    expect(c.dueDate, due);
    expect(pregnancyCalendar(), findsOneWidget);
  });

  testWidgets('turning tracking off can be undone', (tester) async {
    final c = blank();
    addTearDown(c.dispose);
    final due = today.add(const Duration(days: 90));
    c.setDueDate(due);
    await tester.pumpWidget(wrap(c));
    await tester.pumpAndSettle();

    await openEvents(tester);
    await tester.tap(find.text(en.t('evt_gave_birth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t('birth_other')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t('evt_tracking_off')));
    await tester.pumpAndSettle();
    expect(c.dueDate, isNull);
    expect(cycleCalendar(), findsOneWidget);

    await tester.tap(find.text(en.t('act_undo')));
    await tester.pumpAndSettle();

    expect(c.dueDate, due);
    expect(pregnancyCalendar(), findsOneWidget);
    expect(cycleCalendar(), findsNothing);
  });
}
