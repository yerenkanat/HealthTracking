/// Widget tests for the "Your journey" totals screen.
library;
import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/journey_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: JourneyScreen(controller: c)),
      );

  testWidgets('empty state when nothing is tracked', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('Nothing to show yet'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('shows totals for tracked data', (tester) async {
    final c = AppController(now: () => today);
    // Two day logs (one with a note) + a kick session (which also logs its day →
    // 3 logged days total).
    c.setDayLog(const DayLog(date: '2026-07-10', mood: Mood.happy, note: 'good day'));
    c.setDayLog(const DayLog(date: '2026-07-11', symptoms: {Symptom.cramps}));
    c.logKickSession(today, 8, const Duration(seconds: 300));
    await tester.pumpWidget(wrap(c));

    // A ticked-off dose also lands in the totals.
    c.addMedication('Folic acid');
    c.takeMedicationDose(c.medications.single.id, today);
    await tester.pumpWidget(wrap(c));
    expect(find.text('doses taken'), findsOneWidget);

    expect(find.text('days logged'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // 2 logs + the kick day
    expect(find.text('notes'), findsOneWidget);
    expect(find.text('kick sessions'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
