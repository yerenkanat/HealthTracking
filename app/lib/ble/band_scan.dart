/// The real BLE scan behind onboarding's «choose your bracelet» step.
///
/// [OnboardingFlow] has taken a `scanBands` callback since it was written, and
/// nothing ever passed one: `_PairBandPage` rendered its skip line over an empty
/// area, so on a real handset step 4 asked the user to pick her watch from a
/// list that could not exist. The screen was finished; the scan behind it was
/// never connected.
///
/// Flutter- and radio-coupled (flutter_blue_plus), so the decision it makes —
/// "is this advertisement one of our watches" — deliberately lives in the pure
/// [looksLikeStarmaxWatch] next door, where it is unit-tested. What is left here
/// is start-scan / collect / stop, which only a device can exercise.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ui/onboarding/onboarding_flow.dart' show DiscoveredBand;
import 'watch_identity.dart';

/// Watches seen so far, strongest signal first, emitted as they appear.
///
/// Never throws and never delivers an error: the pairing step shows the
/// scanning line while the list is empty, and a Bluetooth radio that is off, a
/// permission the user declined, or a test binding with no platform channel all
/// have to land on that same honest state rather than on a red screen. The
/// caller sees an empty list, which is the truth — we found nothing.
Stream<List<DiscoveredBand>> scanForBands({
  Duration timeout = const Duration(seconds: 15),
}) {
  final found = <String, ({DiscoveredBand band, int rssi})>{};
  late StreamController<List<DiscoveredBand>> out;
  StreamSubscription<List<ScanResult>>? sub;

  void emit() {
    final sorted = found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    if (!out.isClosed) out.add([for (final e in sorted) e.band]);
  }

  Future<void> start() async {
    try {
      sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final adv = r.advertisementData;
          final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
          if (!looksLikeStarmaxWatch(
            name: name,
            serviceUuids: [for (final u in adv.serviceUuids) u.str],
            manufacturerData: adv.manufacturerData,
          )) {
            continue;
          }
          final id = r.device.remoteId.str;
          // A nameless advertisement still pairs — the id is what the app
          // reconnects to — so it is listed under the id rather than dropped.
          found[id] = (
            band: (id: id, name: name.isEmpty ? id : name),
            rssi: r.rssi,
          );
        }
        emit();
      }, onError: (_) {/* a scan that fails delivers nothing, not an error */});
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (_) {
      // No radio, no permission, no platform channel. The list stays empty.
    }
  }

  out = StreamController<List<DiscoveredBand>>(
    onListen: () {
      emit(); // an immediate empty list, so the page has a frame to render
      unawaited(start());
    },
    onCancel: () async {
      await sub?.cancel();
      // Leaving the scan running costs radio for a page nobody is on. NOT
      // awaited: cancelling a stream must not wait on a platform call, which on
      // a device with no radio (or in a test with no channel) may never answer —
      // and `stream.first` awaits this cancel before it completes.
      unawaited(FlutterBluePlus.stopScan().catchError((Object _) {}));
    },
  );
  return out.stream;
}
