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

import '../core/triage.dart';
import 'parsers/band_parser.dart';
import 'parsers/beacon_parser.dart';
import 'calibration.dart';

// OEM band's proprietary NOTIFY channel (⚠ confirm per firmware).
final _bandService = Guid('0000fee0-0000-1000-8000-00805f9b34fb');
final _bandNotify = Guid('0000fee1-0000-1000-8000-00805f9b34fb');

class BleManagerConfig {
  final String bandRemoteId;
  final String childBeaconUuid;
  final BpCalibration? Function() getBpCalibration;
  const BleManagerConfig({
    required this.bandRemoteId,
    required this.childBeaconUuid,
    required this.getBpCalibration,
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

  BleDeviceManager(this.cfg);

  Future<void> start() async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on);
    }
    await _connectBand();
    _startBeaconScan(foreground: false);
  }

  // ---- Smart band: connect + notify, with capped-backoff reconnect ----
  Future<void> _connectBand() async {
    final device = BluetoothDevice.fromId(cfg.bandRemoteId);
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _reconnectAttempts = 0;
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _handleBandDisconnect();
      });

      final services = await device.discoverServices();
      final svc = services.firstWhere((s) => s.serviceUuid == _bandService);
      final chr = svc.characteristics.firstWhere((c) => c.characteristicUuid == _bandNotify);
      await chr.setNotifyValue(true);
      chr.onValueReceived.listen((value) => _onBandFrame(Uint8List.fromList(value)));
    } catch (_) {
      _handleBandDisconnect();
    }
  }

  void _handleBandDisconnect() {
    final delayMs =
        (1000 * (1 << _reconnectAttempts)).clamp(1000, 30000); // cap 30s
    _reconnectAttempts++;
    Timer(Duration(milliseconds: delayMs), _connectBand);
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
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
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
    FlutterBluePlus.startScan(
      continuousUpdates: true,
      androidScanMode:
          foreground ? AndroidScanMode.lowLatency : AndroidScanMode.lowPower,
    );
  }

  /// Code Optimizer hook: called by AdaptiveScanController.apply.
  Future<void> setScanMode({required bool foreground}) async {
    await FlutterBluePlus.stopScan();
    _startBeaconScan(foreground: foreground);
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();
    await _telemetry.close();
    await _emergency.close();
    await _beacon.close();
  }
}
