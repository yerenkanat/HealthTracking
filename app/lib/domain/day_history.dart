/// Screens 47/48 — «История дня».
///
/// The day's trail as the app reads it: where she went, how far, and what
/// happened. The server does the thinning and the arithmetic (see
/// packages/backend/src/safety/dayHistory.ts) so that the number printed here
/// is the length of the line the map draws — this file parses and formats, and
/// deliberately does not compute a second opinion about either.
library;

import 'dart:convert';

/// One point on the drawn line.
class RoutePoint {
  final DateTime at;
  final double lat;
  final double lng;

  const RoutePoint({required this.at, required this.lat, required this.lng});

  static RoutePoint? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse('${j['observedAt']}');
    final coords = j['coords'];
    if (at == null || coords is! Map) return null;
    final lat = (coords['lat'] as num?)?.toDouble();
    final lng = (coords['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return RoutePoint(at: at.toLocal(), lat: lat, lng: lng);
  }
}

enum DayEventKind { enter, exit, sos }

/// Something that happened during the day.
class DayEvent {
  final DateTime at;
  final DayEventKind kind;

  /// The zone, for a crossing. Null for an SOS — and null for a crossing whose
  /// zone has since been deleted, which the screen has to be able to show
  /// rather than pretend the crossing did not happen.
  final String? zoneName;
  final double? lat;
  final double? lng;

  /// What this SOS was marked as, if it has been closed. Null on every crossing
  /// and on an SOS nobody has answered for yet — which the detail screen shows
  /// as no chip selected, rather than guessing one.
  final SosOutcome? outcome;

  const DayEvent({
    required this.at,
    required this.kind,
    this.zoneName,
    this.lat,
    this.lng,
    this.outcome,
  });

  /// The same event with a different verdict, for updating the list in place
  /// after a save without refetching the day.
  DayEvent withOutcome(SosOutcome o) => DayEvent(
        at: at, kind: kind, zoneName: zoneName, lat: lat, lng: lng, outcome: o,
      );

  static DayEvent? fromJson(Map<String, dynamic> j) {
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    final kind = switch ('${j['kind']}') {
      'enter' => DayEventKind.enter,
      'exit' => DayEventKind.exit,
      'sos' => DayEventKind.sos,
      // An unknown kind is a server newer than this build. Dropping the event
      // is better than crashing the screen, and better than inventing a kind.
      _ => null,
    };
    if (kind == null) return null;
    final zone = j['zoneName'];
    return DayEvent(
      at: at.toLocal(),
      kind: kind,
      zoneName: zone is String && zone.isNotEmpty ? zone : null,
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      outcome: sosOutcomeFromWire(j['outcome']),
    );
  }
}

/// One day of a child's movements.
class DayHistory {
  /// The calendar day this describes, as YYYY-MM-DD.
  final String day;
  final List<RoutePoint> points;
  final int distanceM;

  /// Fixes recorded before the trail was simplified for drawing.
  final int rawCount;
  final List<DayEvent> events;

  /// How long ROUTE POINTS are kept on the server — read from the constant the
  /// sweep uses rather than typed here, so the screen cannot promise a window
  /// the sweep does not keep.
  ///
  /// It covers `location_history` and nothing else. The crossings and the SOS
  /// rows in [events] come from other tables that no sweep touches, and the
  /// screen says so separately; do not let this number spread over them.
  final int retentionDays;

  const DayHistory({
    required this.day,
    required this.points,
    required this.distanceM,
    required this.rawCount,
    required this.events,
    required this.retentionDays,
  });

  /// Nothing was recorded. Distinct from a failed load, which the screen shows
  /// differently — a tracker that was switched off is not an error.
  bool get isEmpty => points.isEmpty && events.isEmpty;

  /// The «4 точки» of the badge — how many are drawn.
  int get pointCount => points.length;

  /// The line on screen is fewer points than the tracker reported. True when
  /// that is worth saying, so the badge's small number cannot be mistaken for
  /// a tracker that barely reported.
  bool get wasSimplified => rawCount > points.length;

  static DayHistory fromJson(Map<String, dynamic> j) => DayHistory(
        day: '${j['day']}',
        points: [
          for (final p in (j['points'] as List? ?? const []))
            if (p is Map<String, dynamic>)
              if (RoutePoint.fromJson(p) case final r?) r,
        ],
        distanceM: (j['distanceM'] as num?)?.round() ?? 0,
        rawCount: (j['rawCount'] as num?)?.toInt() ?? 0,
        events: [
          for (final e in (j['events'] as List? ?? const []))
            if (e is Map<String, dynamic>)
              if (DayEvent.fromJson(e) case final d?) d,
        ],
        retentionDays: (j['retentionDays'] as num?)?.toInt() ?? 90,
      );

  static DayHistory parse(String body) =>
      fromJson(jsonDecode(body) as Map<String, dynamic>);
}

/// «3,2 км» / «450 м».
///
/// A comma, because that is the decimal separator in both Russian and Kazakh,
/// and one decimal place: «3,17 км» claims a precision GPS does not have over a
/// day's walk.
String formatDistance(int metres) {
  if (metres < 1000) return '$metres м';
  final km = metres / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} км';
}

/// What a parent can mark an SOS as afterwards — the four chips of screen 48.
///
/// Mirrors SOS_OUTCOMES on the server. Four, and no free-text box: a parent
/// closing an alarm at midnight will not write a paragraph, and an outcome
/// field that is usually empty tells nobody anything.
enum SosOutcome { falsePress, scared, neededHelp, unknown }

/// Parse the server's key. Null for absent, and null for a key this build does
/// not know — a newer server is not a reason to crash the day, and inventing a
/// verdict is worse than showing none.
SosOutcome? sosOutcomeFromWire(Object? v) => switch (v) {
      'false_press' => SosOutcome.falsePress,
      'scared' => SosOutcome.scared,
      'needed_help' => SosOutcome.neededHelp,
      'unknown' => SosOutcome.unknown,
      _ => null,
    };

extension SosOutcomeWire on SosOutcome {
  String get wire => switch (this) {
        SosOutcome.falsePress => 'false_press',
        SosOutcome.scared => 'scared',
        SosOutcome.neededHelp => 'needed_help',
        SosOutcome.unknown => 'unknown',
      };

  /// The l10n key for the chip's label.
  String get l10nKey => switch (this) {
        SosOutcome.falsePress => 'sos_out_false',
        SosOutcome.scared => 'sos_out_scared',
        SosOutcome.neededHelp => 'sos_out_help',
        SosOutcome.unknown => 'sos_out_unknown',
      };
}
