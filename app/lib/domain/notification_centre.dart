/// Screen 39 — «Центр уведомлений».
///
/// «Прочитать всё» → секция «Сегодня» → секция «Раньше» → карточка «экстренные
/// отключить нельзя» + «Настроить остальные →».
///
/// The alerts screen listed everything that had ever happened, in one flat
/// column, with no idea what had been seen. So the badge never went down, and
/// a mother scrolling for the one alert that mattered had to remember where
/// she got to last time.
///
/// ON «ЭКСТРЕННЫЕ ОТКЛЮЧИТЬ НЕЛЬЗЯ». That is not a sentence on a card, it is a
/// property of [NotificationChannel]: the emergency channel has no off switch
/// to render, so the settings screen cannot grow one by accident. A promise
/// about a child's safety that lives only in copy is a promise one refactor
/// away from being false.
library;

import 'geofence_alerts.dart';

/// What the app is allowed to interrupt her for.
enum NotificationChannel {
  /// SOS and a child leaving a safe zone. Cannot be turned off.
  emergency,

  /// Zone crossings that are not emergencies — arriving at school.
  zones,

  /// The tracker's battery.
  battery,

  /// Reminders: appointments, medication, water.
  reminders,

  /// The course, the shop, what is new this week.
  updates,
}

extension NotificationChannelRules on NotificationChannel {
  /// May she silence it?
  ///
  /// False for exactly one channel, and it is false HERE rather than in the
  /// settings screen so there is nowhere else for the decision to be made.
  bool get canBeMuted => this != NotificationChannel.emergency;

  String get l10nKey => switch (this) {
        NotificationChannel.emergency => 'ntf_ch_emergency',
        NotificationChannel.zones => 'ntf_ch_zones',
        NotificationChannel.battery => 'ntf_ch_battery',
        NotificationChannel.reminders => 'ntf_ch_reminders',
        NotificationChannel.updates => 'ntf_ch_updates',
      };
}

/// Which channel an alert belongs to.
///
/// An SOS is an emergency however it was recorded; a zone crossing is not.
/// Getting this wrong in the safe direction costs one extra notification;
/// wrong the other way silences an SOS, so anything unrecognised is treated as
/// an emergency rather than as chatter.
NotificationChannel channelOf(AlertKind kind) => switch (kind) {
      AlertKind.sos => NotificationChannel.emergency,
      AlertKind.entered || AlertKind.left => NotificationChannel.zones,
      AlertKind.lowBattery => NotificationChannel.battery,
      AlertKind.checkIn => NotificationChannel.zones,
    };

/// One row of the centre.
class NotificationItem {
  final SafetyAlert alert;
  final bool unread;

  const NotificationItem({required this.alert, required this.unread});

  NotificationChannel get channel => channelOf(alert.kind);
  bool get isEmergency => channel == NotificationChannel.emergency;
}

/// «Сегодня» and «Раньше».
class NotificationSections {
  final List<NotificationItem> today;
  final List<NotificationItem> earlier;

  const NotificationSections({this.today = const [], this.earlier = const []});

  int get unreadCount =>
      today.where((i) => i.unread).length + earlier.where((i) => i.unread).length;

  bool get isEmpty => today.isEmpty && earlier.isEmpty;
}

/// Split the feed into the two sections, newest first, marking what is unread.
///
/// [readUpTo] is a WATERMARK, not a per-item flag: «Прочитать всё» is the only
/// way to mark anything read, so one instant expresses it exactly. Per-item
/// flags would need syncing and could disagree with the badge — a badge that
/// says 3 over a list with nothing new is how people stop looking at badges.
NotificationSections groupNotifications(
  List<SafetyAlert> alerts,
  DateTime now, {
  DateTime? readUpTo,
}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final sorted = [...alerts]..sort((a, b) => b.at.compareTo(a.at));

  final today = <NotificationItem>[];
  final earlier = <NotificationItem>[];
  for (final a in sorted) {
    // `isAfter`, so an alert stamped at exactly the watermark counts as read —
    // otherwise «Прочитать всё» leaves the newest one unread and the badge
    // never reaches zero.
    final item = NotificationItem(
      alert: a,
      unread: readUpTo == null || a.at.isAfter(readUpTo),
    );
    if (a.at.isBefore(startOfToday)) {
      earlier.add(item);
    } else {
      today.add(item);
    }
  }
  return NotificationSections(today: today, earlier: earlier);
}

/// The instant «Прочитать всё» should record.
///
/// The newest alert's time, not `now`: recording `now` would also mark read an
/// alert that arrives in the same second and is not on screen yet. Null when
/// there is nothing to read, so the button does nothing rather than moving the
/// watermark forward over an empty list.
DateTime? readAllWatermark(List<SafetyAlert> alerts) {
  if (alerts.isEmpty) return null;
  var newest = alerts.first.at;
  for (final a in alerts) {
    if (a.at.isAfter(newest)) newest = a.at;
  }
  return newest;
}
