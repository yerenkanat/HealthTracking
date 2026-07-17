/// Unit tests for appointment → reminder-command scheduling on the controller.
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';

void main() {
  final now = DateTime(2026, 7, 15, 10, 0);

  test('a future appointment emits a schedule command; removing it cancels', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addAppointment('OB visit', DateTime(2026, 7, 20, 9, 0), note: 'bring papers');
    await Future<void>.delayed(Duration.zero);
    expect(cmds.length, 1);
    expect(cmds.first.at, DateTime(2026, 7, 20, 9, 0));
    expect(cmds.first.title, 'OB visit');
    expect(cmds.first.body, 'bring papers');
    final scheduledId = cmds.first.id;

    final apptId = c.appointments.first.id;
    expect(scheduledId, AppController.reminderIdFor(apptId));

    c.removeAppointment(apptId);
    await Future<void>.delayed(Duration.zero);
    expect(cmds.length, 2);
    expect(cmds.last.at, isNull); // cancel
    expect(cmds.last.id, scheduledId);

    await sub.cancel();
    await c.dispose();
  });

  test('a past appointment does not schedule anything', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addAppointment('Old scan', DateTime(2026, 7, 1, 9, 0));
    await Future<void>.delayed(Duration.zero);
    expect(cmds, isEmpty);

    await sub.cancel();
    await c.dispose();
  });

  test('empty note falls back to a localized body', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addAppointment('Ultrasound', DateTime(2026, 7, 20, 9, 0));
    await Future<void>.delayed(Duration.zero);
    expect(cmds.single.body, isNotEmpty);
    expect(cmds.single.body, isNot('')); // localized fallback, not blank

    await sub.cancel();
    await c.dispose();
  });
}
