/// Geofence geometry + jitter-free crossing detection — Dart / on-device twin of
/// backend `geofence.ts`. Pure Dart (dart:math only) → unit-testable.
/// Owned by the Geofencing & Maps specialist.
library;

import 'dart:math' as math;

const double _earthRadiusM = 6371000;

class Coordinates {
  final double lat;
  final double lng;
  final double? accuracyM;
  const Coordinates(this.lat, this.lng, {this.accuracyM});
}

enum GeofenceShape { circle, polygon }

class Geofence {
  final String id;
  final String name;
  final GeofenceShape shape;
  final Coordinates? center; // circle
  final double? radiusM; // circle
  final List<Coordinates>? vertices; // polygon
  const Geofence({
    required this.id,
    required this.name,
    required this.shape,
    this.center,
    this.radiusM,
    this.vertices,
  });

  factory Geofence.circle(String id, String name, Coordinates c, double r) =>
      Geofence(id: id, name: name, shape: GeofenceShape.circle, center: c, radiusM: r);
  factory Geofence.polygon(String id, String name, List<Coordinates> v) =>
      Geofence(id: id, name: name, shape: GeofenceShape.polygon, vertices: v);
}

enum GeofenceTransition { enter, exit }

double _toRad(double deg) => deg * math.pi / 180;

/// Haversine great-circle distance in meters.
double haversineM(Coordinates a, Coordinates b) {
  final dLat = _toRad(b.lat - a.lat);
  final dLng = _toRad(b.lng - a.lng);
  final lat1 = _toRad(a.lat);
  final lat2 = _toRad(b.lat);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Ray-casting point-in-polygon on lat/lng.
bool pointInPolygon(Coordinates pt, List<Coordinates> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].lng, yi = ring[i].lat;
    final xj = ring[j].lng, yj = ring[j].lat;
    final intersect = (yi > pt.lat) != (yj > pt.lat) &&
        pt.lng < (xj - xi) * (pt.lat - yi) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

double _distancePointToSegmentM(Coordinates p, Coordinates a, Coordinates b) {
  final latRef = _toRad((a.lat + b.lat) / 2);
  ({double x, double y}) toXY(Coordinates c) => (
        x: _toRad(c.lng) * math.cos(latRef) * _earthRadiusM,
        y: _toRad(c.lat) * _earthRadiusM,
      );
  final P = toXY(p), A = toXY(a), B = toXY(b);
  final dx = B.x - A.x, dy = B.y - A.y;
  final lenSq = dx * dx + dy * dy;
  final t = lenSq == 0
      ? 0.0
      : math.max(0, math.min(1, ((P.x - A.x) * dx + (P.y - A.y) * dy) / lenSq)).toDouble();
  final projX = A.x + t * dx, projY = A.y + t * dy;
  return math.sqrt(math.pow(P.x - projX, 2) + math.pow(P.y - projY, 2)).toDouble();
}

/// Signed distance to boundary (negative = inside).
double signedDistanceToBoundaryM(Coordinates pt, Geofence fence) {
  if (fence.shape == GeofenceShape.circle) {
    return haversineM(pt, fence.center!) - fence.radiusM!;
  }
  final v = fence.vertices!;
  final inside = pointInPolygon(pt, v);
  var minEdge = double.infinity;
  for (var i = 0, j = v.length - 1; i < v.length; j = i++) {
    minEdge = math.min(minEdge, _distancePointToSegmentM(pt, v[j], v[i]));
  }
  return inside ? -minEdge : minEdge;
}

class BoundaryCheck {
  final bool inside;
  final double signedDistanceM;
  const BoundaryCheck(this.inside, this.signedDistanceM);
}

BoundaryCheck checkGeofenceBoundary(Coordinates childCoords, Geofence geofence) {
  final signed = signedDistanceToBoundaryM(childCoords, geofence);
  return BoundaryCheck(signed <= 0, signed);
}

enum FenceState { inside, outside }

class HysteresisConfig {
  final double bufferM;
  final int confirmations;
  final double maxAccuracyM;
  const HysteresisConfig({
    this.bufferM = 30,
    this.confirmations = 2,
    this.maxAccuracyM = 100,
  });
}

class _FenceRuntime {
  FenceState state = FenceState.outside;
  FenceState? pendingSide;
  int pendingCount = 0;
}

class GeofenceHit {
  final Geofence fence;
  final GeofenceTransition transition;
  const GeofenceHit(this.fence, this.transition);
}

/// Per-(child,fence) transition detector. Emits a transition ONLY on a confirmed,
/// buffered boundary crossing — killing GPS-drift "flapping".
class GeofenceTracker {
  final List<Geofence> fences;
  final HysteresisConfig cfg;
  final Map<String, _FenceRuntime> _runtime = {};

  GeofenceTracker(this.fences, [this.cfg = const HysteresisConfig()]);

  /// The buffer to apply to [fence].
  ///
  /// "Inside" needs `signed <= -buffer`, and the deepest a point can be inside a
  /// circle is its radius (at the centre). So a fence no bigger than the buffer
  /// could NEVER be entered — the enter alert was silently impossible, even
  /// standing dead centre. Today's UI enforces a 50m minimum radius, which only
  /// hides this by coincidence; an imported backup carries any radius at all.
  /// Shrink the buffer for such fences instead of letting them go dark.
  ///
  /// Fences larger than the buffer are unaffected, so normal zones behave
  /// exactly as before. Polygons keep the configured buffer: their inward depth
  /// isn't a single number, and they come from the map picker at map scale.
  double _bufferFor(Geofence fence) {
    if (fence.shape != GeofenceShape.circle) return cfg.bufferM;
    final r = fence.radiusM ?? 0;
    return cfg.bufferM < r ? cfg.bufferM : r / 2;
  }

  List<GeofenceHit> update(Coordinates coords, [double accuracyM = 0]) {
    final out = <GeofenceHit>[];
    if (accuracyM > cfg.maxAccuracyM) return out; // reject low-quality fixes

    for (final fence in fences) {
      final rt = _runtime.putIfAbsent(fence.id, () => _FenceRuntime());
      final signed = signedDistanceToBoundaryM(coords, fence);
      final buffer = _bufferFor(fence);

      FenceState? observed;
      if (signed <= -buffer) {
        observed = FenceState.inside;
      } else if (signed >= buffer) {
        observed = FenceState.outside;
      } // else: within buffer band → ambiguous, hold state.

      if (observed != null && observed != rt.state) {
        if (rt.pendingSide == observed) {
          rt.pendingCount += 1;
        } else {
          rt.pendingSide = observed;
          rt.pendingCount = 1;
        }
        if (rt.pendingCount >= cfg.confirmations) {
          rt.state = observed;
          rt.pendingSide = null;
          rt.pendingCount = 0;
          out.add(GeofenceHit(
            fence,
            observed == FenceState.inside
                ? GeofenceTransition.enter
                : GeofenceTransition.exit,
          ));
        }
      } else {
        rt.pendingSide = null;
        rt.pendingCount = 0;
      }
    }
    return out;
  }

  void seed(String fenceId, FenceState state) {
    final rt = _FenceRuntime()..state = state;
    _runtime[fenceId] = rt;
  }
}
