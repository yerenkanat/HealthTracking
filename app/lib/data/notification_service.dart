/// On-device notifications. Kept behind a small interface so the pure-Dart
/// AppController never depends on the Flutter plugin — the runtime (main.dart)
/// subscribes to the controller's new-alert stream and calls [show] here.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  /// Load the tz database and point tz.local at a zone whose CURRENT offset
  /// matches the device (no native plugin needed). Falls back to Asia/Almaty —
  /// the app's primary region. Good enough for near-term reminder scheduling.
  Future<void> _initTimezone() async {
    try {
      tzdata.initializeTimeZones();
      final deviceOffsetMs = DateTime.now().timeZoneOffset.inMilliseconds;
      tz.Location? match;
      for (final loc in tz.timeZoneDatabase.locations.values) {
        if (tz.TZDateTime.now(loc).timeZoneOffset.inMilliseconds == deviceOffsetMs) {
          match = loc;
          break;
        }
      }
      tz.setLocalLocation(match ?? tz.getLocation('Asia/Almaty'));
      _tzReady = true;
    } catch (_) {
      _tzReady = false;
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
