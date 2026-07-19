/// Unit tests for the period-reminder scheduling on the controller.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/cycle_log.dart';

void main() {
  final today = DateTime(2026, 7, 16);

  // Two ~28-day periods so the cycle predicts a next period ~3 weeks out.
  void seedCycle(AppController c) {
    for (final start in [today.subtract(const Duration(days: 6)), today.subtract(const Duration(days: 34))]) {
      for (var i = 0; i < 3; i++) {
        c.toggleFlowFor(start.add(Duration(days: i)), Flow.medium);
      }
    }
  }

  test('enabling schedules a reminder ~2 days before the predicted period', () async {
    final c = AppController(now: () => today);
    seedCycle(c);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.setPeriodReminder(true);
    await Future<void>.delayed(Duration.zero);

    final scheduled = cmds.where((r) => r.at != null).toList();
    expect(scheduled, isNotEmpty);
    final next = c.cycle.nextPeriodStart!;
    final expected = DateTime(next.year, next.month, next.day, 10).subtract(const Duration(days: 2));
    expect(scheduled.last.at, expected);
    expect(scheduled.last.title, isNotEmpty);

    await sub.cancel();
    await c.dispose();
  });

  test('disabling cancels the reminder', () async {
    final c = AppController(now: () => today);
    seedCycle(c);
    c.setPeriodReminder(true);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.setPeriodReminder(false);
    await Future<void>.delayed(Duration.zero);
    expect(cmds.last.at, isNull); // cancel
    expect(c.periodReminderEnabled, isFalse);

    await sub.cancel();
    await c.dispose();
  });

  test('logging a new period reschedules the reminder', () async {
    final c = AppController(now: () => today);
    seedCycle(c);
    c.setPeriodReminder(true);
    final firstNext = c.cycle.nextPeriodStart!;

    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);
    // Log a fresh period today → prediction shifts → a new schedule is emitted.
    c.toggleFlowFor(today, Flow.medium);
    await Future<void>.delayed(Duration.zero);

    final scheduled = cmds.where((r) => r.at != null).toList();
    expect(scheduled, isNotEmpty);
    expect(c.cycle.nextPeriodStart, isNot(firstNext)); // prediction moved

    await sub.cancel();
    await c.dispose();
  });

  test('fertile reminder schedules for the fertile-window start', () async {
    final c = AppController(now: () => today);
    seedCycle(c);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.setFertileReminder(true);
    await Future<void>.delayed(Duration.zero);

    final scheduled = cmds.where((r) => r.at != null).toList();
    expect(scheduled, isNotEmpty);
    final fs = c.cycle.fertileStart!;
    expect(scheduled.last.at, DateTime(fs.year, fs.month, fs.day, 10));

    // Disabling cancels it.
    cmds.clear();
    c.setFertileReminder(false);
    await Future<void>.delayed(Duration.zero);
    expect(cmds.any((r) => r.at == null), isTrue);
    expect(c.fertileReminderEnabled, isFalse);

    await sub.cancel();
    await c.dispose();
  });

  test('period + fertile reminders are independent', () async {
    final c = AppController(now: () => today);
    seedCycle(c);
    c.setPeriodReminder(true); // period on, fertile off
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);
    // A cycle change reconciles both; the period one schedules, the fertile one cancels.
    c.toggleFlowFor(today, Flow.medium);
    await Future<void>.delayed(Duration.zero);
    expect(cmds.any((r) => r.at != null), isTrue); // period scheduled
    expect(cmds.any((r) => r.at == null), isTrue); // fertile cancelled
    await sub.cancel();
    await c.dispose();
  });

  test('no cycle data → no scheduled reminder (cancels)', () async {
    final c = AppController(now: () => today);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);
    c.setPeriodReminder(true); // enabled but nothing logged
    await Future<void>.delayed(Duration.zero);
    expect(cmds.every((r) => r.at == null), isTrue);
    await sub.cancel();
    await c.dispose();
  });
}
