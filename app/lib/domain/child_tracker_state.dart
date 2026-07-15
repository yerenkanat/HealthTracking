/// Child tracking view-state derivation. Pure Dart → unit-testable.
/// Turns a raw location fix + the child's geofences into what the map screen shows:
/// which zone the child is in, how fresh the fix is, distance from home, and a
/// warm "arrived 5 min ago" style status line. Owned by Geofencing + UX + L10n.
library;

import '../core/geofence.dart';

enum Freshness { live, recent, stale }

class ChildStatus {
  final Coordinates? location;
  final DateTime? updatedAt;
  final Freshness freshness;
  final String? currentZone; // geofence name, or null if between zones
  final double? distanceFromHomeM; // null if no Home fence / no fix
  final String headline; // localized-upstream summary line

  const ChildStatus({
    required this.location,
    required this.updatedAt,
    required this.freshness,
    required this.currentZone,
    required this.distanceFromHomeM,
    required this.headline,
  });
}

/// Freshness from the age of the last fix. A stale fix must never look "live".
Freshness freshnessOf(Duration age) {
  if (age <= const Duration(minutes: 2)) return Freshness.live;
  if (age <= const Duration(minutes: 15)) return Freshness.recent;
  return Freshness.stale;
}

/// First geofence that contains the point (Home/School), or null if outside all.
String? currentZone(Coordinates coords, List<Geofence> fences) {
  for (final f in fences) {
    if (checkGeofenceBoundary(coords, f).inside) return f.name;
  }
  return null;
}

double? distanceFromHomeM(Coordinates coords, List<Geofence> fences) {
  for (final f in fences) {
    if (f.name.toLowerCase() == 'home' && f.center != null) {
      return haversineM(coords, f.center!);
    }
  }
  return null;
}

/// Warm, human "x ago". Localization layer swaps the words per user.locale.
String formatAgo(Duration age) {
  if (age.inSeconds < 45) return 'just now';
  if (age.inMinutes < 1) return 'less than a minute ago';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  if (age.inHours < 24) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}

/// Derive the full status shown on the tracking screen.
ChildStatus deriveChildStatus({
  required String childName,
  required Coordinates? location,
  required DateTime? updatedAt,
  required List<Geofence> fences,
  required DateTime now,
}) {
  if (location == null || updatedAt == null) {
    return ChildStatus(
      location: null,
      updatedAt: null,
      freshness: Freshness.stale,
      currentZone: null,
      distanceFromHomeM: null,
      headline: "Waiting for $childName's location…",
    );
  }
  final age = now.difference(updatedAt);
  final fresh = freshnessOf(age);
  final zone = currentZone(location, fences);
  final distHome = distanceFromHomeM(location, fences);
  final ago = formatAgo(age);

  final headline = switch ((fresh, zone)) {
    (Freshness.stale, _) => "$childName's location is ${_stalePhrase(age)} — last seen $ago",
    (_, final z?) => '$childName is at $z',
    _ => '$childName is on the move — updated $ago',
  };

  return ChildStatus(
    location: location,
    updatedAt: updatedAt,
    freshness: fresh,
    currentZone: zone,
    distanceFromHomeM: distHome,
    headline: headline,
  );
}

String _stalePhrase(Duration age) => age.inHours >= 1 ? 'out of date' : 'delayed';
