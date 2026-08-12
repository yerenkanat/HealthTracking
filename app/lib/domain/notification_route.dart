/// Screen 38's other half — where a TAPPED notification lands.
///
/// «Пуши на локскрине» drew three notifications and stopped there. Tapping any
/// of them did nothing at all: `flutter_local_notifications` was initialized
/// without `onDidReceiveNotificationResponse`, so the plugin had nowhere to
/// deliver the tap, and the FCM `data.screen` values the backend has been
/// setting since frame 43 (`SupportThread`, `NotificationCentre`,
/// `EmergencyRescue`) were read by nothing on this side. A notification that
/// opens the app on the dashboard she was already looking at is the same defect
/// as no notification: the thing it was about is still somewhere else.
///
/// PURE Dart — no Flutter, no plugin — so the mapping from a payload to a
/// destination is unit-testable, which matters because the payload is written
/// on the server (TypeScript) and read here.
library;

import 'dart:convert';

/// Where a tap has to go.
enum NotifyDestination {
  /// Screen 21 — the red SOS takeover.
  sos,

  /// Screen 43 — «Поддержка · оператор».
  supportThread,

  /// Screen 39 — «Центр уведомлений», where рассылки and safety events live.
  notificationCentre,

  /// Screen 12 — the child's live map. Not a push destination the server sends
  /// today; it is where «Открыть карту» on screen 21 hands over to, and it
  /// travels through the same channel so there is one way to ask for a screen
  /// from outside the widget tree.
  childMap,

  /// The mother's own medical emergency (the band / server triage backstop) —
  /// [EmergencyRescueScreen], raised app-wide rather than pushed.
  emergency,

  /// Screen 53/55 — home. The destination for anything we do not recognise,
  /// which is deliberately never "nowhere" and never a crash.
  dashboard,
}

/// The `screen` value each destination travels as. These strings are a CONTRACT
/// with `packages/backend/src/notifications/push.ts` — they are the values that
/// module already puts in the FCM `data` block, so they are referenced on both
/// sides rather than retyped.
const Map<String, NotifyDestination> kNotifyScreens = {
  'SosAlert': NotifyDestination.sos,
  'SupportThread': NotifyDestination.supportThread,
  'NotificationCentre': NotifyDestination.notificationCentre,
  'ChildMap': NotifyDestination.childMap,
  'EmergencyRescue': NotifyDestination.emergency,
  'Dashboard': NotifyDestination.dashboard,
};

/// A tap, resolved: where to go and what the notification knew.
class NotifyTap {
  final NotifyDestination destination;

  /// The raw data block. Read through the accessors below rather than directly,
  /// so a missing or malformed field is absent instead of throwing on a screen
  /// somebody is opening in an emergency.
  final Map<String, String> data;

  const NotifyTap(this.destination, [this.data = const {}]);

  /// Whose SOS. Empty when the notification did not say — the screen then uses
  /// wording that needs no name rather than inventing one.
  String get childName => (data['childName'] ?? '').trim();

  /// When it happened, as the SENDER recorded it. Null when absent or
  /// unparseable; the screen falls back to the moment it opened, and says so.
  DateTime? get at => DateTime.tryParse(data['at'] ?? '')?.toLocal();

  /// The zone the child was in, if any. An SOS happens wherever she is, so this
  /// is very often empty.
  String get zoneName => (data['zoneName'] ?? '').trim();

  /// Which support conversation (screen 43).
  String? get ticketId => _nonEmpty(data['ticketId']);

  /// The triage code behind a medical emergency, so the app localizes the
  /// message exactly as it does an on-device one.
  String? get code => _nonEmpty(data['code']);

  /// Where the child was, when the notification was composed. Null unless BOTH
  /// halves parsed — half a coordinate is a point in the sea.
  ({double lat, double lng})? get coords {
    final lat = double.tryParse(data['lat'] ?? '');
    final lng = double.tryParse(data['lng'] ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return (lat: lat, lng: lng);
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// Read a tapped notification's payload.
///
/// Tolerant on purpose. This runs on a payload written by another codebase, at
/// the moment a frightened person taps a notification, and there is no second
/// chance: anything it cannot understand — null, empty, not JSON, JSON that is
/// not an object, an unknown screen name, a screen name from a newer server —
/// resolves to the dashboard. Never an exception, never a blank route.
NotifyTap parseNotificationPayload(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return const NotifyTap(NotifyDestination.dashboard);

  Map<String, String> data = const {};
  String screen = s;
  if (s.startsWith('{')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        data = {
          for (final e in decoded.entries)
            if (e.value != null) '${e.key}': '${e.value}',
        };
        screen = data['screen'] ?? '';
      }
    } catch (_) {
      // Not JSON after all. Fall through to the bare-name form below, which
      // will not match either — so this lands on the dashboard.
    }
  }
  return NotifyTap(
    kNotifyScreens[screen] ?? NotifyDestination.dashboard,
    data,
  );
}

/// Build the payload the app attaches to its OWN notifications.
///
/// The same shape the server sends, so one parser serves both and the two can
/// never drift into disagreeing about where a tap goes.
String notificationPayload(NotifyDestination destination,
    [Map<String, String> data = const {}]) {
  final screen = kNotifyScreens.entries
      .firstWhere((e) => e.value == destination,
          orElse: () => const MapEntry('Dashboard', NotifyDestination.dashboard))
      .key;
  return jsonEncode({
    'screen': screen,
    for (final e in data.entries)
      if (e.value.trim().isNotEmpty) e.key: e.value,
  });
}

/// The payload for an SOS the phone itself raised (screen 21).
String sosNotificationPayload({
  required String childName,
  required DateTime at,
  String zoneName = '',
}) =>
    notificationPayload(NotifyDestination.sos, {
      'childName': childName,
      'at': at.toUtc().toIso8601String(),
      'zoneName': zoneName,
    });
