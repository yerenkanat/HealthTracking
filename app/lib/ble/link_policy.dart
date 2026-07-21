/// When to retry a band connection, how long to wait, and when to stop.
///
/// Pure Dart on purpose: the manager around it cannot be unit-tested (it talks
/// to flutter_blue_plus, which needs a radio), so every decision that can be
/// made without a radio is made here instead and tested by
/// tool/verify_blelink.dart. What is left in the manager is plumbing.
library;

/// Why a connection attempt ended.
enum LinkFailure {
  /// The adapter is off. Retrying is pointless — the adapter state stream will
  /// say when it comes back — but this is not the user's fault or a broken band.
  bluetoothOff,

  /// Android 12+ refused BLUETOOTH_CONNECT/SCAN, or iOS refused Bluetooth.
  /// No amount of retrying fixes this; only the user can, in Settings.
  permissionDenied,

  /// Out of range, off the wrist, asleep, or flat. The ordinary case, and the
  /// only one worth a backoff loop.
  outOfRange,

  /// We connected, but the device does not expose the band's GATT service.
  /// Retrying re-runs discovery against hardware that will never have it — a
  /// wrong pairing, or a firmware whose UUIDs moved. Stop and say so.
  wrongDevice,

  /// Anything else. Treated as transient, because a bug in classification
  /// should cost a few retries rather than silently ending tracking.
  unknown,
}

/// What the UI is allowed to tell her about the band.
enum BandLinkState { idle, connecting, connected, waitingForBluetooth, needsPermission, wrongDevice, lost }

extension LinkFailureX on LinkFailure {
  /// Whether a backoff retry can plausibly succeed without the user acting.
  ///
  /// [bluetoothOff] is false here NOT because it is hopeless but because the
  /// adapter-state stream is the right thing to wait on — a timer that retries
  /// every 30s while the radio is off is pure battery drain.
  bool get isWorthRetrying => switch (this) {
        LinkFailure.outOfRange || LinkFailure.unknown => true,
        LinkFailure.bluetoothOff ||
        LinkFailure.permissionDenied ||
        LinkFailure.wrongDevice =>
          false,
      };

  BandLinkState get state => switch (this) {
        LinkFailure.bluetoothOff => BandLinkState.waitingForBluetooth,
        LinkFailure.permissionDenied => BandLinkState.needsPermission,
        LinkFailure.wrongDevice => BandLinkState.wrongDevice,
        LinkFailure.outOfRange || LinkFailure.unknown => BandLinkState.lost,
      };
}

/// Guess the failure from a platform exception.
///
/// flutter_blue_plus surfaces platform errors as text, so this matches on text.
/// Deliberately conservative: anything unrecognised is [LinkFailure.unknown],
/// which retries. Mislabelling a transient failure as permanent would end
/// tracking for the session, which is far worse than a few wasted retries.
LinkFailure classifyLinkError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('permission') || s.contains('unauthorized') || s.contains('denied')) {
    return LinkFailure.permissionDenied;
  }
  if (s.contains('adapter is off') || s.contains('bluetooth off') || s.contains('poweredoff')) {
    return LinkFailure.bluetoothOff;
  }
  if (s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('unreachable') ||
      s.contains('disconnected')) {
    return LinkFailure.outOfRange;
  }
  return LinkFailure.unknown;
}

/// Capped exponential backoff: 1s, 2s, 4s, 8s, 16s, then 30s for ever.
///
/// [attempt] is clamped before it is shifted. An unclamped `1 << attempt` is a
/// real hazard, not a theoretical one: a band that is simply out of range all
/// night reaches attempt 64 in a few hours, and in Dart `1 << 64` is 0 — the
/// backoff would silently collapse to a tight retry loop at exactly the moment
/// it is supposed to be conserving battery.
Duration reconnectDelay(int attempt) {
  final safe = attempt.clamp(0, 5);
  final ms = (1000 * (1 << safe)).clamp(1000, 30000);
  return Duration(milliseconds: ms);
}
