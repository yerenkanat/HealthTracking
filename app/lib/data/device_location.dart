/// Getting the phone's position, with a reason when it fails.
///
/// Two screens ask for this — the zone editor and onboarding — and both used to
/// get it wrong in different ways: the editor failed in silence, and onboarding
/// did not ask at all, writing a hardcoded Almaty coordinate for every user in
/// the country. A geofence centred on somewhere the family has never been is
/// worse than no geofence: it produces "left home" alerts about a stranger's
/// street.
///
/// One place, so the next caller inherits the handling instead of reinventing
/// half of it.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';

import '../core/geofence.dart';

/// Why a position could not be read. Each maps to a different remedy, which is
/// the whole reason they are separate: a denied permission can be granted, a
/// permanently-denied one only from system settings, and a failed fix is worth
/// retrying somewhere with sky.
enum LocationFailure { denied, deniedForever, unavailable }

class LocationResult {
  final Coordinates? coords;
  final LocationFailure? failure;

  const LocationResult.ok(Coordinates this.coords) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : coords = null;

  bool get ok => coords != null;

  /// The l10n key describing this failure, or null when it worked.
  String? get messageKey => switch (failure) {
        LocationFailure.denied => 'zone_loc_denied',
        LocationFailure.deniedForever => 'zone_loc_denied_forever',
        LocationFailure.unavailable => 'zone_loc_failed',
        null => null,
      };
}

/// Stand in for the device, in tests.
///
/// Widget tests have no platform channel, so a real call here never completes
/// and any pumpAndSettle waiting on it times out. Without a seam the only way
/// to test a screen that locates you is not to test it.
@visibleForTesting
Future<LocationResult> Function()? debugLocationOverride;

/// Ask the OS where we are, requesting permission if it has not been decided.
///
/// Never throws: a caller in the middle of onboarding must not be dropped on an
/// error screen because the GPS was cold.
Future<LocationResult> currentCoordinates() async {
  final override = debugLocationOverride;
  if (override != null) return override();
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      return const LocationResult.failed(LocationFailure.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return const LocationResult.failed(LocationFailure.denied);
    }
    final p = await Geolocator.getCurrentPosition();
    return LocationResult.ok(Coordinates(p.latitude, p.longitude));
  } catch (_) {
    return const LocationResult.failed(LocationFailure.unavailable);
  }
}
