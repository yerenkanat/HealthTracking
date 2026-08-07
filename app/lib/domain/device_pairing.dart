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
