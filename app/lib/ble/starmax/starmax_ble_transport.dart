/// The concrete BLE transport for the Starmax / RunmeFit watch, over
/// flutter_blue_plus and the Nordic UART Service.
///
/// This file is Flutter- and radio-coupled (it imports flutter_blue_plus), so —
/// like ble_device_manager.dart — it is NOT part of the pure unit-test surface.
/// Everything it delegates to IS tested: the protocol (verify_starmax), the
/// client orchestration and the snapshot→telemetry bridge (fake-transport
/// tests). What is left here is only the parts a real device exercises: scan,
/// connect, discover, subscribe.
///
/// The manager mirrors BleDeviceManager's hard-won lifecycle — a single
/// connect at a time, capped-backoff reconnect, every subscription held so it
/// can be cancelled, and a link-state stream so "not measuring" is visible.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/triage.dart';
import '../link_policy.dart';
import 'starmax_client.dart';
import 'starmax_health_bridge.dart';
import 'starmax_protocol.dart';

// Nordic UART Service — the transport the watch speaks over.
final _nusService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
final _nusWrite = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
final _nusNotify = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

/// A [StarmaxTransport] backed by a connected device's NUS characteristics.
class FlutterBlueStarmaxTransport implements StarmaxTransport {
  final BluetoothCharacteristic _write;
  final _incoming = StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _valueSub;

  FlutterBlueStarmaxTransport._(this._write);

  /// Subscribe to notifications and wrap the pair of characteristics.
  static Future<FlutterBlueStarmaxTransport> attach(
      BluetoothCharacteristic write, BluetoothCharacteristic notify) async {
    final t = FlutterBlueStarmaxTransport._(write);
    await notify.setNotifyValue(true);
    t._valueSub = notify.onValueReceived.listen(t._incoming.add);
    return t;
  }

  @override
  Future<void> write(List<int> frame) async {
    // The frame is already <= one MTU for the commands the app sends; larger
    // writes (firmware) are not used here. writeWithoutResponse matches the
    // vendor's chunked-write path.
    await _write.write(frame, withoutResponse: _write.properties.writeWithoutResponse);
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  Future<void> dispose() async {
    await _valueSub?.cancel();
    await _incoming.close();
  }
}

/// Config for finding and holding the watch.
class StarmaxBandConfig {
  /// A previously-paired device id to reconnect to directly, when known.
  final String? knownRemoteId;

  /// Advertised-name substrings that identify a Starmax/RunmeFit watch, used
  /// when scanning fresh. The vendor's models advertise names like "GTS10".
  final List<String> namePrefixes;

  /// How often to pull a fresh health snapshot while connected.
  final Duration pollInterval;

  const StarmaxBandConfig({
    this.knownRemoteId,
    this.namePrefixes = const ['GTS', 'RunmeFit', 'Starmax'],
    this.pollInterval = const Duration(seconds: 30),
  });
}

/// Connects the watch and turns its snapshots into the app's telemetry +
/// triage, on the same streams BleDeviceManager exposes so main.dart wires
/// them identically.
class StarmaxBandManager {
  final StarmaxBandConfig cfg;

  final _telemetry = StreamController<(BandTelemetry, TriageResult)>.broadcast();
  final _emergency = StreamController<(BandTelemetry, TriageResult)>.broadcast();
  final _status = StreamController<BandLinkState>.broadcast();

  Stream<(BandTelemetry, TriageResult)> get onTelemetry => _telemetry.stream;
  Stream<(BandTelemetry, TriageResult)> get onEmergency => _emergency.stream;
  Stream<BandLinkState> get onStatus => _status.stream;

  BandLinkState _statusValue = BandLinkState.idle;
  BandLinkState get status => _statusValue;

  BluetoothDevice? _device;
  FlutterBlueStarmaxTransport? _transport;
  StarmaxClient? _client;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  int _reconnectAttempts = 0;
  bool _connecting = false;
  bool _disposed = false;

  StarmaxBandManager(this.cfg);

  void _setStatus(BandLinkState s) {
    if (_disposed || s == _statusValue) return;
    _statusValue = s;
    _status.add(s);
  }

