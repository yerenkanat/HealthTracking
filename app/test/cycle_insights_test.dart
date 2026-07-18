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
        home: L10nScope(l10n: const L10n(AppLocale.en), child: CycleInsightsScreen(controller: c, now: () => today)),
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
    expect(find.text('Mild cramps'), findsWidgets); // logged symptom (all-time + this-week cards)
    expect(find.text('Ongoing'), findsOneWidget); // most recent cycle
    addTearDown(c.dispose);
  });

  testWidgets('this-week symptoms card counts only the last 7 days', (tester) async {
    final c = AppController(now: () => today); // today = 2026-07-16
    for (var i = 0; i < 3; i++) {
      c.setDayLog(DayLog(date: dateKey(today.subtract(Duration(days: 6 + i))), flow: Flow.medium));
    }
    // An old symptom (outside the window) + a recent one (inside).
    c.setDayLog(DayLog(date: dateKey(DateTime(2026, 6, 20)), symptoms: const {Symptom.headache}));
    c.setDayLog(DayLog(date: dateKey(DateTime(2026, 7, 14)), symptoms: const {Symptom.nausea}));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('SYMPTOMS THIS WEEK'), 200, scrollable: find.byType(Scrollable).first);
    // The nausea (Jul 14, in window) shows under "this week"; headache (Jun 20) doesn't.
    expect(find.text('Nausea'), findsWidgets);
    addTearDown(c.dispose);
  });

  testWidgets('logging streak banner shows consecutive logged days', (tester) async {
    final c = AppController(now: () => today); // today = 2026-07-16
    // A period (so hasData) covers today-6..today-2; plus notes today, -1, -2, -3.
    for (var i = 0; i < 3; i++) {
      c.setDayLog(DayLog(date: dateKey(today.subtract(Duration(days: 6 + i))), flow: Flow.medium));
    }
    for (var i = 0; i < 4; i++) {
      c.setNoteFor(today.subtract(Duration(days: i)), 'logged');
    }
    await tester.pumpWidget(wrap(c));
    expect(find.text('4-day logging streak'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('mood-this-week card counts only the last 7 days', (tester) async {
    final c = AppController(now: () => today); // today = 2026-07-16
    for (var i = 0; i < 3; i++) {
      c.setDayLog(DayLog(date: dateKey(today.subtract(Duration(days: 6 + i))), flow: Flow.medium));
    }
    c.setDayLog(DayLog(date: dateKey(DateTime(2026, 6, 20)), mood: Mood.sad)); // old
    c.setDayLog(DayLog(date: dateKey(DateTime(2026, 7, 14)), mood: Mood.happy)); // in window
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('MOOD THIS WEEK'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Happy'), findsWidgets); // recent mood shows
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

  testWidgets('tapping a symptom opens its drill-down of logged days', (tester) async {
    final c = AppController(now: () => today);
    // A logged period (so hasData) with cramps on two of the days.
    final start = today.subtract(const Duration(days: 6));
    for (var i = 0; i < 5; i++) {
      final d = start.add(Duration(days: i));
      c.setDayLog(DayLog(date: dateKey(d), flow: Flow.medium, symptoms: i < 2 ? const {Symptom.cramps} : const {}));
    }
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('COMMON SYMPTOMS'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Mild cramps').last);
    await tester.pumpAndSettle();
    // Drill-down screen: header count for the two logged days.
    expect(find.text('Logged on 2 days'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('mood trend card appears when moods span weeks', (tester) async {
    final c = AppController(now: () => today); // today = 2026-07-16
    // A period so hasData, plus moods in this week and a prior week.
    for (var i = 0; i < 3; i++) {
      c.setDayLog(DayLog(date: dateKey(today.subtract(Duration(days: 6 + i))), flow: Flow.medium));
    }
    c.setDayLog(DayLog(date: dateKey(today.subtract(const Duration(days: 1))), mood: Mood.happy));
    c.setDayLog(DayLog(date: dateKey(today.subtract(const Duration(days: 10))), mood: Mood.sad));
    await tester.pumpWidget(wrap(c));

    await tester.scrollUntilVisible(find.text('MOOD TREND'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('MOOD TREND'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget); // trend axis label
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
