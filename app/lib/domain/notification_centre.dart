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

import 'announcement.dart';
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

/// One row of the centre — a safety alert OR a рассылка.
///
/// Exactly one of [alert] and [announcement] is set. They share a list because
/// they share a screen and a badge: a woman does not keep two mental inboxes,
/// and «Прочитать всё» that cleared only half of one would leave a badge she
/// cannot get rid of — which is how badges stop being read at all, including on
/// the day the thing behind it is her child's SOS.
///
/// They do NOT share urgency. An announcement is [NotificationChannel.updates],
/// so it can never be drawn with the emergency treatment, and the ordering
/// below is by time alone rather than by kind — an SOS from this morning stays
/// above a marketing message from this afternoon only if it happened later,
/// because pretending otherwise would mean re-ordering her day.
class NotificationItem {
  /// Set for a safety alert; null for a рассылка.
  final SafetyAlert? alert;

  /// Set for a рассылка; null for a safety alert.
  final Announcement? announcement;

  final bool unread;

  const NotificationItem.forAlert(SafetyAlert this.alert, {required this.unread})
      : announcement = null;

  const NotificationItem.forAnnouncement(Announcement this.announcement, {required this.unread})
      : alert = null;

  /// When it happened. The single ordering key — see the class comment.
  DateTime get at => alert?.at ?? announcement!.at;

  /// A рассылка is «что нового», never an emergency. Read from the model so a
  /// message from the back office cannot inherit the emergency treatment by
  /// landing in the wrong branch of a widget.
  NotificationChannel get channel =>
      alert != null ? channelOf(alert!.kind) : NotificationChannel.updates;

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
///
/// [announcements] are the рассылки from the back office. ONE watermark covers
/// both, for the same reason: two would let «Прочитать всё» clear the alerts
/// and leave the badge at 1.
NotificationSections groupNotifications(
  List<SafetyAlert> alerts,
  DateTime now, {
  DateTime? readUpTo,
  List<Announcement> announcements = const [],
}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  // `isAfter`, so an item stamped at exactly the watermark counts as read —
  // otherwise «Прочитать всё» leaves the newest one unread and the badge never
  // reaches zero.
  bool unread(DateTime at) => readUpTo == null || at.isAfter(readUpTo);

  final sorted = <NotificationItem>[
    for (final a in alerts) NotificationItem.forAlert(a, unread: unread(a.at)),
    for (final m in announcements)
      NotificationItem.forAnnouncement(m, unread: unread(m.at)),
  ]..sort((a, b) => b.at.compareTo(a.at));

  final today = <NotificationItem>[];
  final earlier = <NotificationItem>[];
  for (final item in sorted) {
    if (item.at.isBefore(startOfToday)) {
      earlier.add(item);
    } else {
      today.add(item);
    }
  }
  return NotificationSections(today: today, earlier: earlier);
}

/// The instant «Прочитать всё» should record.
///
/// The newest thing on the screen, not `now`: recording `now` would also mark
/// read an item that arrives in the same second and is not on screen yet. Null
/// when there is nothing to read, so the button does nothing rather than moving
/// the watermark forward over an empty list.
///
/// [announcements] counts here too — a watermark taken from the alerts alone
/// would leave a рассылка sent five minutes ago permanently unread, and the
/// badge stuck at 1 over a list she has just cleared.
DateTime? readAllWatermark(
  List<SafetyAlert> alerts, [
  List<Announcement> announcements = const [],
]) {
  DateTime? newest;
  for (final at in [
    for (final a in alerts) a.at,
    for (final m in announcements) m.at,
  ]) {
    if (newest == null || at.isAfter(newest)) newest = at;
  }
  return newest;
}
