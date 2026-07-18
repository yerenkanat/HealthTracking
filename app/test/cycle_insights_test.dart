/// Widget tests for the Cycle Insights screen.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/cycle_insights_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: CycleInsightsScreen(controller: c)),
      );

  testWidgets('empty state when nothing is logged', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('Log period days'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('shows history + symptom frequency from logged periods', (tester) async {
    final c = AppController(now: () => today);
    // Two ~28-day periods, 5 days each, with a couple of symptoms.
    for (final start in [today.subtract(const Duration(days: 6)), today.subtract(const Duration(days: 34))]) {
      for (var i = 0; i < 5; i++) {
        final d = start.add(Duration(days: i));
        c.setDayLog(DayLog(date: dateKey(d), flow: Flow.medium, symptoms: const {Symptom.cramps}));
      }
    }
    await tester.pumpWidget(wrap(c));
    expect(find.text('Cycle insights'), findsOneWidget); // app bar
    expect(find.text('CYCLE HISTORY'), findsOneWidget); // section
    expect(find.text('COMMON SYMPTOMS'), findsOneWidget);
    expect(find.text('Mild cramps'), findsOneWidget); // logged symptom
    expect(find.text('Ongoing'), findsOneWidget); // most recent cycle
    addTearDown(c.dispose);
  });

  testWidgets('recent notes section lists days that have a note', (tester) async {
    final c = AppController(now: () => today);
    // A logged period (so hasData) + a couple of day notes.
    for (var i = 0; i < 3; i++) {
      c.setDayLog(DayLog(date: dateKey(today.subtract(Duration(days: 6 + i))), flow: Flow.medium));
    }
    c.setNoteFor(DateTime(2026, 7, 10), 'first ultrasound');
    c.setNoteFor(DateTime(2026, 7, 12), 'felt some cramps');
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('RECENT NOTES'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('first ultrasound'), findsOneWidget);
    expect(find.text('felt some cramps'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('regularity card appears with 2+ completed cycles', (tester) async {
    final c = AppController(now: () => today);
    // Three ~28-day periods → two completed cycles → "regular".
    for (final start in [
      today.subtract(const Duration(days: 6)),
      today.subtract(const Duration(days: 34)),
      today.subtract(const Duration(days: 62)),
    ]) {
      for (var i = 0; i < 5; i++) {
        c.setDayLog(DayLog(date: dateKey(start.add(Duration(days: i))), flow: Flow.medium));
      }
    }
    await tester.pumpWidget(wrap(c));
    expect(find.text('Your cycle is regular'), findsOneWidget);
    expect(find.textContaining('28-day average'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