  Future<void> start() async {
    if (_disposed) return;
    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      if (_disposed) return;
      if (s == BluetoothAdapterState.on) {
        _reconnectAttempts = 0;
        unawaited(_connect());
      } else {
        _setStatus(BandLinkState.waitingForBluetooth);
      }
    });
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) {
      await _connect();
    } else {
      _setStatus(BandLinkState.waitingForBluetooth);
    }
  }

  Future<void> _connect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _setStatus(BandLinkState.connecting);
    try {
      final device = cfg.knownRemoteId != null
          ? BluetoothDevice.fromId(cfg.knownRemoteId!)
          : await _scanForWatch();
      if (device == null) {
        _fail(LinkFailure.outOfRange);
        return;
      }
      _device = device;
      await device.connect(timeout: const Duration(seconds: 15));
      if (_disposed) {
        await device.disconnect();
        return;
      }
      _reconnectAttempts = 0;

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _fail(LinkFailure.outOfRange);
      });

      // Negotiate a larger MTU where supported (Android); iOS manages its own.
      try {
        await device.requestMtu(512);
      } catch (_) {/* not fatal */}

      final services = await device.discoverServices();
      final svc = services.where((s) => s.serviceUuid == _nusService).firstOrNull;
      final write = svc?.characteristics.where((c) => c.characteristicUuid == _nusWrite).firstOrNull;
      final notify = svc?.characteristics.where((c) => c.characteristicUuid == _nusNotify).firstOrNull;
      if (write == null || notify == null) {
        _fail(LinkFailure.wrongDevice); // not a Starmax NUS device
        return;
      }

      final transport = await FlutterBlueStarmaxTransport.attach(write, notify);
      final client = StarmaxClient(transport);
      _transport = transport;
      _client = client;

      await client.connect(); // pair + set clock
      _setStatus(BandLinkState.connected);
      _startPolling();
    } catch (e) {
      _fail(classifyLinkError(e));
    } finally {
      _connecting = false;
    }
  }

  /// Scan briefly for a device advertising the NUS service or a known name, and
  /// return the strongest match. Null if none appears in time.
  Future<BluetoothDevice?> _scanForWatch() async {
    final found = Completer<BluetoothDevice?>();
    ScanResult? best;
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_looksLikeWatch(r)) continue;
        if (best == null || r.rssi > best!.rssi) best = r;
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [_nusService],
        timeout: const Duration(seconds: 8),
      );
      // startScan completes when the timeout elapses.
      await FlutterBluePlus.isScanning.where((on) => on == false).first;
    } catch (e) {
      if (!found.isCompleted) found.complete(null);
      rethrow;
    } finally {
      await _scanSub?.cancel();
      _scanSub = null;
    }
    return best?.device;
  }

  bool _looksLikeWatch(ScanResult r) {
    final adv = r.advertisementData;
    if (adv.serviceUuids.contains(_nusService)) return true;
    final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
    if (cfg.namePrefixes.any((p) => name.toLowerCase().contains(p.toLowerCase()))) {
      return true;
    }
    // The vendor's raw-advertising marker: the bytes 0x00 0x01 in manufacturer
    // data. flutter_blue_plus surfaces it keyed by company id.
    for (final entry in adv.manufacturerData.entries) {
      final blob = [entry.key & 0xFF, (entry.key >> 8) & 0xFF, ...entry.value];
      for (var i = 0; i + 1 < blob.length; i++) {
        if (blob[i] == starmaxAdvMarker[0] && blob[i + 1] == starmaxAdvMarker[1]) return true;
      }
    }
    return false;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Poll immediately, then on the interval.
    unawaited(_pollOnce());
    _pollTimer = Timer.periodic(cfg.pollInterval, (_) => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    final client = _client;
    if (_disposed || client == null) return;
    try {
      final snap = await client.readHealth();
      if (!snapshotHasVitals(snap)) return; // idle / not worn — nothing to report
      final telemetry = bandTelemetryFromSnapshot(snap);
      final triage = assessTelemetry(telemetry);
      if (_disposed) return;
      _telemetry.add((telemetry, triage));
      if (triage.forceEmergencyScreen) _emergency.add((telemetry, triage));
    } catch (_) {
      // A missed poll is not a link failure on its own; the connectionState
      // listener handles real drops. Skip and try again next tick.
    }
  }

  void _fail(LinkFailure failure) {
    if (_disposed) return;
    _pollTimer?.cancel();
    _setStatus(failure.state);
    if (!failure.isWorthRetrying) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay(_reconnectAttempts), () {
      if (_disposed) return;
      unawaited(_connect());
    });
    _reconnectAttempts++;
  }

  Future<void> dispose() async {
    _disposed = true;
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    await _adapterSub?.cancel();
    await _connSub?.cancel();
    await _scanSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _client?.dispose();
    await _transport?.dispose();
    try {
      await _device?.disconnect();
    } catch (_) {}
    await _telemetry.close();
    await _emergency.close();
    await _status.close();
  }
}
