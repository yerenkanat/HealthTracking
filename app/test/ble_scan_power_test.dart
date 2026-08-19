/// TODO §10.13 — the child's beacon was only ever scanned for at LOW POWER,
/// including while she was watching the map.
///
/// The filed defect said the opposite: "scanning never drops to low power when
/// backgrounded". It never ROSE. `_startBeaconScan(foreground: false)` was the
/// only call site, and `setScanMode` — the one thing that could have raised it,
/// documented as "called by AdaptiveScanController.apply" — had no caller in
/// lib, test or tool, because nothing ever constructed that controller either.
/// So `AndroidScanMode.lowLatency` was unreachable code, and the scan that
/// notices a child's tag arriving ran on lowPower's long duty cycle always.
///
/// WHAT WOULD FAIL IF EACH FIX WERE REVERTED — the only property of a test that
/// matters:
///
///   * restore `_startBeaconScan(foreground: false)` in `start()` and the first
///     scan of every session is lowPower while she is looking at the app;
///   * remove the `AppForeground` listener and the mode never changes again for
///     the life of the process, whatever the phone does;
///   * stop writing `AppForeground.instance` from `_LifecycleHooks` and the
///     manager listens to a value nobody ever moves — the same defect one layer
///     up, and invisible from inside `ble/`;
///   * drop the `_scanningForeground` guard and every `inactive` flicker (a
///     pulled notification shade, an incoming call) stops the radio and starts
///     it again, opening a gap an advertisement can land in;
///   * restore the bare `await FlutterBluePlus.stopScan()` and a stop that
///     throws abandons the restart — the beacon scan is off for the rest of the
///     session and nothing says so.
///
/// The pin throughout is the safety floor: `lowPower` was the behaviour before
/// this change, so no state this code can reach may scan weaker than `lowPower`.
/// A flat battery is bad; a tag that goes unnoticed is worse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/app/app.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/app/app_foreground.dart';
import 'package:fcs_app/ble/ble_device_manager.dart';
import 'package:fcs_app/data/content_store.dart';
import 'package:fcs_app/domain/timeline_content.dart';

/// Records WHICH mode reached the radio. "startScan was called" is not the
/// claim being tested; "startScan was called with lowLatency" is.
class _Radio {
  final modes = <AndroidScanMode>[];
  int stops = 0;
  bool stopThrows = false;

  Future<void> start(AndroidScanMode mode) async => modes.add(mode);

  Future<void> stop() async {
    stops++;
    if (stopThrows) throw StateError('android: scan already stopping');
  }
}

String _name(AndroidScanMode m) => switch (m.value) {
      -1 => 'opportunistic',
      0 => 'lowPower',
      1 => 'balanced',
      2 => 'lowLatency',
      _ => 'unknown',
    };

({BleDeviceManager ble, _Radio radio, AppForeground fg}) make({
  bool foreground = true,
}) {
  final radio = _Radio();
  final fg = AppForeground(foreground: foreground);
  final ble = BleDeviceManager(BleManagerConfig(
    bandRemoteId: 'AA:BB:CC:DD:EE:FF',
    childBeaconUuid: 'f7826da6-4fa2-4e98-8024-bc5b71e0893e',
    getBpCalibration: () => null,
    foreground: fg,
    startScan: radio.start,
    stopScan: radio.stop,
    // An empty stream of the manager's own, so the test never subscribes to the
    // plugin's static broadcast stream and never leaves a listener on it.
    scanResults: () => const Stream<List<ScanResult>>.empty(),
  ));
  return (ble: ble, radio: radio, fg: fg);
}

