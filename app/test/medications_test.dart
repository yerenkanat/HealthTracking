/// Widget tests for the medications/supplements manager and its women's-health
/// card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/medications_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: MedicationsScreen(controller: c, now: () => today),
        ),
      );

  testWidgets('empty state invites you to add something', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('Nothing added yet'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('adding a medication lists it with dose and per-day', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Iron');
    await tester.enterText(find.widgetWithText(TextField, 'Dose (optional)'), '27 mg');
    await tester.tap(find.widgetWithText(ChoiceChip, '2')); // twice a day
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(c.medications.single.name, 'Iron');
    expect(c.medications.single.perDay, 2);
    expect(find.text('Iron'), findsOneWidget);
    expect(find.textContaining('27 mg'), findsOneWidget);
    // Both the day header and the row read "0/2" here (1 med × 2 doses).
    expect(find.text('0/2'), findsNWidgets(2));
    addTearDown(c.dispose);
  });

  testWidgets('ticking doses advances progress and completes the day', (tester) async {
    final c = AppController(now: () => today);
    c.addMedication('Folic acid', dose: '400 mcg');
    await tester.pumpWidget(wrap(c));

    expect(find.text('0/1'), findsNWidgets(2)); // header + row
    await tester.tap(find.byTooltip('Mark a dose taken'));
    await tester.pumpAndSettle();

    expect(c.medLog[dateKeyFor(today)]?[c.medications.single.id], 1);
    expect(find.text('1/1'), findsNWidgets(2));
    addTearDown(c.dispose);
  });

  testWidgets('undo steps a dose back', (tester) async {
    final c = AppController(now: () => today);
    c.addMedication('Iron', perDay: 2);
    final id = c.medications.single.id;
    c.takeMedicationDose(id, today);
    c.takeMedicationDose(id, today);
    await tester.pumpWidget(wrap(c));

    expect(find.text('2/2'), findsWidgets);
    await tester.tap(find.byTooltip('Undo a dose'));
    await tester.pumpAndSettle();
    expect(c.medLog[dateKeyFor(today)]?[id], 1);
    addTearDown(c.dispose);
  });

  testWidgets('removing a medication asks to confirm; cancel keeps it', (tester) async {
    final c = AppController(now: () => today);
    c.addMedication('Iron');
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from your list?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.medications, hasLength(1)); // nothing lost on cancel
    addTearDown(c.dispose);
  });

  testWidgets('confirming removal drops it and its recorded doses', (tester) async {
    final c = AppController(now: () => today);
    c.addMedication('Iron');
    final id = c.medications.single.id;
    c.takeMedicationDose(id, today);
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove')); // dialog confirm
    await tester.pumpAndSettle();

    expect(c.medications, isEmpty);
    expect(c.medLog.values.any((d) => d.containsKey(id)), isFalse); // doses pruned
    addTearDown(c.dispose);
  });

  testWidgets('card summarises today and ticks a dose', (tester) async {
    final c = AppController(now: () => today);
    c.addMedication('Folic acid');
    c.addMedication('Iron', perDay: 2);
    // The card reads the controller directly and relies on an ancestor
    // StreamBuilder to rebuild — exactly how women's health hosts it.
    await tester.pumpWidget(MaterialApp(
      home: L10nScope(
        l10n: const L10n(AppLocale.en),
        child: Scaffold(
          body: StreamBuilder<void>(
            stream: c.changes,
            builder: (_, __) => ListView(children: [
              MedicationCard(controller: c, today: today, onOpen: () {}),
            ]),
          ),
        ),
      ),
    ));

    expect(find.text('0/3'), findsOneWidget); // 1 + 2 planned
    await tester.tap(find.byTooltip('Mark a dose taken').first);
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    addTearDown(c.dispose);
  });
}

/// Local mirror of the domain's dateKey so the test asserts against the same
/// key shape the log uses.
String dateKeyFor(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
