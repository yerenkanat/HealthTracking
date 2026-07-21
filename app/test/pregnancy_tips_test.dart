/// The daily-tips shelf on the pregnancy calendar.
///
/// It reuses the dashboard's TimelineContentCard on purpose — the tips are the
/// published catalogue, not placeholder copy — so these tests check the wiring:
/// that stage-relevant content appears in pregnancy mode, and nowhere it should
/// not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/timeline_content.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/womens_health_screen.dart';

final today = DateTime(2026, 7, 22);

ContentItem tip(String id, String title) => ContentItem(
      id: id,
      kind: ContentKind.lesson,
      title: LocalizedText({'ru': title, 'en': title}),
      summary: LocalizedText({'ru': 'Описание', 'en': 'Summary'}),
      url: 'https://umay.kz/$id',
    );

final tips = [tip('t1', 'Развитие на 20 неделе'), tip('t2', 'Питание во втором триместре')];

AppController pregnant() {
  final c = AppController(now: () => today, locale: AppLocale.ru);
  c.setDueDate(today.add(const Duration(days: 140))); // ~week 20
  return c;
}

Widget wrap(AppController c, {List<ContentItem> withTips = const [], void Function(ContentItem)? onOpen}) =>
    MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.ru),
        child: WomensHealthScreen(
          controller: c,
          now: () => today,
          tips: withTips,
          onOpenTip: onOpen ?? (_) {},
          onSeeAllTips: () {},
        ),
      ),
    );

void main() {
  testWidgets('this week\'s tips appear under the pregnancy hero', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final c = pregnant();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, withTips: tips));
    await tester.pumpAndSettle();

    expect(find.text('Развитие на 20 неделе'), findsOneWidget);
  });

  testWidgets('tapping a tip routes it to the opener', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    ContentItem? opened;
    final c = pregnant();
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, withTips: tips, onOpen: (i) => opened = i));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Развитие на 20 неделе'));
    await tester.pumpAndSettle();
    expect(opened?.id, 't1');
  });

  testWidgets('the cycle calendar shows no pregnancy tips shelf', (tester) async {
    // Not pregnant: the tips belong to the pregnancy hero, and an empty shelf
    // on the cycle calendar would be clutter.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final c = AppController(now: () => today, locale: AppLocale.ru); // no due date
    addTearDown(c.dispose);
    await tester.pumpWidget(wrap(c, withTips: tips));
    await tester.pumpAndSettle();

    expect(find.text('Развитие на 20 неделе'), findsNothing);
  });
}
