/// Widget tests for the appointments/reminders screen (run with `flutter test`).
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

    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.text('OB visit'), findsOneWidget);
    expect(find.text('Ultrasound'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget); // the 16th, one day out
    expect(find.text('in 5 days'), findsOneWidget); // the 20th
    addTearDown(c.dispose);
  });

  testWidgets('past reminders appear under a Past section', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('Old scan', DateTime(2026, 7, 1, 12, 0));
    await tester.pumpWidget(wrap(c));
    expect(find.text('PAST'), findsOneWidget);
    expect(find.text('Old scan'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('deleting a reminder asks to confirm; confirming removes it', (tester) async {
    final c = AppController(now: () => today);
    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0));
    await tester.pumpWidget(wrap(c));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Delete this reminder?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(c.appointments, isEmpty);
    expect(find.textContaining('No reminders yet'), findsOneWidget);
    addTearDown(c.dispose);
  });
}
