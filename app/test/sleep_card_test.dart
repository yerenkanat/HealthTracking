/// Widget tests for the dashboard Sleep card + detail screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/ui/dashboard/sleep_card.dart';
import 'package:fcs_app/ui/dashboard/sleep_detail_screen.dart';

void main() {
  final nights = [
    SleepSummary(night: DateTime(2026, 7, 15), deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25),
    SleepSummary(night: DateTime(2026, 7, 14), deepMin: 70, remMin: 90, lightMin: 250, awakeMin: 35),
  ];

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: ListView(children: [child])));

  testWidgets('renders last night total, quality and stage legend', (tester) async {
    await tester.pumpWidget(wrap(SleepCard(nights: nights)));
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('8h'), findsOneWidget); // 95+105+280 = 480 min
    expect(find.text('Good sleep'), findsOneWidget);
    expect(find.text('Deep '), findsOneWidget);
    expect(find.text('1h 35m'), findsOneWidget); // deep = 95 min
  });

  testWidgets('shows the week average alongside last night', (tester) async {
    // 480 and 410 asleep minutes → 445 avg (7h 25m).
    await tester.pumpWidget(wrap(SleepCard(nights: nights)));
    expect(find.textContaining('average this week'), findsOneWidget);
    expect(find.text('7h 25m average this week'), findsOneWidget);
  });

  testWidgets('no week average from a single night', (tester) async {
    await tester.pumpWidget(wrap(SleepCard(nights: [nights.first])));
    expect(find.textContaining('average this week'), findsNothing);
  });

  testWidgets('empty nights render nothing', (tester) async {
    await tester.pumpWidget(wrap(const SleepCard(nights: [])));
    expect(find.text('Sleep'), findsNothing);
  });

  testWidgets('tapping the card opens the sleep detail screen', (tester) async {
    await tester.pumpWidget(wrap(SleepCard(nights: nights)));
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.text('RECENT NIGHTS'), findsOneWidget); // detail chart header
    expect(find.text('Deep'), findsWidgets); // legend
  });

  testWidgets('detail screen shows a consistency read with 3+ nights', (tester) async {
    // Three nights within ~40 min of each other → "consistent".
    final threeNights = [
      SleepSummary(night: DateTime(2026, 7, 15), lightMin: 420),
      SleepSummary(night: DateTime(2026, 7, 14), lightMin: 440),
      SleepSummary(night: DateTime(2026, 7, 13), lightMin: 400),
    ];
    await tester.pumpWidget(MaterialApp(home: SleepDetailScreen(nights: threeNights)));
    expect(find.text('Your sleep is consistent'), findsOneWidget);
    expect(find.textContaining('spread between nights'), findsOneWidget);
  });

  // Without a band nothing ever records a night, so the card used to render
  // nothing at all — leaving no way to log sleep by hand.
  testWidgets('with no nights the card offers hand entry instead of vanishing', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(SleepCard(nights: const [], onLog: () => tapped = true)));
    expect(find.text('Log sleep'), findsOneWidget);
    await tester.tap(find.text('Log sleep'));
    expect(tapped, isTrue);
  });

  testWidgets('with no nights and no hand entry the card stays hidden', (tester) async {
    await tester.pumpWidget(wrap(const SleepCard(nights: [])));
    expect(find.text('Log sleep'), findsNothing);
    expect(find.text('Sleep'), findsNothing);
  });

  testWidgets('the detail screen offers hand entry too', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
        MaterialApp(home: SleepDetailScreen(nights: nights, onLog: () => tapped = true)));
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(tapped, isTrue);
  });

  testWidgets('a hand-logged night shows its total without inventing stages', (tester) async {
    // 7h30m asleep, 30 awake — and no deep/REM figure, because nobody can
    // report their own. It must still read as a good night.
    final manual = [SleepSummary.manual(night: DateTime(2026, 7, 15), asleepMin: 450, awakeMin: 30)];
    await tester.pumpWidget(wrap(SleepCard(nights: manual)));
    expect(find.text('7h 30m'), findsOneWidget);
    expect(find.text('Good sleep'), findsOneWidget);
  });
}
