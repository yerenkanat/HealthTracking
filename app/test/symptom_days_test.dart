/// Widget tests for the symptom drill-down, including opening a day for editing.
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/symptom_days_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  AppController seeded() {
    final c = AppController(now: () => today);
    c.setDayLog(const DayLog(date: '2026-07-10', symptoms: {Symptom.cramps}));
    c.setDayLog(const DayLog(date: '2026-07-12', symptoms: {Symptom.cramps, Symptom.headache}));
    return c;
  }

  Widget wrap(AppController? c, {List<DayLog>? logs}) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: SymptomDaysScreen(
            logs: logs ?? c!.dayLogs.values.toList(),
            symptom: Symptom.cramps,
            controller: c,
          ),
        ),
      );

  testWidgets('lists the days a symptom was logged', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));
    expect(find.text('Logged on 2 days'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('tapping a day opens the shared log editor', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.textContaining('July').first);
    await tester.pumpAndSettle();
    expect(find.text('How are you feeling?'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('an edit made in the sheet updates the list behind it', (tester) async {
    final c = seeded();
    await tester.pumpWidget(wrap(c));
    expect(find.text('Logged on 2 days'), findsOneWidget);

    // Clearing cramps on one day drops it out of the drill-down.
    c.toggleSymptomFor(DateTime(2026, 7, 10), Symptom.cramps);
    await tester.pumpAndSettle();
    expect(find.text('Logged on 1 days'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('read-only without a controller', (tester) async {
    await tester.pumpWidget(wrap(null, logs: const [
      DayLog(date: '2026-07-10', symptoms: {Symptom.cramps}),
    ]));
    await tester.tap(find.textContaining('July').first);
    await tester.pumpAndSettle();
    expect(find.text('How are you feeling?'), findsNothing);
  });
}
