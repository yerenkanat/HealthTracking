/// The Starmax client, over a fake transport.
///
/// No BLE and no hardware: a fake transport captures the frames the client
/// writes and lets the test push replies back, so the request/reply matching,
/// error handling, and live-measurement fan-out are all exercised here.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ble/starmax/starmax_client.dart';
import 'package:fcs_app/ble/starmax/starmax_frames.dart';
import 'package:fcs_app/ble/starmax/starmax_protocol.dart';
import 'package:fcs_app/ble/starmax/starmax_health_bridge.dart';

StarmaxHealthSnapshot snap({int hr = 0, int spo2 = 0, int tempTenths = 0, int sys = 0, int dia = 0}) =>
    StarmaxHealthSnapshot(
      totalSteps: 0, totalKcal: 0, totalMeters: 0, totalSleepMin: 0,
      deepSleepMin: 0, lightSleepMin: 0, heartRate: hr, bloodOxygen: spo2,
      stress: 0, met: 0, bpDiastolic: dia, bpSystolic: sys,
      tempRaw: tempTenths, bloodSugar: 0, isWorn: true, breathRate: 0,
    );

class FakeTransport implements StarmaxTransport {
  final _in = StreamController<List<int>>.broadcast();
  final List<List<int>> writes = [];

  @override
  Future<void> write(List<int> frame) async => writes.add(frame);

  @override
  Stream<List<int>> get incoming => _in.stream;

  void push(List<int> frame) => _in.add(frame);
  Future<void> close() => _in.close();
}

/// A frame-141 reply carrying a heart rate and SpO₂, with the leading status
/// byte the device sends.
Uint8List healthReply({int hr = 72, int spo2 = 98, int tempTenths = 365}) {
  final fields = List<int>.filled(30, 0);
  fields[18] = hr;
  fields[21] = spo2;
  fields[25] = tempTenths & 0xFF;
  fields[26] = (tempTenths >> 8) & 0xFF;
  fields[28] = 1; // worn
  return buildFrame(StarmaxReply.healthDetail, [0, ...fields]);
}

void main() {
  test('readHealth writes get-health-detail and parses the reply', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t);
    addTearDown(c.dispose);

    final future = c.readHealth();
    t.push(healthReply(hr: 80, spo2: 97));
    final snap = await future;

    expect(snap.heartRate, 80);
    expect(snap.bloodOxygen, 97);
    expect(snap.tempCelsius, 36.5);
    // It asked with the health-detail command.
    expect(t.writes.single[1], StarmaxCmd.healthDetail);
  });

  test('a reply for a different command does not complete the wrong request', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t, timeout: const Duration(milliseconds: 200));
    addTearDown(c.dispose);

    final future = c.readHealth();
    // Push a battery reply — wrong command; the health request must keep waiting
    // and then time out.
    t.push(buildFrame(StarmaxReply.power, [0, 90]));
    await expectLater(future, throwsA(isA<StarmaxError>()));
  });

  test('a missing reply times out', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t, timeout: const Duration(milliseconds: 150));
    addTearDown(c.dispose);
    await expectLater(c.readPower(), throwsA(isA<StarmaxError>()));
  });

  test('a checksum-failed reply is an error, never data', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t, timeout: const Duration(milliseconds: 300));
    addTearDown(c.dispose);

    final future = c.readHealth();
    final corrupt = [...healthReply()];
    corrupt[corrupt.length - 1] ^= 0xFF; // break the CRC
    t.push(corrupt);
    await expectLater(future, throwsA(isA<StarmaxError>()));
  });

  test('a non-zero device status is an error', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t, timeout: const Duration(milliseconds: 300));
    addTearDown(c.dispose);

    final future = c.readPower();
    // status byte (index 4) = 2 → "校验码错误" on the device side.
    t.push(buildFrame(StarmaxReply.power, [2, 90]));
    await expectLater(future, throwsA(isA<StarmaxError>()));
  });

  test('pair returns the device pair status', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t);
    addTearDown(c.dispose);
    final future = c.pair();
    t.push(buildFrame(StarmaxReply.pair, [0, 1])); // status ok, pairStatus 1
    expect(await future, 1);
  });

  test('a live measurement fans readings out to the stream', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t);
    addTearDown(c.dispose);

    final readings = <int>[];
    c.liveReadings.listen((r) => readings.add(r.result.value));

    final started = c.startMeasure(StarmaxMeasure.heartRate);
    t.push(buildFrame(StarmaxReply.healthMeasure, [0, 99, 68])); // first reading
    final first = await started;
    expect(first.value, 68);

    // Subsequent unsolicited readings still arrive on the stream.
    t.push(buildFrame(StarmaxReply.healthMeasure, [0, 99, 71]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(readings, containsAll(<int>[68, 71]));
  });

  test('the health bridge maps a real reading into telemetry', () {
    final t = bandTelemetryFromSnapshot(snap(hr: 78, spo2: 96, tempTenths: 368, sys: 118, dia: 76));
    expect(t.heartRateBpm, 78);
    expect(t.spo2Pct, 96);
    expect(t.coreTempC, 36.8);
    expect(t.systolicMmHg, 118);
    expect(t.diastolicMmHg, 76);
  });

  test('the bridge turns unmeasured zeros into null, not a false zero reading', () {
    // A watch that has not measured recently reports 0 for every current field.
    // Pushed into triage a 0 heart rate would read as a lethal bradycardia — the
    // bridge must yield null instead.
    final t = bandTelemetryFromSnapshot(snap());
    expect(t.heartRateBpm, isNull);
    expect(t.spo2Pct, isNull);
    expect(t.coreTempC, isNull);
    expect(t.systolicMmHg, isNull);
    expect(snapshotHasVitals(snap()), isFalse); // nothing worth emitting
    expect(snapshotHasVitals(snap(hr: 70)), isTrue);
  });

  test('connect pairs then sets the clock', () async {
    final t = FakeTransport();
    final c = StarmaxClient(t);
    addTearDown(c.dispose);

    final done = c.connect(now: DateTime(2026, 7, 22, 9, 30));
    // Reply to pair, then to set-time (empty-payload ack).
    t.push(buildFrame(StarmaxReply.pair, [0, 1]));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    t.push(buildFrame(StarmaxCmd.time + starmaxReplyBit, [0]));
    await done;

    expect(t.writes[0][1], StarmaxCmd.pair);
    expect(t.writes[1][1], StarmaxCmd.time);
  });
}
