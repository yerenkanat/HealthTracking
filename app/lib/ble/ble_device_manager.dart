/// BLEDeviceManager — Flutter orchestrator over flutter_blue_plus for BOTH the
/// mother's smart band (connect + notify → triage) and the child's beacon (scan).
///
/// This file is Flutter-coupled (imports flutter_blue_plus) so it is NOT part of
/// the pure-Dart unit-test surface; the logic it delegates to (parsers, triage,
/// calibration, smoother) IS unit-tested. Owned by Hardware Integration + Mobile
/// Architect, with OB-GYN's on-device triage wired to fire even offline.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app/app_foreground.dart';
import '../core/triage.dart';
import 'parsers/band_parser.dart';
import 'parsers/beacon_parser.dart';
import 'calibration.dart';
import 'link_policy.dart';

// OEM band's proprietary NOTIFY channel (⚠ confirm per firmware).
final _bandService = Guid('0000fee0-0000-1000-8000-00805f9b34fb');
final _bandNotify = Guid('0000fee1-0000-1000-8000-00805f9b34fb');

class BleManagerConfig {
  final String bandRemoteId;
  final String childBeaconUuid;
  final BpCalibration? Function() getBpCalibration;

  /// Whether the app is in front of her. The beacon scan follows it: low
  /// latency while she is looking, low power once she is not. Defaults to the
  /// app-wide [AppForeground.instance] that `_LifecycleHooks` writes to.
  final AppForeground? foreground;

  /// Seams over the three flutter_blue_plus statics the beacon scan touches.
  ///
  /// They exist so a test can assert WHICH [AndroidScanMode] reached the radio,
  /// which is the whole behaviour here — `startScan` was called is not the
  /// claim, `startScan` was called with `lowLatency` is. The statics go through
  /// a platform channel, so nothing else would run under `flutter test`.
  final Future<void> Function(AndroidScanMode mode)? startScan;
  final Future<void> Function()? stopScan;
  final Stream<List<ScanResult>> Function()? scanResults;

  const BleManagerConfig({
    required this.bandRemoteId,
    required this.childBeaconUuid,
    required this.getBpCalibration,
    this.foreground,
    this.startScan,
    this.stopScan,
    this.scanResults,
  });
}

class BleDeviceManager {
  final BleManagerConfig cfg;

  final _telemetry = StreamController<(BandTelemetry, TriageResult)>.broadcast();
  final _emergency = StreamController<(BandTelemetry, TriageResult)>.broadcast();
  final _beacon = StreamController<BeaconReading>.broadcast();

  Stream<(BandTelemetry, TriageResult)> get onTelemetry => _telemetry.stream;
  Stream<(BandTelemetry, TriageResult)> get onEmergency => _emergency.stream;
  Stream<BeaconReading> get onBeacon => _beacon.stream;

  final _smoothers = <String, DistanceSmoother>{};
  final _pending = BandFrame();
  Timer? _flushTimer;
  int _reconnectAttempts = 0;
  StreamSubscription<List<ScanResult>>? _scanSub;

  // Every subscription and timer below used to be created and then forgotten.
  // They are fields now so they can be cancelled — see _connectBand and dispose.
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _reconnectTimer;
  BluetoothDevice? _band;
  bool _connecting = false;
  bool _disposed = false;

  final _status = StreamController<BandLinkState>.broadcast();

  /// What the band is doing, for the UI to show.
  ///
  /// Nothing exposed this before, so a band that had been out of range since
  /// morning looked exactly like a band that was connected and quiet: the
  /// dashboard's last reading simply got older. On a product whose promise is
  /// noticing a dangerous reading, "not measuring" has to be visible.
  Stream<BandLinkState> get onStatus => _status.stream;
  BandLinkState get status => _statusValue;
  BandLinkState _statusValue = BandLinkState.idle;

  void _setStatus(BandLinkState s) {
    if (_disposed || s == _statusValue) return;
    _statusValue = s;
    _status.add(s);
  }

  BleDeviceManager(this.cfg);

  AppForeground get _foreground => cfg.foreground ?? AppForeground.instance;

  /// What the running scan was started for, or null when nothing is scanning.
  /// Only used to skip a restart that would change nothing — see [setScanMode].
  bool? _scanningForeground;

