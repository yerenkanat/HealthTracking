/// Widget tests for the Notes browser (all notes + search).
library;

import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/calendar/notes_browser_screen.dart';

void main() {
  final logs = <DayLog>[
    const DayLog(date: '2026-07-01', note: 'First ultrasound scan'),
    const DayLog(date: '2026-07-10', note: 'Felt tired all day'),
    const DayLog(date: '2026-07-08', note: 'Second scan booked'),
    const DayLog(date: '2026-07-03', mood: Mood.happy), // no note → excluded
  ];

  Widget wrap() => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: NotesBrowserScreen(logs: logs)),
      );

  testWidgets('lists every note newest-first', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('First ultrasound scan'), findsOneWidget);
    expect(find.text('Felt tired all day'), findsOneWidget);
    expect(find.text('Second scan booked'), findsOneWidget);
  });

  testWidgets('search filters notes by substring', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'scan');
    await tester.pump();
    expect(find.text('First ultrasound scan'), findsOneWidget);
    expect(find.text('Second scan booked'), findsOneWidget);
    expect(find.text('Felt tired all day'), findsNothing);
  });

  testWidgets('no match shows an empty message', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matching notes.'), findsOneWidget);
  });
}
