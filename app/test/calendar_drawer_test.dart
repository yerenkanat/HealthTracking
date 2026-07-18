/// Widget tests for the Flo-style logging drawer (run with `flutter test`).
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/ui/calendar/logging_drawer.dart';

void main() {
  Widget harness(DayLog log, {
    void Function(Mood)? onMood,
    void Function(Symptom)? onSymptom,
    void Function(Flow)? onFlow,
    VoidCallback? onKick,
    ValueChanged<String>? onSetNote,
    bool pregnant = true,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: FloStyleCalendarDrawer(
            day: DateTime(2026, 7, 15),
            log: log,
            pregnant: pregnant,
            onToggleMood: onMood ?? (_) {},
            onToggleSymptom: onSymptom ?? (_) {},
            onToggleFlow: onFlow ?? (_) {},
            onKick: onKick ?? () {},
            onResetKicks: () {},
            onSetNote: onSetNote,
          ),
        ),
      );

  testWidgets('renders mood, symptom and kick sections', (tester) async {
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15')));
    expect(find.text('How are you feeling?'), findsOneWidget);
    expect(find.text('Happy'), findsOneWidget);
    expect(find.text('Mild cramps'), findsOneWidget);
    expect(find.text('All good'), findsOneWidget);
    expect(find.text('KICK COUNTER'), findsOneWidget); // section labels are uppercased
    expect(find.byIcon(Icons.add_rounded), findsOneWidget); // the large + hit target
  });

  testWidgets('tapping a mood pill fires onToggleMood', (tester) async {
    Mood? picked;
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15'), onMood: (m) => picked = m));
    await tester.tap(find.text('Tired'));
    await tester.pump();
    expect(picked, Mood.tired);
  });

  testWidgets('tapping the + logs a kick', (tester) async {
    var kicks = 0;
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15'), onKick: () => kicks++));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(kicks, 1);
  });

  testWidgets('shows the running kick count', (tester) async {
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15', kicks: 7)));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('kicks today'), findsOneWidget);
  });

  testWidgets('cycle mode shows period flow, not the kick counter', (tester) async {
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15'), pregnant: false));
    expect(find.text('PERIOD'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Heavy'), findsOneWidget);
    expect(find.text('KICK COUNTER'), findsNothing);
  });

  testWidgets('note field shows a prefilled note and saves on submit', (tester) async {
    String? saved;
    await tester.pumpWidget(harness(
      const DayLog(date: '2026-07-15', note: 'first scan today'),
      onSetNote: (n) => saved = n,
    ));
    expect(find.text('NOTE'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'first scan today'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ultrasound went well');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(saved, 'ultrasound went well');
  });

  testWidgets('no note field when onSetNote is not wired', (tester) async {
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15')));
    expect(find.text('NOTE'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping a flow pill fires onToggleFlow', (tester) async {
    Flow? picked;
    await tester.pumpWidget(harness(const DayLog(date: '2026-07-15'), pregnant: false, onFlow: (f) => picked = f));
    await tester.tap(find.text('Medium'));
    await tester.pump();
    expect(picked, Flow.medium);
  });
}
