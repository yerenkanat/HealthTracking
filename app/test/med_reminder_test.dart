/// Unit tests for the daily medication-reminder command stream on the
/// controller — the same schedule/cancel contract the water reminder uses.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';

void main() {
  test('setting and clearing the reminder emits the minutes then null', () async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    final emitted = <int?>[];
    final sub = c.medReminderCommands.listen(emitted.add);

    expect(c.medReminderMinutes, isNull);
    c.setMedReminder(9 * 60); // 09:00
    await Future<void>.delayed(Duration.zero);
    expect(c.medReminderMinutes, 9 * 60);
    expect(emitted.last, 9 * 60);

    c.setMedReminder(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.medReminderMinutes, isNull);
    expect(emitted.last, isNull);

    await sub.cancel();
    await c.dispose();
  });

  test('reconcile re-emits the current setting for the runtime', () async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.setMedReminder(8 * 60 + 30);
    final emitted = <int?>[];
    final sub = c.medReminderCommands.listen(emitted.add);

    c.reconcileMedReminder();
    await Future<void>.delayed(Duration.zero);
    expect(emitted, [8 * 60 + 30]);

    await sub.cancel();
    await c.dispose();
  });

  test('an out-of-range time is clamped into the day', () async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.setMedReminder(99 * 60);
    expect(c.medReminderMinutes, 24 * 60 - 1);
    await c.dispose();
  });
}
