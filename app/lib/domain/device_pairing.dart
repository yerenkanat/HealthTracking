/// What happened when a device was offered to the server.
///
/// Separate from a plain bool because the three cases need different words on
/// screen and different next steps: one is "write to us", one is "this was
/// reported stolen", and one is "we will try again when you have signal".
library;

enum DevicePairOutcome {
  /// The server took it.
  ok,

  /// Not in our registry — the same watches and tags are sold elsewhere, and
  /// this one did not come from us. She is told how to reach us, because
  /// somebody holding one still wants the service.
  notOurs,

  /// Registered to us and blocked: reported stolen, returned, or replaced
  /// under warranty.
  blocked,

  /// The push did not land — no signal, server down. The device STAYS paired
  /// locally and is re-pushed at the next launch.
  offline,
}

/// What happened when she typed the code from the box.
///
/// Five outcomes because each needs different words and a different next step,
/// and collapsing them into "it did not work" is what makes a customer give up
/// on a device she legitimately owns.
enum DeviceClaimResult {
  /// Claimed and paired.
  ok,

  /// No unit carries that code. The one she can fix herself, by looking at the
  /// box again — so it is phrased as a typo, not as an accusation.
  unknownCode,

  /// Someone else got there first. Either a second-hand unit, or somebody
  /// shared the code — support, not self-service.
  alreadyClaimed,

  /// Ours, and blocked: reported stolen, returned, or replaced under warranty.
  blocked,

  /// Too many guesses from this number in an hour. Says when to come back.
  tooManyAttempts,

  /// No signal, or no server in this build. Nothing was consumed.
  offline,
}
