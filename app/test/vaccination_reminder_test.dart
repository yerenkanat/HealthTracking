/// Unit tests for child → vaccination next-visit reminder scheduling on the
/// controller. The domain math is checked by tool/verify_vaccination.dart; this
/// asserts the controller actually EMITS a command — the "wired to nothing"
/// failure a domain runner cannot see.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/family.dart';

void main() {
  // A fixed "now". The child below turns two months on 2026-08-20, so the
  // reminder for the two-month visit is in the future.
  final now = DateTime(2026, 7, 15, 10, 0);

  ChildProfile child(String id, DateTime? dob) =>
      ChildProfile(id: id, name: 'Сұлтан', dateOfBirth: dob);

  test('adding a child with a birth date schedules the next-visit reminder', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addChild(child('kid-1', DateTime(2026, 6, 20))); // <2 months old
    await Future<void>.delayed(Duration.zero);

    expect(cmds.length, 1);
    expect(cmds.single.at, DateTime(2026, 8, 20, 10)); // turns 2 months, at 10:00
    expect(cmds.single.title, isNotEmpty);
    expect(cmds.single.body, contains('Сұлтан'));
    expect(cmds.single.id, AppController.vaccinationReminderIdFor('kid-1'));

    await sub.cancel();
    await c.dispose();
  });

  test('a child with no birth date emits a cancel, never a phantom schedule', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addChild(child('kid-2', null));
    await Future<void>.delayed(Duration.zero);

    expect(cmds.single.at, isNull); // cancel
    expect(cmds.single.id, AppController.vaccinationReminderIdFor('kid-2'));

    await sub.cancel();
    await c.dispose();
  });

  test('correcting the birth date re-emits under the same id', () async {
    final c = AppController(now: () => now);
    c.addChild(child('kid-3', DateTime(2026, 6, 20)));
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    // Move the birth date later: the two-month visit shifts with it.
    c.updateChild(child('kid-3', DateTime(2026, 7, 1)));
    await Future<void>.delayed(Duration.zero);

    expect(cmds.single.at, DateTime(2026, 9, 1, 10));
    expect(cmds.single.id, AppController.vaccinationReminderIdFor('kid-3'));

    await sub.cancel();
    await c.dispose();
  });

  test('an older child past the schedule gets a cancel, not a schedule', () async {
    final c = AppController(now: () => now);
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.addChild(child('kid-4', DateTime(2018, 1, 1))); // ~8 years, schedule done
    await Future<void>.delayed(Duration.zero);

    expect(cmds.single.at, isNull);

    await sub.cancel();
    await c.dispose();
  });

  test('removing a child cancels its vaccination reminder', () async {
    final c = AppController(now: () => now);
    c.addChild(child('kid-5', DateTime(2026, 6, 20)));
    final cmds = <ReminderCommand>[];
    final sub = c.reminderCommands.listen(cmds.add);

    c.removeChild('kid-5');
    await Future<void>.delayed(Duration.zero);

    // The cancel for the vaccination reminder is among the emitted commands.
    expect(
      cmds.where((cmd) =>
          cmd.at == null && cmd.id == AppController.vaccinationReminderIdFor('kid-5')),
      isNotEmpty,
    );

    await sub.cancel();
    await c.dispose();
  });
}
