/// «Главная зависит от этапа … Показатели браслета всегда ниже — они не
/// главные.»
///
/// docs/CLAUDE-app-design.md §6.
///
/// The home screen opened on four band readings and never mentioned that she is
/// twenty weeks pregnant. Not because the data was missing: home_shell computed
/// the stage, fetched its content and wired both callbacks, and the dashboard
/// declared all four as constructor parameters and read none of them.
/// TimelineContentCard was already built and tested for exactly this and was
/// mounted only on the calendar.
///
/// Four dead parameters is the inverse of the wired-to-nothing defect — data
/// reaching the client and never being drawn — and it is invisible in a diff:
/// everything compiles, the widget takes what it is given, and the screen is
/// simply missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/domain/cycle_predictions.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/timeline_content_card.dart';
import 'package:fcs_app/ui/dashboard/child_hero.dart';
import 'package:fcs_app/ui/dashboard/cycle_hero.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
import 'package:fcs_app/ui/dashboard/stage_hero.dart';
import 'package:fcs_app/ui/theme.dart';

void main() {
  final at = DateTime(2026, 7, 16, 11, 58);

  ContentItem item(String id, String title) => ContentItem(
        id: id,
        kind: ContentKind.lesson,
        title: LocalizedText({'ru': title, 'kk': title, 'en': title}),
        summary: LocalizedText({'ru': 'О чём это', 'kk': 'Бұл не туралы', 'en': 'What this is'}),
        // A link, so the tile is actionable. An item with no url renders as
        // «Скоро» and is deliberately not tappable — see ContentTile.
        url: 'https://example.kz/$id',
      );

  Future<void> pump(
    WidgetTester tester, {
    TimelineStage? stage,
    List<ContentItem> items = const [],
    void Function(ContentItem)? onOpen,
    VoidCallback? onSeeAll,
  }) async {
    tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: FcsTheme.light(AppLocale.ru),
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: HealthDashboardView(
          samples: [HealthSample(at: at, heartRate: 78, spo2: 98, coreTemp: 36.6)],
          sleepNights: const [],
          currentLocale: AppLocale.ru,
          nowForAppointment: at,
          timelineStage: stage,
          timelineItems: items,
          onOpenContent: onOpen,
          onSeeAllContent: onSeeAll,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('her stage is on the home screen at all', (tester) async {
    await pump(
      tester,
      stage: TimelineStage.pregnancyWeek(20),
      items: [item('a', 'Двадцатая неделя'), item('b', 'Что происходит с малышом')],
    );
    expect(find.byType(TimelineContentCard), findsOneWidget,
        reason: 'the stage the shell computed is not drawn anywhere');
    expect(find.text('Двадцатая неделя'), findsOneWidget);
  });

  testWidgets('and it sits ABOVE the band readings', (tester) async {
    // «Показатели браслета всегда ниже — они не главные.» This is the rule the
    // screen broke: it led with four numbers off a wrist sensor.
    await pump(
      tester,
      stage: TimelineStage.pregnancyWeek(20),
      items: [item('a', 'Двадцатая неделя')],
    );
    const l = L10n(AppLocale.ru);
    final stageY = tester.getTopLeft(find.byType(TimelineContentCard)).dy;
    // _SectionLabel uppercases its text, so the raw key does not match.
    final vitalsY = tester.getTopLeft(find.text(l.t('db_vitals_section').toUpperCase())).dy;
    expect(stageY, lessThan(vitalsY),
        reason: 'the band readings still come first');
  });

  testWidgets('a child stage reaches it too, not only pregnancy', (tester) async {
    await pump(
      tester,
      stage: TimelineStage.childMonth(4),
      items: [item('m4', 'Четвёртый месяц')],
    );
    expect(find.text('Четвёртый месяц'), findsOneWidget);
  });

  testWidgets('with neither, it says what to add rather than showing nothing',
      (tester) async {
    // The card handles the empty stage itself — which is why it is safe to lead
    // with in every state instead of being hidden when she has not filled
    // anything in, the state a new user is in.
    await pump(tester);
    expect(find.byType(TimelineContentCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening an item is wired, not decorative', (tester) async {
    // The callback was passed from the shell and read by nothing, so tapping a
    // lesson could not have done anything even once the card was on screen.
    final opened = <String>[];
    await pump(
      tester,
      stage: TimelineStage.pregnancyWeek(20),
      items: [item('a', 'Двадцатая неделя')],
      onOpen: (i) => opened.add(i.id),
    );
    await tester.tap(find.text('Двадцатая неделя'));
    await tester.pumpAndSettle();
    expect(opened, ['a']);
  });

  /// … and it does not depend on owning a bracelet.
  ///
  /// The screen was `samples.isEmpty ? <checklist + manual diary> : <the whole
  /// dashboard>`, so a woman who finished onboarding as pregnant, gave a due
  /// date and has no band — which is most of them, permanently — opened «Бүгін»
  /// onto a setup checklist and «сфотографируйте тонометр». No week, no
  /// Шевеления/Самочувствие/Вес, no appointment, no shelf.
  ///
  /// It survived because every test in this file and in dashboard_screen_test
  /// passed a non-empty samples list. These pass `samples: const []`.
  group('with no band readings at all', () {
    /// [week] completed weeks, the rest of the pregnancy still to run.
    GestationInfo gest(int week) {
      final days = week * 7;
      return GestationInfo(days, week, 0, 280 - days);
    }

    final today = DateTime(2026, 8, 8);
    final cycle = CycleInfo(
      today: today,
      avgCycleLength: 28,
      avgPeriodLength: 5,
      lastPeriodStart: today.subtract(const Duration(days: 14)),
      nextPeriodStart: today.add(const Duration(days: 14)),
      ovulation: today,
      fertileStart: today.subtract(const Duration(days: 2)),
      fertileEnd: today.add(const Duration(days: 2)),
      cycleDay: 15,
      hasData: true,
    );

    Future<void> pumpEmpty(
      WidgetTester tester, {
      GestationInfo? gestation,
      String? childHeroName,
      int? childHeroAgeMonths,
      CycleInfo? cycleInfo,
      TimelineStage? stage,
      List<ContentItem> items = const [],
      VoidCallback? onLogKick,
    }) async {
      tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: FcsTheme.light(AppLocale.ru),
        home: L10nScope(
          l10n: const L10n(AppLocale.ru),
          child: HealthDashboardView(
            // The whole point: nothing from a bracelet, ever.
            samples: const [],
            nowForAppointment: at,
            gestation: gestation,
            childHeroName: childHeroName,
            childHeroAgeMonths: childHeroAgeMonths,
            cycleInfo: cycleInfo,
            timelineStage: stage,
            timelineItems: items,
            onLogKick: onLogKick,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the pregnancy hero still leads the screen', (tester) async {
      await pumpEmpty(tester, gestation: gest(22));
      const l = L10n(AppLocale.ru);
      expect(find.byType(PregnancyHero), findsOneWidget,
          reason: 'a due date does not need a bracelet reading');
      expect(find.text(l.t('hero_week_trimester', {'w': 22, 't': 2})),
          findsOneWidget);
    });

    testWidgets('with its three quick actions, and they fire', (tester) async {
      var kicked = false;
      await pumpEmpty(tester,
          gestation: gest(22), onLogKick: () => kicked = true);
      const l = L10n(AppLocale.ru);
      expect(find.text(l.t('log_kicks')), findsOneWidget);
      expect(find.text(l.t('qa_wellbeing')), findsOneWidget);
      expect(find.text(l.t('qa_weight')), findsOneWidget);
      await tester.tap(find.text(l.t('log_kicks')));
      await tester.pumpAndSettle();
      expect(kicked, isTrue);
    });

    testWidgets('and the content shelf for her week', (tester) async {
      await pumpEmpty(
        tester,
        gestation: gest(20),
        stage: TimelineStage.pregnancyWeek(20),
        items: [item('a', 'Двадцатая неделя')],
      );
      expect(find.byType(TimelineContentCard), findsOneWidget);
      expect(find.text('Двадцатая неделя'), findsOneWidget);
    });

    testWidgets('the child hero reaches a mother with no band', (tester) async {
      await pumpEmpty(tester, childHeroName: 'Алия', childHeroAgeMonths: 3);
      const l = L10n(AppLocale.ru);
      expect(find.byType(ChildHero), findsOneWidget);
      expect(find.text(l.t('childhero_age', {'name': 'Алия', 'n': 3})),
          findsOneWidget);
    });

    testWidgets('and the cycle hero, for neither state', (tester) async {
      await pumpEmpty(tester, cycleInfo: cycle);
      expect(find.byType(CycleHero), findsOneWidget);
    });

    testWidgets('the hero survives the removal of the manual diary',
        (tester) async {
      // This used to assert that screen 05's «Записывайте вручную» card sat
      // below the hero. That card is gone (hand entry removed, 2026-08-17).
      // What the test was really protecting is still here and still worth
      // pinning: with no readings at all, the stage hero is on the screen —
      // the dashboard does not collapse to an empty state for a woman who has
      // told it she is twenty-two weeks pregnant.
      await pumpEmpty(tester, gestation: gest(22));
      expect(find.byType(PregnancyHero), findsOneWidget);
    });
  });
}
