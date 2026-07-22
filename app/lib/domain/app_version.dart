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