void main() {
  test('she is looking at the app: the first scan of the session is low latency', () async {
    final (:ble, :radio, fg: _) = make(foreground: true);
    addTearDown(ble.dispose);

    await ble.start();

    expect(radio.modes.map(_name), ['lowLatency'],
        reason: 'the beacon scan started at lowPower while she watched the map — '
            'a tag arriving takes longer to be seen than it needs to');
  });

  test('the phone goes in her pocket: the scan drops to low power', () async {
    final (:ble, :radio, :fg) = make(foreground: true);
    addTearDown(ble.dispose);
    await ble.start();

    fg.value = false;
    await Future<void>.delayed(Duration.zero);

    expect(radio.modes.map(_name), ['lowLatency', 'lowPower']);
    expect(radio.stops, 1, reason: 'the old scan must be stopped before the new one starts');
  });

  test('she opens it again: the scan rises again', () async {
    final (:ble, :radio, :fg) = make(foreground: true);
    addTearDown(ble.dispose);
    await ble.start();

    fg.value = false;
    await Future<void>.delayed(Duration.zero);
    fg.value = true;
    await Future<void>.delayed(Duration.zero);

    expect(radio.modes.map(_name), ['lowLatency', 'lowPower', 'lowLatency'],
        reason: 'one trip to the home screen must not pin the scan low for the session');
  });

  test('launched into the background: low power, exactly as before', () async {
    final (:ble, :radio, fg: _) = make(foreground: false);
    addTearDown(ble.dispose);

    await ble.start();

    expect(radio.modes.map(_name), ['lowPower']);
  });

  // ---- the safety floor ----
  //
  // This is the constraint that outranks battery. Before this change the scan
  // was lowPower at every instant. After it, the scan must never be WEAKER than
  // lowPower at any instant — not while a child is out of a zone, not during an
  // unresolved SOS, not mid check-in. The guarantee is structural rather than
  // situational: this code has exactly two reachable modes and the weaker of
  // them IS the old behaviour, so no screen, alert or lifecycle order can
  // produce a regression. This test is what holds that shape in place.
  test('no reachable state scans weaker than the old behaviour', () async {
    final (:ble, :radio, :fg) = make(foreground: true);
    addTearDown(ble.dispose);
    await ble.start();

    // Every lifecycle order a phone actually produces, including the ones that
    // repeat and the ones that alternate quickly.
    for (final visible in [
      false, true, true, false, false, true, false, true, true, false, true,
    ]) {
      fg.value = visible;
      await Future<void>.delayed(Duration.zero);
    }

    expect(radio.modes, isNotEmpty);
    for (final m in radio.modes) {
      expect(m.value, greaterThanOrEqualTo(AndroidScanMode.lowPower.value),
          reason: 'scanned at ${_name(m)} — weaker than the lowPower this code '
              'used before, so a tag arriving would be noticed LATER than it '
              'was before the battery fix. That is a safety regression.');
    }
    expect(radio.modes.last.value, AndroidScanMode.lowLatency.value,
        reason: 'the sequence ends foreground');
  });

  test('an unchanged mode does not stop and restart the radio', () async {
    final (:ble, :radio, :fg) = make(foreground: true);
    addTearDown(ble.dispose);
    await ble.start();

    // `inactive` over a screen she is still looking at, a shade pull, a rebuild:
    // all of these arrive as "still foreground".
    await ble.setScanMode(foreground: true);
    await ble.setScanMode(foreground: true);
    fg.value = true;
    await Future<void>.delayed(Duration.zero);

    expect(radio.stops, 0,
        reason: 'each stop/start opens a window with no scan running at all; an '
            'advertisement that lands in it is an arrival nobody saw');
    expect(radio.modes.map(_name), ['lowLatency']);
  });

  test('a stop that fails still leaves a scan running', () async {
    final (:ble, :radio, :fg) = make(foreground: true);
    addTearDown(ble.dispose);
    await ble.start();
    radio.stopThrows = true;

    fg.value = false;
    await Future<void>.delayed(Duration.zero);

    expect(radio.stops, 1);
    expect(radio.modes.map(_name), ['lowLatency', 'lowPower'],
        reason: 'stopScan threw and the restart was abandoned: the child beacon '
            'scan is off for the rest of the session, silently');
  });

  test('a failed start is not remembered as the running mode', () async {
    final radio = _Radio();
    final fg = AppForeground();
    var fail = true;
    final ble = BleDeviceManager(BleManagerConfig(
      bandRemoteId: 'AA:BB:CC:DD:EE:FF',
      childBeaconUuid: 'f7826da6-4fa2-4e98-8024-bc5b71e0893e',
      getBpCalibration: () => null,
      foreground: fg,
      startScan: (m) async {
        if (fail) throw StateError('android denied BLUETOOTH_SCAN');
        radio.modes.add(m);
      },
      stopScan: radio.stop,
      scanResults: () => const Stream<List<ScanResult>>.empty(),
    ));
    addTearDown(ble.dispose);

    await ble.start(); // permission refused → nothing is scanning
    await Future<void>.delayed(Duration.zero);
    fail = false;

    // Same foreground value as the failed attempt. Had the manager recorded
    // "we are scanning in foreground mode", this would be skipped as a no-op
    // and the radio would stay off for good.
    await ble.setScanMode(foreground: true);

    expect(radio.modes.map(_name), ['lowLatency']);
  });

  // ---- the producer end ----
  //
  // The manager listening to AppForeground is worth nothing unless something
  // writes to it. `_LifecycleHooks` in app/app.dart is the app's ONLY
  // WidgetsBindingObserver, and this is the assertion that it publishes.
  group('the app lifecycle is what moves it', () {
    setUp(() => AppForeground.instance.value = true);
    tearDown(() => AppForeground.instance.value = true);

    testWidgets('paused, hidden and detached are background; resumed and inactive are not',
        (tester) async {
      await tester.pumpWidget(FcsApp(
        controller: AppController(),
        content: ContentStore(const ContentCatalog({})),
      ));
      await tester.pump();

      for (final (state, expected) in <(AppLifecycleState, bool)>[
        (AppLifecycleState.paused, false),
        (AppLifecycleState.resumed, true),
        (AppLifecycleState.hidden, false),
        (AppLifecycleState.resumed, true),
        // Still on screen: a pulled notification shade or an incoming call.
        (AppLifecycleState.inactive, true),
        (AppLifecycleState.detached, false),
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(AppForeground.instance.value, expected,
            reason: '$state should read as ${expected ? 'foreground' : 'background'}');
      }
    });
  });
}
