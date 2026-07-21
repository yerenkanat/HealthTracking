/// On-device notifications. Kept behind a small interface so the pure-Dart
/// AppController never depends on the Flutter plugin — the runtime (main.dart)
/// subscribes to the controller's new-alert stream and calls [show] here.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/notification_ids.dart';

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
  /// Sequence for immediate alerts, seeded from the clock rather than 0.
  ///
  /// Starting at 0 every launch meant the first alert after a restart reused
  /// the id of the first alert of the previous run — and the OS treats a repeat
  /// id as a replacement. "Aizhan left school", still unread in the tray, was
  /// silently overwritten by the next alert after the app restarted. Losing a
  /// safety alert to a counter reset is the worst version of this bug, so the
  /// seed makes consecutive runs start at different points in the block.
  int _id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  bool _tzReady = false;

  @override
  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS was never initialized, although ios/ is a build target: with no
    // Darwin settings the plugin has no iOS configuration, so every show() and
    // every schedule did nothing there — and requestPermission() below returned
    // true, because it only ever asked the Android resolver. The app believed
    // notifications were working on iOS and no alert ever arrived.
    //
    // requestAlert/Badge/Sound are false here because permission is asked for
    // explicitly in requestPermission(), at a point where the app can explain
    // why — not as a prompt at first launch with no context.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin, macOS: darwin);
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
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    // No resolver at all. This used to return true — claiming a permission
    // nobody had asked for, on the strength of the Android resolver being null.
    // On iOS that meant the app reported alerts were working while none could
    // ever arrive. Unknown is not granted.
    return false;
  }

  @override
  Future<void> show({required String title, required String body}) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _plugin.show(NotifyIds.forAlert(_id++), title, body, details);
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
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
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
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
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
