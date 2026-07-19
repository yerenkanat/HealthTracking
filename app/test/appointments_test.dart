/// Widget tests for the appointments/reminders screen (run with `flutter test`).
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/appointments/appointments_screen.dart';

void main() {
  final today = DateTime(2026, 7, 15, 10, 0);

  Widget wrap(AppController c) => MaterialApp(
        localizationsDelegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        home: L10nScope(
          l10n: const L10n(AppLocale.en),
          child: AppointmentsScreen(controller: c, now: () => today),
        ),
      );

  testWidgets('empty state when there are no reminders', (tester) async {
    final c = AppController(now: () => today);
    await tester.pumpWidget(wrap(c));
    expect(find.textContaining('No reminders yet'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('shows upcoming reminders soonest-first with a countdown', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0));
    c.addAppointment('Ultrasound', DateTime(2026, 7, 16, 15, 30));
    await tester.pumpWidget(wrap(c));

    expect(find.text('Upcoming (2)'), findsOneWidget);
    expect(find.text('OB visit'), findsOneWidget);
    expect(find.text('Ultrasound'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget); // the 16th, one day out
    expect(find.text('in 5 days'), findsOneWidget); // the 20th
    addTearDown(c.dispose);
  });

  testWidgets('past-only defaults to the Past tab', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('Old scan', DateTime(2026, 7, 1, 12, 0));
    await tester.pumpWidget(wrap(c));
    expect(find.text('Past (1)'), findsOneWidget);
    expect(find.text('Old scan'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('the tabs switch between upcoming and past', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('Future visit', DateTime(2026, 7, 20, 9, 0));
    c.addAppointment('Old scan', DateTime(2026, 7, 1, 12, 0));
    await tester.pumpWidget(wrap(c));

    // Defaults to Upcoming: future shown, past hidden.
    expect(find.text('Future visit'), findsOneWidget);
    expect(find.text('Old scan'), findsNothing);
    // Switch to Past.
    await tester.tap(find.text('Past (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Old scan'), findsOneWidget);
    expect(find.text('Future visit'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('no search field for a short list', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0));
    await tester.pumpWidget(wrap(c));
    expect(find.widgetWithText(TextField, 'Search reminders'), findsNothing);
    addTearDown(c.dispose);
  });

  testWidgets('search appears once the list grows and filters it', (tester) async {
    final c = AppController(now: () => today);
    for (var i = 0; i < 5; i++) {
      c.addAppointment('Routine visit $i', DateTime(2026, 7, 20 + i, 9, 0));
    }
    c.addAppointment('Ultrasound', DateTime(2026, 7, 28, 9, 0), note: 'bring papers');
    await tester.pumpWidget(wrap(c));

    expect(find.widgetWithText(TextField, 'Search reminders'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ultra');
    await tester.pumpAndSettle();
    expect(find.text('Ultrasound'), findsOneWidget);
    expect(find.text('Routine visit 0'), findsNothing);
    expect(find.text('Upcoming (1)'), findsOneWidget); // counts reflect the filter

    // Matching the note works too.
    await tester.enterText(find.byType(TextField), 'papers');
    await tester.pumpAndSettle();
    expect(find.text('Ultrasound'), findsOneWidget);

    // A fruitless search says so.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching reminders.'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('tapping a reminder opens a prefilled edit sheet and saves changes', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0), note: 'bring papers');
    final id = c.appointments.single.id;
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.text('OB visit'));
    await tester.pumpAndSettle();
    // Edit sheet is prefilled.
    expect(find.text('Edit reminder'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'OB visit'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'bring papers'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'OB visit'), 'OB-GYN checkup');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Same appointment (id preserved), new title.
    expect(c.appointments.single.id, id);
    expect(c.appointments.single.title, 'OB-GYN checkup');
    expect(find.text('OB-GYN checkup'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('deleting a reminder (via the menu) asks to confirm; confirming removes it', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0));
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this reminder?'), findsOneWidget);
    await tester.tap(find.text('Remove')); // dialog confirm
    await tester.pumpAndSettle();
    expect(c.appointments, isEmpty);
    expect(find.textContaining('No reminders yet'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('quick reschedule +1 week shifts the appointment', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0));
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move +1 week'));
    await tester.pumpAndSettle();

    expect(c.appointments.single.at, DateTime(2026, 7, 27, 9, 0)); // +7 days
    addTearDown(c.dispose);
  });
}
