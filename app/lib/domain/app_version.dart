/// App version gating — is this build too old to keep running, and is a newer
/// one available? PURE Dart → verified by tool/verify_app_version.dart.
///
/// The server owns the policy (GET /app/version → minBuild / latestBuild); the
/// app only compares its own build number against it. A build below [minBuild]
/// is blocked outright behind the force-update screen, because it may be talking
/// to an API it no longer matches or missing a safety fix. A build below
/// latestBuild but at/above minBuild is fine — it just earns a soft "update
/// available" nudge, never a block.
library;

/// This build's number — the `+N` in pubspec's `version: x.y.z+N`. Bump both
/// together on every release so the gate compares like with like.
const int currentAppBuild = 1;

/// True when [currentBuild] is older than the server's required minimum, so the
/// app must block until updated. A missing/zero minimum never blocks (the server
/// has set no floor yet).
bool appUpdateRequired(int currentBuild, int minBuild) => minBuild > 0 && currentBuild < minBuild;

/// True when a newer build than [currentBuild] exists but the current one is
/// still allowed to run — a soft nudge, not a block.
bool appUpdateAvailable(int currentBuild, int latestBuild) => currentBuild < latestBuild;

/// How long the soft nudge stays quiet after she dismisses it.
///
/// A nudge that returns on every launch is not a nudge, it is a tax — and the
/// thing it teaches is to dismiss update prompts without reading them, which is
/// exactly the habit that makes the HARD block land badly when it eventually
/// comes. A week is long enough to be forgettable and short enough that a build
/// does not rot for months.
const Duration updateNudgeSnooze = Duration(days: 7);

/// Should the soft "update available" nudge be on screen right now?
///
/// The whole policy in one pure function, so the answer is testable without a
/// widget and cannot drift between the controller and the UI:
///
///  * Below [minBuild] the HARD block wins and this returns false. Both at once
///    would be a nudge drawn behind a full-screen gate — invisible, and asking
///    for something she is already being forced to do.
///  * At or above [latestBuild] there is nothing to offer.
///  * A build newer than the one she last dismissed ([dismissedBuild]) asks
///    again immediately: she snoozed *that* release, not every future one.
///  * Otherwise it stays quiet until [updateNudgeSnooze] has elapsed since
///    [dismissedAt]. A null [dismissedAt] means she has never dismissed it.
bool showUpdateNudge({
  required int currentBuild,
  required int minBuild,
  required int latestBuild,
  required int dismissedBuild,
  required DateTime? dismissedAt,
  required DateTime now,
}) {
  if (appUpdateRequired(currentBuild, minBuild)) return false;
  if (!appUpdateAvailable(currentBuild, latestBuild)) return false;
  if (latestBuild > dismissedBuild) return true;
  if (dismissedAt == null) return true;
  return !now.isBefore(dismissedAt.add(updateNudgeSnooze));
}
