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

/// How far ahead of us a fix's timestamp may be before we stop believing it.
///
/// Small skew between a phone and a server is ordinary and must not make every
/// fix look stale.
///
/// Public because the localization layer composes the same sentence and must
/// draw the line in the same place; two copies of this number would drift and
/// the drift would show as a headline that contradicts its own freshness dot.
const clockSkewTolerance = Duration(minutes: 2);

/// Whether a fix's timestamp is far enough ahead of us to be unusable.
bool clockDisagrees(Duration age) => age.isNegative && age.abs() > clockSkewTolerance;

/// Freshness from the age of the last fix. A stale fix must never look "live".
///
/// A NEGATIVE age means the fix claims to be from the future. Beyond a little
/// tolerance that is a clock disagreement, and once the clocks disagree we do
/// not know how old the fix actually is — so we must not claim it is live.
/// "Live" is precisely the word a parent acts on, and this is a child tracker;
/// admitting we cannot tell is the only safe answer.
///
/// Not reachable today — updatedAt comes from the device clock — but
/// ApiClient.lastLocation exists to be wired, and it carries a server timestamp.
Freshness freshnessOf(Duration age) {
  if (clockDisagrees(age)) return Freshness.stale;
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

/// Names that mean "home", across the languages the app ships in.
///
/// A fallback only — the id is the reliable signal. This exists for a zone the
/// user created and named by hand, where there is nothing else to go on.
const _homeNames = {'home', 'дом', 'дома', 'үй', 'уй', 'уйим'};

/// Whether a fence is the family's home.
///
/// Matches the stable id FIRST. The app creates that zone itself with a
/// LOCALIZED display name — l.t('onb_home_label') — so a Russian user's home
/// zone is called "Дом" and a Kazakh user's is "Үй". Matching the name against
/// the literal English 'home', as this used to, meant distance-from-home was
/// silently null for every user of the app's own default language.
bool isHomeFence(Geofence f) =>
    f.id.trim().toLowerCase() == 'home' || _homeNames.contains(f.name.trim().toLowerCase());

double? distanceFromHomeM(Coordinates coords, List<Geofence> fences) {
  for (final f in fences) {
    if (isHomeFence(f) && f.center != null) {
      return haversineM(coords, f.center!);
    }
  }
  return null;
}

/// Warm, human "x ago". Localization layer swaps the words per user.locale.
///
/// A timestamp from the future is not "just now". Every bucket below is a
/// less-than test, so a negative age fell into the first one and a fix the
/// clocks disagree about was described as having arrived this second — the
/// single most reassuring phrase available, at the exact moment we know least.
/// freshnessOf already refuses to call such a fix live; this refuses to
/// describe it, and the callers turn that into an honest sentence.
String? formatAgo(Duration age) {
  if (clockDisagrees(age)) return null;
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
    // Clock disagreement first: with no trustworthy age there is no "last
    // seen", and saying so is the only true thing available.
    _ when ago == null => "Umay can't tell how old $childName's location is — "
        'the phone and the tracker disagree about the time',
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
