/// Widget tests for the Reminders centre — the single home for period, fertile,
/// and water reminders.
library;
import 'package:flutter/material.dart' hide Flow;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/l10n/l10n_scope.dart';
import 'package:fcs_app/ui/settings/reminders_center_screen.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  Widget wrap(AppController c) => MaterialApp(
        home: L10nScope(l10n: const L10n(AppLocale.en), child: RemindersCenterScreen(controller: c)),
      );

  void seedCycle(AppController c) {
    for (final start in [today.subtract(const Duration(days: 6)), today.subtract(const Duration(days: 34))]) {
      for (var i = 0; i < 3; i++) {
        c.toggleFlowFor(start.add(Duration(days: i)), Flow.medium);
      }
    }
  }

  testWidgets('shows the active count and toggles the period reminder', (tester) async {
    final c = AppController(now: () => today);
    seedCycle(c); // cycle data → period/fertile can be scheduled
    await tester.pumpWidget(wrap(c));

    expect(find.text('0 active'), findsOneWidget);
    // Flip the period reminder on via its switch.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(c.periodReminderEnabled, isTrue);
    expect(find.text('1 active'), findsOneWidget);
    addTearDown(c.dispose);
  });

  testWidgets('cycle reminders are disabled without cycle data', (tester) async {
    final c = AppController(now: () => today); // no cycle logs
    await tester.pumpWidget(wrap(c));
    expect(find.text('Needs cycle data to schedule'), findsNWidgets(2)); // period + fertile
    // The period switch is disabled (onChanged null) → tapping does nothing.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(c.periodReminderEnabled, isFalse);
    addTearDown(c.dispose);
  });
}
