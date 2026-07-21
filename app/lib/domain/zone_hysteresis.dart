/// Deciding which zone a child is in, without flapping.
///
/// WHY THIS EXISTS
///
/// core/geofence.dart already had all of this — GeofenceTracker, with a buffer
/// band, a confirmation count and an accuracy gate — and nothing in the app
/// used it. The production path went straight to currentZone(), a bare
/// "does this point fall inside", which meant a child standing still near a
/// boundary flipped zone on GPS noise alone. Each flip is a "left School"
/// followed by an "entered School", written to the feed and pushed to a
/// parent's phone. A location poll every 45 seconds makes that dozens of false
/// alarms in an afternoon, on the half of the product whose whole promise is
/// that an alert means something.
///
/// GeofenceTracker is not reused directly because it answers a different
/// question — per-fence transitions — while the app is built around a single
/// current zone NAME that is persisted and survives restart. This resolves the
/// same ambiguity in those terms, and keeps its state explicit so it can be
/// held by the controller and reasoned about in tests.
///
/// Pure Dart. Verified by tool/verify_zone_hysteresis.dart.
library;

import '../core/geofence.dart';

/// What the resolver remembers between fixes.
///
/// Deliberately a value: the controller holds one, and a test can construct any
/// intermediate state directly rather than replaying fixes to reach it.
class ZoneHysteresisState {
  /// The zone we are moving towards but have not confirmed. Null means no
  /// change is pending; [pendingZone] being null while [pendingCount] > 0 is a
  /// pending move to "no zone at all", which is why the two are separate.
  final String? pendingZone;
  final int pendingCount;
  final bool hasPending;

  const ZoneHysteresisState({
    this.pendingZone,
    this.pendingCount = 0,
    this.hasPending = false,
  });

  static const idle = ZoneHysteresisState();
}

class ZoneDecision {
  /// The zone to act on — unchanged from the previous one unless a move was
  /// confirmed this fix.
  final String? zone;
  final ZoneHysteresisState state;

  /// Why the fix did not move us, when it did not. For diagnostics only.
  final String? held;

  const ZoneDecision({required this.zone, required this.state, this.held});
}

/// Decide the current zone from a new fix.
///
/// The rules, in order:
///
/// 1. A fix less accurate than [cfg].maxAccuracyM is ignored entirely. A fix
///    with a 500 m error radius cannot tell you which side of a 100 m fence
///    someone is on, and acting on it is how a phone reports a child leaving
///    school from the classroom.
/// 2. To COUNT as inside a fence, the point must be at least a buffer inside
///    it; to count as outside, at least a buffer outside. In between is
///    ambiguous and holds the current answer. This is what stops a boundary
///    from flapping.
/// 3. A change must then repeat [cfg].confirmations times before it takes
///    effect, so one bad fix in a good sequence changes nothing.
ZoneDecision resolveZone({
  required String? prevZone,
  required Coordinates location,
  required List<Geofence> fences,
  required ZoneHysteresisState state,
  HysteresisConfig cfg = const HysteresisConfig(),
  double? accuracyM,
}) {
  final acc = accuracyM ?? location.accuracyM;
  if (acc != null && acc > cfg.maxAccuracyM) {
    // Hold everything, including any pending move: a rejected fix is not
    // evidence for or against it.
    return ZoneDecision(zone: prevZone, state: state, held: 'accuracy');
  }

  // Which fence, if any, we are definitely inside; and whether the zone we
  // believe we are in is still plausible.
  String? definitelyInside;
  var prevStillPlausible = false;
  for (final fence in fences) {
    final signed = signedDistanceToBoundaryM(location, fence);
    if (signed.isNaN) continue; // a malformed fence must not decide anything
    final buffer = _bufferFor(fence, cfg);
    if (signed <= -buffer && definitelyInside == null) {
      definitelyInside = fence.name;
    }
    // Inside, or within the ambiguous band around this fence's edge.
    if (fence.name == prevZone && signed < buffer) prevStillPlausible = true;
  }

  // Standing on the line of the zone we are already in: stay. This is the
  // single most common case near a boundary and the one that used to flap.
  if (prevStillPlausible && definitelyInside == null) {
    return ZoneDecision(
        zone: prevZone, state: ZoneHysteresisState.idle, held: 'ambiguous');
  }

  final candidate = definitelyInside;
  if (candidate == prevZone) {
    return ZoneDecision(zone: prevZone, state: ZoneHysteresisState.idle);
  }

  // A change: require it to repeat before believing it.
  final continuing = state.hasPending && state.pendingZone == candidate;
  final count = continuing ? state.pendingCount + 1 : 1;
  if (count >= cfg.confirmations) {
    return ZoneDecision(zone: candidate, state: ZoneHysteresisState.idle);
  }
  return ZoneDecision(
    zone: prevZone,
    state: ZoneHysteresisState(pendingZone: candidate, pendingCount: count, hasPending: true),
    held: 'unconfirmed',
  );
}

/// The buffer to apply to [fence].
///
/// Mirrors GeofenceTracker._bufferFor, and extends its reasoning to polygons.
/// "Inside" requires being a buffer deep, so a fence that is not a buffer deep
/// anywhere can never be entered — the enter alert is silently impossible. For
/// a circle the deepest point is the centre, at exactly the radius. For a
/// polygon there is no single number, so the distance from its centroid to the
/// nearest edge is used as a stand-in: it is not the true inradius, but it is
/// never larger, so the buffer it produces is never too big to enter.
double _bufferFor(Geofence fence, HysteresisConfig cfg) {
  if (fence.shape == GeofenceShape.circle) {
    final r = fence.radiusM ?? 0;
    return cfg.bufferM < r ? cfg.bufferM : r / 2;
  }
  final v = fence.vertices;
  if (v == null || v.length < 3) return cfg.bufferM;
  var lat = 0.0, lng = 0.0;
  for (final p in v) {
    lat += p.lat;
    lng += p.lng;
  }
  final centroid = Coordinates(lat / v.length, lng / v.length);
  final depth = -signedDistanceToBoundaryM(centroid, fence);
  if (depth.isNaN || depth <= 0) return cfg.bufferM; // concave enough that the
  // centroid falls outside; fall back rather than guess.
  return cfg.bufferM < depth ? cfg.bufferM : depth / 2;
}
