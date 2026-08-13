/// The real BLE scan behind onboarding's «choose your bracelet» step.
///
/// [OnboardingFlow] has taken a `scanBands` callback since it was written, and
/// nothing ever passed one: `_PairBandPage` rendered its skip line over an empty
/// area, so on a real handset step 4 asked the user to pick her watch from a
/// list that could not exist. The screen was finished; the scan behind it was
/// never connected.
///
/// It then had the opposite defect. The stream emitted a bare `List` and
/// swallowed every reason it could be empty — radio off, permission declined,
/// no watch nearby, window not elapsed — so the page had one sentence for four
/// situations and showed it for ever. With Bluetooth switched off she was told
/// «Поиск устройств…» until she gave up, and nothing anywhere mentioned
/// Bluetooth. It now emits [BandScanUpdate]: the same "never throws, never
/// delivers an error" contract, but carrying WHY.
///
/// Flutter- and radio-coupled (flutter_blue_plus), so the decisions that can be
/// made without a radio live next door where they are unit-tested:
/// "is this advertisement one of our watches" in [looksLikeStarmaxWatch], the
/// state vocabulary in [BandScanUpdate], and the error→reason mapping in
/// [classifyLinkError]. What is left here is start-scan / collect / stop.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'band_scan_state.dart';
import 'link_policy.dart';
import 'watch_identity.dart';

/// Watches seen so far, strongest signal first, with the reason for an empty
/// list attached.
///
/// Never throws and never delivers an error: a page mid-onboarding must not be
/// handed an exception, and a test binding with no platform channel has to land
/// somewhere drawable too. The first frame is always
/// [BandScanUpdate.opening] — emitted synchronously on listen, before any
/// platform call — so the page has something to render immediately.
Stream<BandScanUpdate> scanForBands({
  Duration timeout = const Duration(seconds: 15),
}) {
  final found = <String, ({DiscoveredBand band, int rssi})>{};
  late StreamController<BandScanUpdate> out;
  StreamSubscription<List<ScanResult>>? sub;
  StreamSubscription<BluetoothAdapterState>? adapterSub;
  Timer? window;
  // Once the scan has landed on a reason (radio off, refused, failed), results
  // arriving late must not quietly redraw it as "searching".
  var settled = false;
  var windowOpen = true;

  void push(BandScanPhase phase, {bool searching = false}) {
    if (out.isClosed) return;
    out.add(BandScanUpdate(
      phase,
      bands: [
        for (final e in (found.values.toList()
              ..sort((a, b) => b.rssi.compareTo(a.rssi))))
          e.band
      ],
      searching: searching,
    ));
  }

  void settle(BandScanPhase phase) {
    settled = true;
    window?.cancel();
    push(phase);
  }

  /// What the list means right now, given the radio is healthy.
  void emitProgress() {
    if (settled) return;
    if (found.isNotEmpty) {
      push(BandScanPhase.found, searching: windowOpen);
    } else if (windowOpen) {
      push(BandScanPhase.scanning, searching: true);
    } else {
      // The window closed with nothing in it. THIS is the state the page could
      // never reach before, and the whole reason the spinner never stopped.
      push(BandScanPhase.noneNearby);
    }
  }

  /// An adapter state is the most reliable reason we have: on iOS a declined
  /// permission shows up here as `unauthorized` rather than as a thrown error.
  BandScanPhase? phaseForAdapter(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.off ||
        BluetoothAdapterState.turningOff =>
          BandScanPhase.bluetoothOff,
        BluetoothAdapterState.unauthorized => BandScanPhase.permissionDenied,
        BluetoothAdapterState.unavailable => BandScanPhase.unsupported,
        // `unknown` and `turningOn` are transitional — saying anything about
        // them would be guessing at a state that is about to resolve itself.
        BluetoothAdapterState.on ||
        BluetoothAdapterState.turningOn ||
        BluetoothAdapterState.unknown =>
          null,
      };

  /// Open the radio and, if it refuses, say why in the same vocabulary.
  Future<void> runScan() async {
    window?.cancel();
    window = Timer(timeout, () {
      windowOpen = false;
      emitProgress();
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      settle(switch (classifyLinkError(e)) {
        LinkFailure.permissionDenied => BandScanPhase.permissionDenied,
        LinkFailure.bluetoothOff => BandScanPhase.bluetoothOff,
        LinkFailure.outOfRange ||
        LinkFailure.wrongDevice ||
        LinkFailure.unknown =>
          BandScanPhase.failed,
      });
    }
  }

  Future<void> start() async {
    try {
      // A handset with no BLE at all. Asked first, because every sentence below
      // it ("switch Bluetooth on", "try again") would be false here.
      if (!await FlutterBluePlus.isSupported) {
        settle(BandScanPhase.unsupported);
        return;
      }
    } catch (_) {
      // No platform channel (a test binding, or a desktop build). Not a claim
      // worth making either way — fall through and let the scan below say.
    }

    try {
      adapterSub = FlutterBluePlus.adapterState.listen(
        (s) {
          final bad = phaseForAdapter(s);
          if (bad != null) {
            settle(bad);
          } else if (s == BluetoothAdapterState.on && settled) {
            // She switched it on while looking at the "Bluetooth is off" plate.
            // Pick the search back up rather than making her tap «Искать снова».
            settled = false;
            windowOpen = true;
            emitProgress();
            unawaited(runScan());
          }
        },
        onError: (_) {/* an adapter we cannot read is not a reason to shout */},
      );
    } catch (_) {
      // Same: no channel. The scan attempt below is the honest test.
    }

    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final adv = r.advertisementData;
        final name =
            adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
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
          band: (id: id, name: name.isEmpty ? id : name, rssi: r.rssi),
          rssi: r.rssi,
        );
      }
      // A watch answering proves the radio is fine, whatever we concluded
      // earlier from a failed platform call.
      settled = false;
      emitProgress();
    }, onError: (_) {/* a scan that fails delivers nothing, not an error */});

    // `startScan(timeout:)` stops the radio when the window closes; runScan's
    // own timer is what turns "still looking" into "looked, found nothing" on
    // the screen.
    await runScan();
  }

  out = StreamController<BandScanUpdate>(
    onListen: () {
      // Synchronous, before any platform call: the page always has a frame.
      if (!out.isClosed) out.add(BandScanUpdate.opening);
      unawaited(start());
    },
    onCancel: () async {
      window?.cancel();
      await sub?.cancel();
      await adapterSub?.cancel();
      // Leaving the scan running costs radio for a page nobody is on. NOT
      // awaited: cancelling a stream must not wait on a platform call, which on
      // a device with no radio (or in a test with no channel) may never answer —
      // and `stream.first` awaits this cancel before it completes.
      unawaited(FlutterBluePlus.stopScan().catchError((Object _) {}));
    },
  );
  return out.stream;
}

/// Ask Android to switch Bluetooth on, for the pairing page's «Включить
/// Bluetooth» button.
///
/// Android only — iOS has no API for it, and the button is not offered there
/// rather than being offered and doing nothing. Returns whether the radio is on
/// afterwards, so a refusal at the system dialog is not reported as success.
Future<bool> requestBluetoothOn() async {
  try {
    await FlutterBluePlus.turnOn();
    return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
  } catch (_) {
    return false;
  }
}
