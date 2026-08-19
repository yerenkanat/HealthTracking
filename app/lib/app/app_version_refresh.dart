/// The launch-time version check: ask the server what it supports, and hand
/// BOTH numbers to the gate.
///
/// This lived inline in main.dart and read only `minBuild`, so `latestBuild`
/// was parsed by the ApiClient, carried across the wire, and dropped one line
/// before it could do anything. The effect was that the app had exactly two
/// states — fine, and blocked outright — with nothing in between: a mother sat
/// on a stale build indefinitely and then, one server change later, hit a
/// full-screen wall she had never been warned about.
///
/// Extracted here so the call is a function a test can drive end to end, rather
/// than two statements inside `main()` that nothing can reach.
library;

import '../data/api_client.dart';
import 'app_controller.dart';

/// Fetch GET /app/version and apply it. Offline or a failing server leaves the
/// gate exactly as it was — never strand a user who cannot reach us.
Future<void> refreshAppVersionFromApi({
  required ApiClient api,
  required AppController controller,
}) async {
  try {
    final v = await api.getAppVersion();
    controller.applyAppVersion(minBuild: v.minBuild, latestBuild: v.latestBuild);
  } catch (_) {
    // Offline / backend down — do not block, and do not nudge either.
  }
}
