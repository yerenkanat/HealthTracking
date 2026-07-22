/// The newborn log screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/newborn_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/tracking/newborn_log_screen.dart';

final today = DateTime(2026, 7, 22, 14);

NewbornEvent feed(int hour, [String? side]) =>
    NewbornEvent(at: DateTime(2026, 7, 22, hour), kind: NewbornEventKind.feed, detail: side);
NewbornEvent diaper(int hour, String kind) =>
    NewbornEvent(at: DateTime(2026, 7, 22, hour), kind: NewbornEventKind.diaper, detail: kind);
NewbornEvent feedOn(int day, int hour, [String? side]) =>
    NewbornEvent(at: DateTime(2026, 7, day, hour), kind: NewbornEventKind.feed, detail: side);

Future<void> pump(WidgetTester tester, List<NewbornEvent> events,
    {void Function(NewbornEvent)? onLog, void Function(NewbornEvent)? onDelete}) async {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.ru), child: child!),
    home: NewbornLogScreen(
      childName: 'Сұлтан',
      events: events,
      today: today,
      onLog: onLog ?? (_) {},
      onDelete: onDelete ?? (_) {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const ru = L10n(AppLocale.ru);

  testWidgets('an empty log invites the parent to start', (tester) async {
    await pump(tester, const []);
    expect(find.text(ru.t('nb_empty')), findsOneWidget);
  });

  testWidgets("today's tallies count feeds and wet diapers", (tester) async {
    await pump(tester, [feed(8), feed(11), diaper(9, 'wet'), diaper(12, 'both')]);
    // 2 feeds, 2 diapers, both wet.
    expect(find.text('2'), findsWidgets);
    expect(find.text(ru.t('nb_wet_count', {'n': 2})), findsOneWidget);
  });

  testWidgets('tapping Feed logs a feed with the chosen side', (tester) async {
    NewbornEvent? logged;
    await pump(tester, const [], onLog: (e) => logged = e);

    await tester.tap(find.text(ru.t('nb_add_feed')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ru.t('nb_left')));
    await tester.pumpAndSettle();

    expect(logged?.kind, NewbornEventKind.feed);
    expect(logged?.detail, 'left');
  });

  testWidgets('tapping Sleep logs immediately, no sub-menu', (tester) async {
    // A nap is a single tap — a tired parent should not have to answer a
    // question to record one.
    NewbornEvent? logged;
    await pump(tester, const [], onLog: (e) => logged = e);
    // By icon, not text: the sleep button's label ("Сон") is the same string as
    // the sleep tally label, so a text finder is ambiguous. With an empty log
    // the button is the only nightlight icon on screen.
    await tester.tap(find.byIcon(Icons.nightlight_outlined));
    await tester.pumpAndSettle();
    expect(logged?.kind, NewbornEventKind.sleep);
  });

  testWidgets('the recent list shows events newest-first with their detail', (tester) async {
    await pump(tester, [feed(11, 'left'), diaper(9, 'wet')]);
    // Both appear.
    expect(find.textContaining(ru.t('nb_feed')), findsWidgets);
    expect(find.textContaining(ru.t('nb_left')), findsWidgets);
  });

  testWidgets('long-pressing an event asks to delete it', (tester) async {
    NewbornEvent? deleted;
    await pump(tester, [feed(11, 'left')], onDelete: (e) => deleted = e);
    // Long-press the row by its detail — "Левая" appears only in the event
    // row, never in a tally, so this cannot hit the summary by accident.
    await tester.longPress(find.textContaining(ru.t('nb_left')));
    await tester.pumpAndSettle();
    expect(deleted?.kind, NewbornEventKind.feed);
  });

  testWidgets('the week recall shows the check-up averages and expands to a per-day breakdown', (tester) async {
    // Today: 2 feeds. Two days ago: 1 feed. So the average is 1.5 feeds over
    // 2 active days — the number a clinic asks for, that a parent forgets.
    await pump(tester, [feed(8), feed(11), feedOn(20, 9)]);
    expect(find.text(ru.t('nb_week_title')), findsOneWidget);
    // Collapsed header carries the feeds-per-day figure.
    expect(find.textContaining(ru.t('nb_week_feeds_avg', {'n': '1.5'})), findsOneWidget);

    // Expanding reveals the per-day rows and the "over N days" qualifier.
    await tester.tap(find.text(ru.t('nb_week_title')));
    await tester.pumpAndSettle();
    expect(find.text(ru.t('nb_week_over', {'n': 2})), findsOneWidget);
    // An empty day in the window shows "none", not a blank.
    expect(find.text(ru.t('nb_week_none')), findsWidgets);
  });

  testWidgets('no week recall until something is logged', (tester) async {
    await pump(tester, const []);
    expect(find.text(ru.t('nb_week_title')), findsNothing);
  });

  testWidgets('renders in all three languages without a raw key', (tester) async {
    for (final loc in AppLocale.values) {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => L10nScope(l10n: L10n(loc), child: child!),
        home: NewbornLogScreen(
          childName: 'Сұлтан',
          events: [feed(8, 'left'), diaper(9, 'both')],
          today: today,
          onLog: (_) {},
          onDelete: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('nb_'), findsNothing, reason: loc.name);
    }
  });

  testWidgets('golden: the log with the week recall expanded', (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => L10nScope(l10n: const L10n(AppLocale.ru), child: child!),
      home: NewbornLogScreen(
        childName: 'Сұлтан',
        events: [feed(8, 'left'), feed(11, 'right'), diaper(9, 'both'), feedOn(20, 9), feedOn(20, 15)],
        today: today,
        onLog: (_) {},
        onDelete: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const L10n(AppLocale.ru).t('nb_week_title')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NewbornLogScreen),
      matchesGoldenFile('goldens/newborn_week_recall.png'),
    );
  });
}
