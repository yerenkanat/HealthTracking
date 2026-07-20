/// On-device notifications. Kept behind a small interface so the pure-Dart
/// AppController never depends on the Flutter plugin — the runtime (main.dart)
/// subscribes to the controller's new-alert stream and calls [show] here.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract class NotificationService {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> show({required String title, required String body});

  /// Schedule a one-off notification for [at] (a wall-clock local time). A past
  /// time is ignored. [id] must be stable so it can be cancelled/replaced.
  Future<void> scheduleAt({required int id, required String title, required String body, required DateTime at});

  /// Schedule a notification that repeats every day at [hour]:[minute] (local).
  /// Re-calling with the same [id] replaces it.
  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute});

  /// Cancel a previously scheduled notification by [id] (no-op if none).
  Future<void> cancel(int id);
}

/// No-op implementation (tests, or platforms without support).
class NoopNotificationService implements NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> show({required String title, required String body}) async {}
  @override
  Future<void> scheduleAt({required int id, required String title, required String body, required DateTime at}) async {}
  @override
  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute}) async {}
  @override
  Future<void> cancel(int id) async {}
}

class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'safety_alerts';
  static const _channelName = 'Safety alerts';
  static const _reminderChannelId = 'reminders';
  static const _reminderChannelName = 'Reminders';
  int _id = 0;
  bool _tzReady = false;

  @override
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    final android13 = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Zone entry and exit alerts for your children',
      importance: Importance.high,
    ));
    await android13?.createNotificationChannel(const AndroidNotificationChannel(
      _reminderChannelId,
      _reminderChannelName,
      description: 'Appointment and health reminders',
      importance: Importance.high,
    ));
    await _initTimezone();
  }

  /// Load the tz database and point tz.local at the device's ACTUAL zone.
  ///
  /// This used to pick the first zone in the database whose current offset
  /// matched the device. That is not the same thing: on a UTC+5 device it
  /// selected Antarctica/Mawson rather than Asia/Almaty, and on UTC+0 it
  /// selected Africa/Abidjan rather than Europe/London. Same offset today,
  /// different rules tomorrow — daily reminders repeat by wall-clock time in
  /// tz.local, and none of those stand-ins observe DST, so a 09:00 reminder
  /// would arrive at 10:00 for half the year anywhere that does. Kazakhstan
  /// dropped DST in 2005, which is why this never showed up locally.
  Future<void> _initTimezone() async {
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      _tzReady = true;
    } catch (_) {
      // An unknown or unavailable zone name must not take reminders down with
      // it: fall back to the app's primary region rather than leaving tz unset,
      // which would make every schedule call silently do nothing.
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Almaty'));
        _tzReady = true;
      } catch (_) {
        _tzReady = false;
      }
    }
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  @override
  Future<void> show({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(_id++, title, body, details);
  }

  @override
  Future<void> scheduleAt({required int id, required String title, required String body, required DateTime at}) async {
    if (!_tzReady) return; // no zone → can't schedule safely
    final when = tz.TZDateTime.from(at, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return; // past → skip
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId, _reminderChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    // Inexact scheduling avoids needing the SCHEDULE_EXACT_ALARM permission;
    // reminders don't need second-precision.
    await _plugin.zonedSchedule(
      id, title, body, when, details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute}) async {
    if (!_tzReady) return;
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1)); // next occurrence
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId, _reminderChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.zonedSchedule(
      id, title, body, when, details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily at this time
    );
  }

  @override
  Future<void> cancel(int id) async => _plugin.cancel(id);
}