  Future<void> start() async {
    if (_disposed) return;
    // Watch the adapter for the life of the manager rather than awaiting it
    // once. `firstWhere` never completes while Bluetooth stays off, so start()
    // hung for ever and the caller's `await ble.start()` never returned — the
    // beacon scan below was never reached either, taking child tracking down
    // with it. Now a radio switched on at any point resumes the band.
    _adapterSub ??= FlutterBluePlus.adapterState.listen(
      (s) {
        if (_disposed) return;
        if (s == BluetoothAdapterState.on) {
          _reconnectAttempts = 0;
          unawaited(_connectBand());
        } else {
          _setStatus(BandLinkState.waitingForBluetooth);
        }
      },
      // `adapterState` is `async*` and asks the platform for the current state
      // on first listen. With no onError that failure — an unsupported host, a
      // plugin not registered — left the zone as an unhandled async error, and
      // it must not take the beacon scan below down with it: the band is one
      // of two things this manager does.
      onError: (Object e) {
        if (_disposed) return;
        _setStatus(classifyLinkError(e).state);
      },
    );

    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      await _connectBand();
    } else {
      _setStatus(BandLinkState.waitingForBluetooth);
    }
    // The beacon scan follows the app's lifecycle from here on, and starts at
    // whatever the app is right now — which at launch is foreground, so the
    // first scan of the session is lowLatency.
    //
    // It was hard-coded `foreground: false`, and the only thing that could ever
    // have raised it (setScanMode) had no caller, so the scan that notices a
    // child's tag arriving has only ever run on lowPower's long duty cycle,
    // including while she was watching the map.
    _foreground.addListener(_onForegroundChanged);
    _startBeaconScan(foreground: _foreground.value);
  }

  void _onForegroundChanged() =>
      unawaited(setScanMode(foreground: _foreground.value));

  // ---- Smart band: connect + notify, with capped-backoff reconnect ----
  Future<void> _connectBand() async {
    // A single attempt at a time. Without this latch the retry timer and the
    // adapter-state listener could both enter here and each leave a live
    // subscription behind.
    if (_disposed || _connecting) return;
    _connecting = true;
    _setStatus(BandLinkState.connecting);
    final device = BluetoothDevice.fromId(cfg.bandRemoteId);
    _band = device;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      if (_disposed) {
        await device.disconnect();
        return;
      }
      _reconnectAttempts = 0;

      // Replace, never accumulate. Each reconnect used to add another
      // connectionState listener without cancelling the last, so one disconnect
      // called _handleBandDisconnect once per listener, each scheduling its own
      // reconnect — the listener count doubled every cycle. A band left out of
      // range overnight woke up to thousands of connect attempts a minute.
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _handleBandFailure(LinkFailure.outOfRange);
        }
      });

      final services = await device.discoverServices();
      final svc = services.where((s) => s.serviceUuid == _bandService).firstOrNull;
      final chr =
          svc?.characteristics.where((c) => c.characteristicUuid == _bandNotify).firstOrNull;
      if (chr == null) {
        // firstWhere threw a StateError here, which the blanket catch below
        // turned into "disconnected" and retried for ever against hardware that
        // does not have the service. That is a wrong pairing or moved firmware
        // UUIDs — a permanent condition worth reporting once, not a retry loop.
        _handleBandFailure(LinkFailure.wrongDevice);
        return;
      }
      await chr.setNotifyValue(true);
      await _valueSub?.cancel();
      _valueSub = chr.onValueReceived.listen((value) => _onBandFrame(Uint8List.fromList(value)));
      _setStatus(BandLinkState.connected);
    } catch (e) {
      _handleBandFailure(classifyLinkError(e));
    } finally {
      _connecting = false;
    }
  }

  void _handleBandFailure(LinkFailure failure) {
    if (_disposed) return;
    _setStatus(failure.state);
    if (!failure.isWorthRetrying) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay(_reconnectAttempts), () {
      // The timer was unheld before, so dispose() could not stop it: it fired
      // afterwards, reconnected, and added to a closed StreamController —
      // "Cannot add new events after calling close", thrown from a timer
      // callback where nothing catches it.
      if (_disposed) return;
      unawaited(_connectBand());
    });
    _reconnectAttempts++;
  }

  /// Coalesce HR/SpO2/BP/temp frames arriving within 400ms into one record.
  void _onBandFrame(Uint8List value) {
    final res = parseBandFrame(value, validateChecksum: true);
    if (!res.ok) return;
    final f = res.frame;
    _pending
      ..heartRateBpm = f.heartRateBpm ?? _pending.heartRateBpm
      ..spo2Pct = f.spo2Pct ?? _pending.spo2Pct
      ..systolicMmHg = f.systolicMmHg ?? _pending.systolicMmHg
      ..diastolicMmHg = f.diastolicMmHg ?? _pending.diastolicMmHg
      ..coreTempC = f.coreTempC ?? _pending.coreTempC
      ..skinTempC = f.skinTempC ?? _pending.skinTempC
      ..duringSleep = f.duringSleep ?? _pending.duringSleep;

    _flushTimer ??= Timer(const Duration(milliseconds: 400), _flushFrame);
  }

  void _flushFrame() {
    _flushTimer = null;
    if (_disposed) return;
    final f = _pending;
    if (f.isEmpty) return;

    var sys = f.systolicMmHg;
    var dia = f.diastolicMmHg;
    if (sys != null && dia != null) {
      final c = applyBpCalibration(sys, dia, cfg.getBpCalibration());
      sys = c.systolic;
      dia = c.diastolic;
    }

    final telemetry = BandTelemetry(
      coreTempC: f.coreTempC,
      skinTempC: f.skinTempC,
      heartRateBpm: f.heartRateBpm,
      spo2Pct: f.spo2Pct,
      systolicMmHg: sys,
      diastolicMmHg: dia,
      duringSleep: f.duringSleep ?? false,
      // A band on her wrist measured this. Stated rather than defaulted: the
      // fever rule branches on it, and this side of the branch warns without
      // ever raising an emergency — the band's `skinToCoreTempC` has a stated
      // input site and a tested conversion, but it is still a wrist.
      source: ReadingSource.sensor,
    );

    // OB-GYN: triage ON-DEVICE so emergencies fire even offline.
    final triage = assessTelemetry(telemetry);
    _telemetry.add((telemetry, triage));
    if (triage.forceEmergencyScreen) _emergency.add((telemetry, triage));

    // reset the pending accumulator
    _pending
      ..coreTempC = null
      ..skinTempC = null
      ..heartRateBpm = null
      ..spo2Pct = null
      ..systolicMmHg = null
      ..diastolicMmHg = null
      ..duringSleep = null;
  }

  // ---- Child beacon: passive advertisement scan ----
  void _startBeaconScan({required bool foreground}) {
    if (_disposed) return;
    _scanningForeground = foreground;
    unawaited(_scanSub?.cancel());
    final results$ = cfg.scanResults?.call() ?? FlutterBluePlus.scanResults;
    _scanSub = results$.listen((results) {
      for (final r in results) {
        final md = r.advertisementData.manufacturerData; // {companyId: [bytes]}
        if (md.isEmpty) continue;
        // Rebuild the raw blob (companyId LE prefix + payload) for the parser.
        final entry = md.entries.first;
        final raw = Uint8List.fromList(
          [entry.key & 0xFF, (entry.key >> 8) & 0xFF, ...entry.value],
        );
        final reading = parseIBeacon(raw, r.rssi, DateTime.now());
        if (reading == null ||
            reading.uuid.toLowerCase() != cfg.childBeaconUuid.toLowerCase()) {
          continue;
        }
        final key = '${reading.uuid}:${reading.major}:${reading.minor}';
        final sm = _smoothers.putIfAbsent(key, () => DistanceSmoother(5));
        final smoothed = sm.push(reading.distanceM);
        _beacon.add(BeaconReading(
          uuid: reading.uuid,
          major: reading.major,
          minor: reading.minor,
          rssi: reading.rssi,
          txPower: reading.txPower,
          distanceM: smoothed,
          observedAt: reading.observedAt,
        ));
      }
    });
    // startScan throws when Android denies BLUETOOTH_SCAN. Unawaited, that
    // became an unhandled async error and the scan simply never happened —
    // child proximity dead, with nothing said. Caught, it reaches onStatus.
    final mode =
        foreground ? AndroidScanMode.lowLatency : AndroidScanMode.lowPower;
    final start = cfg.startScan ?? _startPlatformScan;
    unawaited(start(mode).catchError((Object e) {
      // The radio is not scanning after all. Say so, and forget the mode we
      // thought we were in, so the next lifecycle change retries rather than
      // deciding it has nothing to do.
      _scanningForeground = null;
      _setStatus(classifyLinkError(e).state);
    }));
  }

  static Future<void> _startPlatformScan(AndroidScanMode mode) =>
      FlutterBluePlus.startScan(continuousUpdates: true, androidScanMode: mode);

  /// Follow the app in or out of the foreground.
  ///
  /// Wired to [AppForeground] in [start]; `_LifecycleHooks` in app/app.dart is
  /// what writes to that. Two properties this must hold, both safety and not
  /// battery:
  ///
  ///   * **A no-op is a no-op.** Restarting the scan means stopping the radio
  ///     and starting it again, and an advertisement that lands in the gap is
  ///     an arrival nobody saw. `inactive`/`resumed` flickers on every pulled
  ///     notification shade, so without this guard the gap would open dozens of
  ///     times a day for no change of mode at all.
  ///   * **A failed stop must not end the scan.** `stopScan` throwing used to
  ///     abandon the method before the restart, leaving the beacon scan off for
  ///     the rest of the session with nothing said. Whatever the stop did, a
  ///     scan is started afterwards.
  Future<void> setScanMode({required bool foreground}) async {
    if (_disposed) return;
    if (_scanningForeground == foreground) return;
    final stop = cfg.stopScan ?? FlutterBluePlus.stopScan;
    try {
      await stop();
    } catch (_) {
      // Nothing to salvage here, and nothing worth reporting: the start below
      // is what decides whether we are scanning.
    }
    if (_disposed) return;
    _startBeaconScan(foreground: foreground);
  }

  Future<void> dispose() async {
    _disposed = true;
    _foreground.removeListener(_onForegroundChanged);
    _flushTimer?.cancel();
    _reconnectTimer?.cancel();
    await _scanSub?.cancel();
    await _connSub?.cancel();
    await _valueSub?.cancel();
    await _adapterSub?.cancel();
    _scanningForeground = null;
    try {
      await (cfg.stopScan ?? FlutterBluePlus.stopScan)();
    } catch (_) {
      // The radio is going away with us either way.
    }
    // Leaving the band connected kept the radio link (and its battery cost)
    // alive for a manager nobody holds any more.
    try {
      await _band?.disconnect();
    } catch (_) {
      // Already gone, or the adapter went down with us. Nothing to salvage.
    }
    await _status.close();
    await _telemetry.close();
    await _emergency.close();
    await _beacon.close();
  }
}
