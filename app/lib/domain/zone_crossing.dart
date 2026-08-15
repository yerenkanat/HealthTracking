/// One crossing of a safe-zone boundary, as the SERVER recorded it.
///
/// `GET /children/:id/events` has existed, been access-controlled and been
/// tested since geofencing was built, and nothing in the app ever called it.
/// The consequence is specific: the crossings the SERVER derives from a
/// tracker's own fixes (ingestHandler) land in `geofence_events`, and the only
/// route the app read — `GET /alerts` — is keyed to the OWNER's user id and is
/// pulled exactly once, at sign-in. So a father or a grandmother invited into
/// the family opened «Оповещения» and read «Пока нет оповещений» about a child
/// who had crossed the school boundary four times that morning. An empty read
/// was rendering as an answer.
///
/// PURE Dart — no Flutter — so the parsing and the day grouping are testable
/// without a widget.
///
/// What this record is NOT, and it matters enough to say here as well as on the
/// screen: an SOS is not a crossing. `geofence_events` holds enter/exit and
/// nothing else — the five-kind set (`entered`, `left`, `sos`, `checkIn`,
/// `lowBattery`) belongs to `safety_alerts`, a different table behind a
/// different route. A list built from this file therefore may never be
/// presented as "everything that happened".
library;

/// Which way the boundary was crossed. The wire says `enter`/`exit`; the app
/// has said `entered`/`left` since the alert feed was written, and one spelling
/// per concept is what stops a caller comparing against the other one.
enum ZoneTransition { entered, left }

class ZoneCrossing {
  /// The zone's name as the server joined it. Empty when the server sent none —
  /// which the screen renders as «Пришла в зону» rather than «зону «»».
  final String zoneName;

  final ZoneTransition transition;

  /// When it happened, in local time (the wire carries UTC).
  final DateTime at;

  /// How the position that triggered it was obtained: `gps`, `wifi`, `lbs` or
  /// `ble`. Null when the server sent something this build does not know, which
  /// hides the label rather than printing a word nobody has translated.
  ///
  /// Kept and shown because the instrument is part of the claim: a crossing
  /// derived from a cell-tower fix and one derived from GPS are not the same
  /// evidence, and the screen names which it was instead of implying either.
  final String? source;

  const ZoneCrossing({
    required this.transition,
    required this.at,
    this.zoneName = '',
    this.source,
  });

  /// The sources the backend can send (`PositioningSource` in @fcs/shared).
  static const knownSources = {'gps', 'wifi', 'lbs', 'ble'};

  /// Tolerant: a row with no usable timestamp or an unknown transition is
  /// DROPPED rather than thrown, because one malformed row must not empty a
  /// history a parent is reading — and must not be turned into a crossing in
  /// the other direction either, which is what a default would do.
  static ZoneCrossing? fromJson(Map<String, dynamic> j) {
    final rawAt = j['at'];
    if (rawAt is! String) return null;
    final at = DateTime.tryParse(rawAt);
    if (at == null) return null;

    final t = switch (j['transition']) {
      'enter' => ZoneTransition.entered,
      'exit' => ZoneTransition.left,
      _ => null,
    };
    if (t == null) return null;

    final src = j['source'];
    return ZoneCrossing(
      transition: t,
      at: at.toLocal(),
      zoneName: (j['geofenceName'] as String?)?.trim() ?? '',
      source: src is String && knownSources.contains(src) ? src : null,
    );
  }

  /// Newest first, which is the order the route already promises and the order
  /// the screen needs. Sorted here anyway: the memory repository and Postgres
  /// reach it by different routes, and a screen that depends on one of them
  /// being right is a screen that breaks when the other is used.
  static List<ZoneCrossing> listFromJson(List<Map<String, dynamic>> rows) {
    final out = <ZoneCrossing>[];
    for (final r in rows) {
      final c = fromJson(r);
      if (c != null) out.add(c);
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }
}

/// One calendar day of crossings.
typedef CrossingDay = ({DateTime day, List<ZoneCrossing> crossings});

/// Group [crossings] by local calendar day, newest day first and newest
/// crossing first inside each day.
///
/// A flat list spanning a week reads as one run-on stream in which yesterday
/// and today are told apart only by doing arithmetic on timestamps. The
/// grouping is here rather than in the widget so it can be tested against a
/// month boundary without pumping a frame.
List<CrossingDay> groupCrossingsByDay(List<ZoneCrossing> crossings) {
  final sorted = [...crossings]..sort((a, b) => b.at.compareTo(a.at));
  final out = <CrossingDay>[];
  for (final c in sorted) {
    final day = DateTime(c.at.year, c.at.month, c.at.day);
    if (out.isNotEmpty && out.last.day == day) {
      out.last.crossings.add(c);
    } else {
      out.add((day: day, crossings: <ZoneCrossing>[c]));
    }
  }
  return out;
}
