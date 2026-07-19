/// Unit tests for the daily water-reminder command stream on the controller.
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';

void main() {
  test('setting and clearing the reminder emits the minutes then null', () async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    final emitted = <int?>[];
    final sub = c.waterReminderCommands.listen(emitted.add);

    expect(c.waterReminderMinutes, isNull);
    c.setWaterReminder(20 * 60 + 30); // 20:30
    await Future<void>.delayed(Duration.zero);
    expect(c.waterReminderMinutes, 20 * 60 + 30);
    expect(emitted.last, 20 * 60 + 30);

    c.setWaterReminder(null);
    await Future<void>.delayed(Duration.zero);
    expect(c.waterReminderMinutes, isNull);
    expect(emitted.last, isNull);

    await sub.cancel();
    await c.dispose();
  });

  test('reconcile re-emits the current setting', () async {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.setWaterReminder(8 * 60); // 08:00
    final emitted = <int?>[];
    final sub = c.waterReminderCommands.listen(emitted.add);
    c.reconcileWaterReminder();
    await Future<void>.delayed(Duration.zero);
    expect(emitted, contains(8 * 60));
    await sub.cancel();
    await c.dispose();
  });

  test('time is clamped into a valid day range', () {
    final c = AppController(now: () => DateTime(2026, 7, 15));
    c.setWaterReminder(99999);
    expect(c.waterReminderMinutes, 24 * 60 - 1);
    c.dispose();
  });
}
