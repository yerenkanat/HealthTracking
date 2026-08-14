/// Per-category notification preferences + quiet hours.
///
/// PURE Dart → verified by tool/verify_notification_prefs.dart.
///
/// The audit found only a single global notification switch plus the four
/// reminder toggles; the child-safety categories (zone events, check-ins,
/// low-battery) had no per-category control, and there were no quiet hours.
///
/// THE ONE RULE THAT MUST NOT BREAK: an **SOS / emergency** notification is
/// ALWAYS delivered — no toggle turns it off, and quiet hours never hold it. The
/// whole point of the product is that the one message you cannot afford to miss
/// gets through. Everything else is a preference.
library;

import 'geofence_alerts.dart';

/// A notification category the user can control. SOS is included so callers pass
/// it through the same gate, but [NotificationPrefs.shouldDeliver] always lets it
/// through.
///
/// [updates] is the SERVER's voice — рассылки (frame 06) and support answers
/// (frame 43). It is a fourth category rather than a reuse of [checkIn], which
/// is the shortcut this enum invites: both already exist and neither is about
/// the child's tracker. Hanging marketing off [checkIn] would mean a mother who
/// silenced advertisements also silenced «ребёнок на месте», with nothing on
/// the screen to tell her which switch did it.
enum NotifyCategory { zoneEvents, checkIn, lowBattery, updates, sos }

/// Which category an alert is gated by — the bridge between what the app RAISES
/// ([AlertKind]) and what the mother CONTROLS ([NotifyCategory]).
///
/// It exists so no caller has to re-derive the mapping and get SOS wrong. The
/// bias is the same as `channelOf`'s: an unclassifiable alert would be an
/// emergency, never chatter.
NotifyCategory categoryOfAlert(AlertKind kind) => switch (kind) {
      AlertKind.sos => NotifyCategory.sos,
      AlertKind.entered || AlertKind.left => NotifyCategory.zoneEvents,
      AlertKind.checkIn => NotifyCategory.checkIn,
      AlertKind.lowBattery => NotifyCategory.lowBattery,
    };

class NotificationPrefs {
  final bool zoneEvents; // child entered/left a zone
  final bool checkIn; // child checked in ("arrived / all good")
  final bool lowBattery; // tracker battery low
  /// Рассылки and support answers — what the product says to her.
  ///
  /// Gated on the SERVER too (packages/backend/src/notifications/gate.ts), which
  /// is the whole reason it exists: these two notifications are not raised by
  /// this phone, so a switch honoured only here would control nothing at all.
  final bool updates;
  // SOS has no field — it is never suppressible.

  /// Quiet-hours window in minutes since midnight (inclusive start, exclusive
  /// end). Null/null = off. Supports an overnight window (e.g. 22:00 → 07:00).
  final int? quietStart;
  final int? quietEnd;

  const NotificationPrefs({
    this.zoneEvents = true,
    this.checkIn = true,
    this.lowBattery = true,
    this.updates = true,
    this.quietStart,
    this.quietEnd,
  });

  bool get hasQuietHours => quietStart != null && quietEnd != null;

  bool allows(NotifyCategory c) => switch (c) {
        NotifyCategory.sos => true,
        NotifyCategory.zoneEvents => zoneEvents,
        NotifyCategory.checkIn => checkIn,
        NotifyCategory.lowBattery => lowBattery,
        NotifyCategory.updates => updates,
      };

  /// Whether [minute] (0–1439, minutes since midnight) falls in quiet hours.
  bool inQuietHours(int minute) {
    if (!hasQuietHours) return false;
    final s = quietStart!, e = quietEnd!;
    if (s == e) return false; // zero-length window is "off"
    return s < e ? (minute >= s && minute < e) : (minute >= s || minute < e);
  }

  /// The gate every notification passes through. SOS always delivers; otherwise
  /// the category must be enabled AND it must not be quiet hours.
  bool shouldDeliver(NotifyCategory c, int minuteOfDay) {
    if (c == NotifyCategory.sos) return true;
    if (!allows(c)) return false;
    if (inQuietHours(minuteOfDay)) return false;
    return true;
  }

  NotificationPrefs copyWith({
    bool? zoneEvents,
    bool? checkIn,
    bool? lowBattery,
    bool? updates,
    int? quietStart,
    int? quietEnd,
    bool clearQuietHours = false,
  }) =>
      NotificationPrefs(
        zoneEvents: zoneEvents ?? this.zoneEvents,
        checkIn: checkIn ?? this.checkIn,
        lowBattery: lowBattery ?? this.lowBattery,
        updates: updates ?? this.updates,
        quietStart: clearQuietHours ? null : (quietStart ?? this.quietStart),
        quietEnd: clearQuietHours ? null : (quietEnd ?? this.quietEnd),
      );

  Map<String, dynamic> toJson() => {
        'zoneEvents': zoneEvents,
        'checkIn': checkIn,
        'lowBattery': lowBattery,
        'updates': updates,
        if (quietStart != null) 'quietStart': quietStart,
        if (quietEnd != null) 'quietEnd': quietEnd,
      };

  /// What PUT /notifications/settings takes.
  ///
  /// The quiet window travels as an explicit null rather than being omitted:
  /// this is a full replace, and a missing key on the wire would leave the
  /// server holding a window she has just cleared.
  Map<String, dynamic> toApiJson() => {
        'zoneEvents': zoneEvents,
        'checkIn': checkIn,
        'lowBattery': lowBattery,
        'updates': updates,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      };

  /// Tolerant: unknown/missing fields fall back to the safe default (on), and a
  /// half-specified quiet window is treated as off rather than crashing.
  ///
  /// `updates` MISSING MEANS ON. Every install that predates the switch has a
  /// stored blob without the key; reading that as "off" would silently stop the
  /// support answers she is waiting for, on the day this shipped.
  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    final s = (j['quietStart'] as num?)?.toInt();
    final e = (j['quietEnd'] as num?)?.toInt();
    return NotificationPrefs(
      zoneEvents: (j['zoneEvents'] as bool?) ?? true,
      checkIn: (j['checkIn'] as bool?) ?? true,
      lowBattery: (j['lowBattery'] as bool?) ?? true,
      updates: (j['updates'] as bool?) ?? true,
      quietStart: (s != null && e != null) ? s : null,
      quietEnd: (s != null && e != null) ? e : null,
    );
  }

  /// Value equality — so a sync hook can skip a push that changes nothing, and
  /// a restore can tell "the server agrees" from "the server has other ideas".
  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      other.zoneEvents == zoneEvents &&
      other.checkIn == checkIn &&
      other.lowBattery == lowBattery &&
      other.updates == updates &&
      other.quietStart == quietStart &&
      other.quietEnd == quietEnd;

  @override
  int get hashCode =>
      Object.hash(zoneEvents, checkIn, lowBattery, updates, quietStart, quietEnd);
}
