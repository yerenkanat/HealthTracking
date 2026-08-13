/// What the pairing scan is doing, and why it has found nothing.
///
/// Pure Dart on purpose. The scan itself ([scanForBands]) needs a radio and so
/// cannot be unit-tested; the vocabulary it speaks can be, and the pairing page
/// can be driven through every one of these states in a widget test without one.
///
/// This exists because the scan used to collapse four unrelated situations into
/// one empty list — Bluetooth switched off, the permission declined, no watch
/// within range, and the fifteen-second window simply not having elapsed yet.
/// The onboarding page therefore had exactly one thing it could say, «Поиск
/// устройств…», and it said it for ever. A woman whose phone had Bluetooth off
/// was told nothing at all about the one thing standing between her and a paired
/// watch, and nothing on the screen was about her phone.
///
/// The ordering the scanner must observe: is there a radio at all → is the app
/// allowed to use it → is it switched on → has the search window elapsed → did
/// we find anything. Each answer is a different sentence on the screen.
library;

/// A watch seen by the scan.
///
/// [rssi] is the raw signal strength in dBm (negative; closer to zero is
/// stronger). It rides along because two identical `AK-08B` advertisements are
/// otherwise indistinguishable in a list, and the one on the table in front of
/// her is the one she means.
typedef DiscoveredBand = ({String id, String name, int rssi});

/// Whether an advertisement is close enough to describe as a strong signal.
///
/// −75 dBm is the usual "same room" boundary for BLE advertising; below it a
/// watch is typically through a wall or in another room. It labels a row, and
/// nothing else depends on it — a wrong call costs a word, not a connection.
bool isStrongSignal(int rssi) => rssi >= -75;

/// The state of a pairing scan.
///
/// Every value here is one the transport can actually produce; see the mapping
/// in `band_scan.dart`. Nothing describes a connection — the onboarding step
/// records the id she picks and connects afterwards, so "connecting", "connected"
/// and "connection refused" belong to [BandLinkState] in `link_policy.dart`,
/// which this page never sees.
enum BandScanPhase {
  /// The radio is on, we are listening, and the window has not closed yet.
  scanning,

  /// At least one watch has been seen. [BandScanUpdate.searching] says whether
  /// more may still turn up.
  found,

  /// The window closed and nothing answered. Distinct from [scanning]: it is the
  /// state the old page could never reach, and the reason it span for ever.
  noneNearby,

  /// The adapter is off (or on its way off). Her phone, not her watch.
  bluetoothOff,

  /// The OS refused us the radio: Android 12+ BLUETOOTH_SCAN declined, or iOS
  /// Bluetooth permission declined. No amount of waiting fixes it.
  permissionDenied,

  /// This handset has no Bluetooth LE at all. Retrying is pointless and
  /// "switch Bluetooth on" would be a lie.
  unsupported,

  /// The scan itself failed for some other reason. Retrying is reasonable.
  failed,
}

/// One frame of a scan: what is happening, and what has been seen so far.
class BandScanUpdate {
  final BandScanPhase phase;

  /// Strongest signal first. Non-empty only in [BandScanPhase.found].
  final List<DiscoveredBand> bands;

  /// Whether the radio is still listening. True through [BandScanPhase.scanning]
  /// and through a [BandScanPhase.found] whose window is still open — that is
  /// what lets the page say «Ищем ещё…» under a list of one instead of implying
  /// the list is final.
  final bool searching;

  const BandScanUpdate(
    this.phase, {
    this.bands = const [],
    this.searching = false,
  });

  /// The frame every listener gets first, before any platform call has been
  /// made: something the page can draw, and never an error.
  static const BandScanUpdate opening =
      BandScanUpdate(BandScanPhase.scanning, searching: true);

  /// Whether trying again could plausibly change the answer.
  ///
  /// False for [BandScanPhase.unsupported] — a phone does not grow a radio —
  /// and false while a scan is already running.
  bool get canRetry => switch (phase) {
        BandScanPhase.noneNearby ||
        BandScanPhase.bluetoothOff ||
        BandScanPhase.permissionDenied ||
        BandScanPhase.failed =>
          true,
        BandScanPhase.scanning || BandScanPhase.found => false,
        BandScanPhase.unsupported => false,
      };

  @override
  String toString() =>
      'BandScanUpdate(${phase.name}, ${bands.length} band(s), searching: $searching)';
}
