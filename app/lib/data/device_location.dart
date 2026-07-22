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
enum LocationFailure { denied, deniedForever, off, unavailable }

/// How long to wait for a fix before giving up.
///
/// There was no limit. A cold GPS indoors can take a very long time and, with
/// location services in an odd state, can simply never answer — and both
/// callers hold a spinner across this await. On the onboarding step that gates
/// finishing setup, that is a screen she cannot leave.
///
/// Twenty seconds is long enough for a genuine cold start and short enough
/// that "it isn't working, try outside" arrives while she is still holding the
/// phone. Timing out maps to [LocationFailure.unavailable], which is precisely
/// the failure worth retrying somewhere with sky.
///
/// Deliberately NOT falling back to getLastKnownPosition, which the plugin
/// recommends generally: a cached fix could centre "Home" on wherever she was
/// yesterday, and a zone around the wrong place produces alerts about a
/// stranger's street. That is the failure this whole file exists to prevent.
const locationTimeout = Duration(seconds: 20);

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
        LocationFailure.off => 'zone_loc_off',
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

/// True when the OS location prompt has NOT yet been answered — so the next
/// [currentCoordinates] call is what pops the system dialog. The UI uses this to
/// show a plain-language primer first, and ONLY when it will actually matter: if
/// permission is already granted (or permanently denied), priming again would
/// just be a pointless extra tap.
///
/// Returns false under the test override, where no real OS prompt occurs.
Future<bool> locationPermissionUndecided() async {
  if (debugLocationOverride != null) return false;
  try {
    return (await Geolocator.checkPermission()) == LocationPermission.denied;
  } catch (_) {
    return false;
  }
}

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
    final p = await Geolocator.getCurrentPosition(timeLimit: locationTimeout);
    return LocationResult.ok(Coordinates(p.latitude, p.longitude));
  } on LocationServiceDisabledException {
    // Granted the permission, but location is switched off device-wide. The
    // remedy is neither "allow the app" nor "go outside" — it is a different
    // toggle in a different place, and sending her to the app's permission
    // screen for it wastes the one thing she is trying to finish.
    return const LocationResult.failed(LocationFailure.off);
  } catch (_) {
    // Includes TimeoutException from timeLimit above.
    return const LocationResult.failed(LocationFailure.unavailable);
  }
}
