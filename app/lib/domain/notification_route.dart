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

import 'child_tracker_state.dart' show clockDisagrees;
import 'emergency_confirmation.dart' show emergencyFamily;
import 'health_monitor.dart' show latestTelemetryMaxAge;

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

  /// The vitals HISTORY for one metric — [MetricDetailScreen], pushed on the
  /// dashboard tab. Where a tap on an emergency notification lands once the
  /// emergency is over: the same reading, in its own series, with «9 ч назад»
  /// under it in amber.
  ///
  /// Deliberately absent from [kNotifyScreens]: no payload names it, on either
  /// side. It is decided HERE, from the age of an `EmergencyRescue` push, and
  /// it travels through this channel only because that is the one way to ask
  /// for a screen from outside the widget tree. A payload built for it would
  /// fall back to `Dashboard`, which is the correct answer to a question
  /// nothing asks.
  vitalsHistory,

  /// Screen 53/55 — home. The destination for anything we do not recognise,
  /// which is deliberately never "nowhere" and never a crash.
  dashboard,
}

/// What a tapped MEDICAL emergency notification actually is: something
/// happening NOW, a record of something that already finished, or a claim we
/// cannot date.
enum EmergencyTapAge {
  /// Recent enough that the takeover is still a true sentence in the present
  /// tense. Behaves exactly as this app always has.
  live,

  /// Over. The crossing is real history — it must be readable, and it must not
  /// take the screen over.
  past,

  /// No usable timestamp: the field is absent (a push from a build that did
  /// not carry it), unparseable, or so far in the future that the two clocks
  /// disagree and we do not know the age at all.
  unknown,
}

/// How old a tapped emergency may be and still raise the takeover.
///
/// NOT a new number, and deliberately not a second idea of "too old".
/// [latestTelemetryMaxAge] is the app's existing answer to «how long does a
/// reading still describe how she is NOW», and `health_monitor.dart` states it
/// against this very failure: a critical reading that nothing expired «was
/// still attached on Friday, so an unrelated question about a mild headache was
/// answered by throwing the emergency screen at her again». A notification
/// fished out of the tray in the evening is the same stale reading and the same
/// mistake arriving through a different door, so it gets the same window.
const emergencyTakeoverMaxAge = latestTelemetryMaxAge;

/// Date a tapped emergency against [now].
///
/// FAILS TOWARD [EmergencyTapAge.unknown], and unknown must never raise the
/// takeover. A takeover is a sentence in the present tense — «seek emergency
/// care now» — and we may only say it when we can prove the reading behind it
/// is from the last few hours. Not being able to prove it is not permission to
/// assume it: the cost of missing the takeover is that she reads the same
/// finding one screen later, and the cost of raising it wrongly is that the
/// next real one is the third false alarm she has learned to dismiss.
///
/// A timestamp a little ahead of us is ordinary phone-vs-server skew and stays
/// [live] — `clockDisagrees` owns where that line is drawn, and this does not
/// restate it.
EmergencyTapAge emergencyTapAge(DateTime? at, DateTime now) {
  if (at == null) return EmergencyTapAge.unknown;
  final age = now.difference(at);
  if (clockDisagrees(age)) return EmergencyTapAge.unknown;
  final a = age.isNegative ? Duration.zero : age;
  return a <= emergencyTakeoverMaxAge
      ? EmergencyTapAge.live
      : EmergencyTapAge.past;
}

/// The vitals series a triage code is about — where a PAST emergency is read
/// back, in its own history, with its own time on it.
///
/// Grouped by [emergencyFamily] rather than code-by-code, so the ordinary and
/// the severe threshold for one measurement land on one screen; that function
/// already owns the grouping and this must not grow a second copy of it.
///
/// Null for a finding with no number behind it (`SYMPTOM_RED_FLAG`, an
/// `UNKNOWN` code from a newer server) — the caller then falls back to the
/// dashboard, which is the honest destination when there is no single series
/// to open.
String? emergencyMetricKey(String? code) => switch (emergencyFamily(code)) {
      'bp' => 'systolic',
      'fever' => 'temp',
      'spo2' => 'spo2',
      'hr' => 'hr',
      _ => null,
    };

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
  /// unparseable; the SOS screen falls back to the moment it opened, and says
  /// so.
  ///
  /// For a medical emergency it is not decoration but the deciding field —
  /// [emergencyTapAge] reads it to decide whether the takeover may be raised
  /// at all — so null here means "we do not know", never "just now".
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
