/// ON-DEVICE test for reminder delivery. Run against a running emulator or
/// device: `flutter test integration_test/reminder_delivery_test.dart`.
///
/// Widget tests already assert that the controller EMITS the right schedule and
/// cancel commands. They cannot see the other half — whether the plugin then
/// registers anything with Android, whether the notification channel exists,
/// whether POST_NOTIFICATIONS was granted, and whether timezone setup produced
/// a usable zone. Any one of those failing swallows every reminder in the app
/// silently: nothing throws and nothing appears. That is why "medication
/// reminders actually firing" sat unverified in the checklist follow-ups.
///
/// WHAT THIS DELIBERATELY DOES NOT ASSERT: the moment a scheduled reminder
/// arrives. The app schedules with AndroidScheduleMode.inexactAllowWhileIdle
/// on purpose, so it doesn't need the SCHEDULE_EXACT_ALARM permission — and on
/// this emulator canScheduleExactNotifications() is false, so exact alarms
/// aren't available anyway. Android batches inexact alarms and may defer them
/// for many minutes. A test asserting "arrives within N seconds" would be
/// asserting a guarantee Android never made, and would fail at random.
///
/// So delivery is proven with an immediate show() — which exercises the
/// channel, the permission and the shade end to end — while scheduling is
/// proven by the pending-request registry.
///
/// Setup note: the runtime permission must already be granted, because a
/// consent dialog has nobody to tap it during a test run and will hang it.
///   adb shell pm grant com.fcs.fcs_app android.permission.POST_NOTIFICATIONS
/// Re-granting is needed after any reinstall, which `flutter test` does itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fcs_app/data/notification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final observer = FlutterLocalNotificationsPlugin();
  late LocalNotificationService notifications;

  Future<bool> isShowing(int id) async =>
      (await observer.getActiveNotifications()).any((n) => n.id == id);
  Future<bool> isPending(int id) async =>
      (await observer.pendingNotificationRequests()).any((n) => n.id == id);

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    notifications = LocalNotificationService();
    await notifications.init();
  });

  testWidgets('notifications are permitted and enabled', (tester) async {
    // On Android 13+ POST_NOTIFICATIONS is a runtime permission. Without it
    // every reminder is dropped silently.
    final android = observer
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    expect(await android?.areNotificationsEnabled(), isTrue,
        reason: 'notifications are disabled, so nothing can ever be delivered');
  });

  testWidgets('a notification actually reaches the shade', (tester) async {
    // Proves the channel, the permission and rendering all work — the parts
    // scheduling depends on, minus Android's discretion over timing.
    await notifications.show(title: 'Umay test', body: 'delivery works');

    var delivered = false;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!delivered && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      delivered = (await observer.getActiveNotifications()).isNotEmpty;
    }
    expect(delivered, isTrue, reason: 'show() never reached the notification shade');
  });

  testWidgets('the daily medication reminder is registered with the OS', (tester) async {
    // The real id and the real call the app makes for this reminder. If
    // timezone setup had failed, scheduleDaily() would silently return and
    // nothing would be registered here — the exact silent failure this guards.
    const medReminderId = 900002;
    await notifications.cancel(medReminderId);
    expect(await isPending(medReminderId), isFalse);

    await notifications.scheduleDaily(
      id: medReminderId,
      title: 'Time for your medication',
      body: 'Tap to mark it taken.',
      hour: 9,
      minute: 30,
    );
    expect(await isPending(medReminderId), isTrue,
        reason: 'scheduleDaily registered nothing — reminders would never fire');

    // Turning a reminder off has to actually deregister it, or one the user
    // switched off keeps arriving every day.
    await notifications.cancel(medReminderId);
    expect(await isPending(medReminderId), isFalse,
        reason: 'cancel() left the reminder scheduled');
  });

  testWidgets('rescheduling replaces rather than duplicates', (tester) async {
    // Re-setting the time must not leave the old reminder behind, or the user
    // gets two notifications a day and can only turn one of them off.
    const medReminderId = 900002;
    await notifications.cancel(medReminderId);
    for (final hour in [8, 9, 10]) {
      await notifications.scheduleDaily(
        id: medReminderId, title: 'Meds', body: 'take them', hour: hour, minute: 0,
      );
    }
    final pending = await observer.pendingNotificationRequests();
    expect(pending.where((n) => n.id == medReminderId).length, 1,
        reason: 'rescheduling stacked duplicate reminders');
    await notifications.cancel(medReminderId);
  });

  testWidgets('a one-off reminder in the past is not scheduled', (tester) async {
    const id = 990303;
    await notifications.cancel(id);
    await notifications.scheduleAt(
      id: id,
      title: 'Past',
      body: 'should be ignored',
      at: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(await isPending(id), isFalse,
        reason: 'a past reminder was scheduled and would fire immediately');
  });

  testWidgets('a future one-off reminder is registered', (tester) async {
    const id = 990404;
    await notifications.cancel(id);
    await notifications.scheduleAt(
      id: id,
      title: 'Appointment',
      body: 'in an hour',
      at: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(await isPending(id), isTrue);
    await notifications.cancel(id);
    expect(await isPending(id), isFalse);
    expect(await isShowing(id), isFalse);
  });
}
