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
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/content/timeline_content_card.dart';
import 'package:fcs_app/ui/dashboard/health_dashboard_screen.dart';
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
}
