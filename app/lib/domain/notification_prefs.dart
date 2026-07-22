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

/// A notification category the user can control. SOS is included so callers pass
/// it through the same gate, but [NotificationPrefs.shouldDeliver] always lets it
/// through.
enum NotifyCategory { zoneEvents, checkIn, lowBattery, sos }

class NotificationPrefs {
  final bool zoneEvents; // child entered/left a zone
  final bool checkIn; // child checked in ("arrived / all good")
  final bool lowBattery; // tracker battery low
  // SOS has no field — it is never suppressible.

  /// Quiet-hours window in minutes since midnight (inclusive start, exclusive
  /// end). Null/null = off. Supports an overnight window (e.g. 22:00 → 07:00).
  final int? quietStart;
  final int? quietEnd;

  const NotificationPrefs({
    this.zoneEvents = true,
    this.checkIn = true,
    this.lowBattery = true,
    this.quietStart,
    this.quietEnd,
  });

  bool get hasQuietHours => quietStart != null && quietEnd != null;

  bool allows(NotifyCategory c) => switch (c) {
        NotifyCategory.sos => true,
        NotifyCategory.zoneEvents => zoneEvents,
        NotifyCategory.checkIn => checkIn,
        NotifyCategory.lowBattery => lowBattery,
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
    int? quietStart,
    int? quietEnd,
    bool clearQuietHours = false,
  }) =>
      NotificationPrefs(
        zoneEvents: zoneEvents ?? this.zoneEvents,
        checkIn: checkIn ?? this.checkIn,
        lowBattery: lowBattery ?? this.lowBattery,
        quietStart: clearQuietHours ? null : (quietStart ?? this.quietStart),
        quietEnd: clearQuietHours ? null : (quietEnd ?? this.quietEnd),
      );

  Map<String, dynamic> toJson() => {
        'zoneEvents': zoneEvents,
        'checkIn': checkIn,
        'lowBattery': lowBattery,
        if (quietStart != null) 'quietStart': quietStart,
        if (quietEnd != null) 'quietEnd': quietEnd,
      };

  /// Tolerant: unknown/missing fields fall back to the safe default (on), and a
  /// half-specified quiet window is treated as off rather than crashing.
  factory NotificationPrefs.fromJson(Map<String, dynamic> j) {
    final s = (j['quietStart'] as num?)?.toInt();
    final e = (j['quietEnd'] as num?)?.toInt();
    return NotificationPrefs(
      zoneEvents: (j['zoneEvents'] as bool?) ?? true,
      checkIn: (j['checkIn'] as bool?) ?? true,
      lowBattery: (j['lowBattery'] as bool?) ?? true,
      quietStart: (s != null && e != null) ? s : null,
      quietEnd: (s != null && e != null) ? e : null,
    );
  }
}
