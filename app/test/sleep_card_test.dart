/// Widget tests for the dashboard Sleep card + detail screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/ui/dashboard/sleep_card.dart';

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
}
