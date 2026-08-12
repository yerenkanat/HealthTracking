/// The smartwatch, from the radio to the wire.
///
/// Three defects lived on this path, and each of them presented as "the watch
/// just does not do anything":
///
///   1. the BLE stack was behind `bool.fromEnvironment('STARMAX_WATCH')`, a
///      compile-time gate no build script in the repository ever set, so every
///      shipped APK carried the whole thing as dead code;
///   2. readings were stamped with a compile-time device id defaulting to the
///      string 'band-unpaired', which `/ingest` cannot attribute to anyone — so
///      the server counted them `rejected` and answered 200;
///   3. everything the watch measures beyond the four triage vitals (steps,
///      distance, calories, stress, breathing rate, MET, battery, wear state)
///      reached one in-memory field and was never sent anywhere at all.
///
/// Each test below fails if its fix is reverted.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/ble/band_scan.dart';
import 'package:fcs_app/ble/starmax/starmax_frames.dart';
import 'package:fcs_app/ble/starmax/starmax_health_bridge.dart';
import 'package:fcs_app/ble/watch_identity.dart';
import 'package:fcs_app/core/triage.dart';
import 'package:fcs_app/data/api_client.dart' show IngestSummary;
import 'package:fcs_app/data/sync_push.dart';
import 'package:fcs_app/domain/emergency_confirmation.dart' show ReadingSource;
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/health_monitor.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';
import 'package:fcs_app/net/telemetry_batcher.dart';
import 'package:fcs_app/ui/onboarding/onboarding_flow.dart' show DiscoveredBand;

StarmaxHealthSnapshot _snap({
  int hr = 0,
  int spo2 = 0,
  int sugar = 0,
  int stress = 0,
  int met = 0,
  int steps = 0,
}) =>
    StarmaxHealthSnapshot(
      totalSteps: steps,
      totalKcal: 0,
      totalMeters: 0,
      totalSleepMin: 0,
      deepSleepMin: 0,
      lightSleepMin: 0,
      heartRate: hr,
      bloodOxygen: spo2,
      bpSystolic: 0,
      bpDiastolic: 0,
      tempRaw: 0,
      bloodSugar: sugar,
      isWorn: true,
      breathRate: 0,
      stress: stress,
      met: met,
    );

/// A batcher that records what it was asked to send.
({TelemetryBatcher batcher, List<QueuedItem> sent}) _fakeBatcher() {
  final sent = <QueuedItem>[];
  final batcher = TelemetryBatcher(BatcherConfig(
    maxBatch: 1000, // never auto-flush: we inspect the queue, not the network
    maxDelay: const Duration(days: 1),
    flush: (items) async => sent.addAll(items),
    persist: (items) async {
      sent
        ..clear()
        ..addAll(items);
    },
    restore: () async => [],
  ));
  return (batcher: batcher, sent: sent);
}

void main() {
  group('the paired band is a runtime fact, not a build flag', () {
    test('a paired band gives the app an identity to send readings under', () async {
      final c = AppController();
      expect(c.hasPairedBand, isFalse);
      expect(c.pairedBandId, isNull);

      await c.addDevice(const PairedDevice(
          id: 'AA:BB:CC:DD:EE:FF', name: 'GTS10', kind: DeviceKind.band));
      expect(c.hasPairedBand, isTrue);
      expect(c.pairedBandId, 'AA:BB:CC:DD:EE:FF');
    });

    test("a tracker tag is not a band — it must not start the watch link", () async {
      final c = AppController();
      await c.addDevice(const PairedDevice(
          id: 'TAG-1', name: 'Tag', kind: DeviceKind.tag, childId: 'child-1'));
      expect(c.hasPairedBand, isFalse,
          reason: 'a child tracker cannot report a heart rate');
    });

    test('main starts the watch on the paired band and no longer on a define', () {
      final source = File('lib/main.dart').readAsStringSync();
      // The gate that hid the entire BLE stack in every shipped build. It must
      // not come back: a constant nobody sets reads as "supported" in the code
      // and is "absent" in the product.
      expect(source.contains('STARMAX_WATCH'), isFalse,
          reason: 'the compile-time watch gate is gone');
      expect(source.contains('controller.hasPairedBand'), isTrue,
          reason: 'the watch starts on a runtime condition');
      // And it must stay conditional: starting it unconditionally makes every
      // user without a watch pay for a BLE scan on every launch.
      expect(source.contains('startWatchIfPaired'), isTrue);
    });

    test('readings are stamped with the paired band, not a placeholder', () {
      final c = AppController();
      final wire = <Map<String, dynamic>>[];
      final monitor = HealthMonitor(
        deviceId: 'band-unpaired', // the old default, still the last resort
        resolveDeviceId: () => c.pairedBandId ?? '',
        enqueue: (t, {required urgent}) => wire.add(t),
        onEmergency: (_, __) {},
      );

      const t = BandTelemetry(heartRateBpm: 88, spo2Pct: 97);
      monitor.handle(t, assessTelemetry(t));
      expect(wire.single['deviceId'], 'band-unpaired',
          reason: 'nothing paired yet — the fallback is all there is');

      c.addDevice(const PairedDevice(id: 'BAND-42', name: 'GTS10', kind: DeviceKind.band));
      monitor.handle(t, assessTelemetry(t));
      // Resolved at SEND time: the monitor is built at launch and pairing
      // happens later, so an id captured in the constructor would be the
      // unpaired placeholder for the rest of the run — and the server rejects
      // every reading that names a device it cannot attribute.
      expect(wire.last['deviceId'], 'BAND-42');
    });
  });

  group('what the watch parses reaches the wire', () {
    test('blood sugar rides on the telemetry the server actually stores', () {
      final t = bandTelemetryFromSnapshot(_snap(hr: 72, sugar: 82));
      expect(t.glucoseMmol, closeTo(8.2, 1e-9));
      expect(t.toJson()['glucoseMmol'], closeTo(8.2, 1e-9),
          reason: 'toJson is what /ingest receives');
    });

    test('a glucose-only snapshot is still worth sending', () {
      // Nothing else measured. This used to be dropped before it could reach
      // any storage at all, because "has vitals" meant HR/SpO2/temperature.
      expect(snapshotHasVitals(_snap(sugar: 61)), isTrue);
      expect(snapshotHasVitals(_snap()), isFalse);
    });

    test('an unmeasured sugar stays absent rather than becoming zero', () {
      expect(bandTelemetryFromSnapshot(_snap(hr: 72)).glucoseMmol, isNull);
    });

    test('the MET estimate survives the bridge', () {
      final m = wearableMetricsFromSnapshot(_snap(met: 4), DateTime(2026, 8, 12));
      expect(m.met, 4);
      expect(wearableMetricsFromSnapshot(_snap(), DateTime(2026, 8, 12)).met, isNull,
          reason: '0 means the watch did not measure it');
    });

    test('one measurement makes one sample, whichever path carries it', () {
      final at = DateTime(2026, 8, 12, 9);
      final c = AppController(now: () => at);
      // A single poll of the watch emits BOTH an activity snapshot and a
      // telemetry record, and the glucose estimate now rides on both.
      c.onWearableMetrics(WearableMetrics(at: at, steps: 900, bloodSugarTenths: 82));
      const t = BandTelemetry(heartRateBpm: 72, glucoseMmol: 8.2);
      c.onTelemetry(t, assessTelemetry(t));
      expect(buildSeries(c.samples, 'glucose').length, 1,
          reason: 'two carriers, one reading');
    });

    test('a hand-typed glucose is always recorded', () {
      final at = DateTime(2026, 8, 12, 9);
      final c = AppController(now: () => at);
      c.onWearableMetrics(WearableMetrics(at: at, steps: 900, bloodSugarTenths: 82));
      const typed = BandTelemetry(glucoseMmol: 8.2);
      c.onTelemetry(typed, assessTelemetry(typed), source: ReadingSource.manual);
      expect(buildSeries(c.samples, 'glucose').length, 2,
          reason: 'she typed this one in herself; it is not the watch repeating');
    });
  });

  group('the activity half of the watch reaches the backend', () {
    test('a snapshot is queued for /ingest with every indicator on it', () async {
      final c = AppController();
      final fake = _fakeBatcher();
      c.attachRuntime(batcher: fake.batcher);
      await c.addDevice(const PairedDevice(id: 'BAND-42', name: 'GTS10', kind: DeviceKind.band));

      c.onWearableMetrics(WearableMetrics(
        at: DateTime(2026, 8, 12, 21, 30),
        steps: 6480,
        kcal: 320,
        meters: 4600,
        sleepMinutes: 445,
        deepSleepMinutes: 95,
        lightSleepMinutes: 280,
        stress: 42,
        breathRate: 16,
        met: 3,
        batteryPercent: 78,
        worn: true,
      ));

      final item = fake.sent.singleWhere((i) => i.type == 'wearable');
      expect(item.payload, containsPair('deviceId', 'BAND-42'));
      expect(item.payload, containsPair('steps', 6480));
      expect(item.payload, containsPair('kcal', 320));
      expect(item.payload, containsPair('meters', 4600));
      expect(item.payload, containsPair('stress', 42));
      expect(item.payload, containsPair('breathRate', 16));
      expect(item.payload, containsPair('met', 3));
      expect(item.payload, containsPair('batteryPercent', 78));
      expect(item.payload, containsPair('worn', true));
      // The wearer's local day, not the UTC one: her watch rolls its totals
      // over at her midnight, and 21:30 in Almaty is already tomorrow in UTC.
      expect(item.payload, containsPair('day', '2026-08-12'));
    });

    test('an unmeasured value is left out, never sent as a zero', () async {
      final c = AppController();
      final fake = _fakeBatcher();
      c.attachRuntime(batcher: fake.batcher);
      await c.addDevice(const PairedDevice(id: 'BAND-42', name: 'GTS10', kind: DeviceKind.band));

      c.onWearableMetrics(WearableMetrics(at: DateTime(2026, 8, 12), steps: 100));
      final item = fake.sent.singleWhere((i) => i.type == 'wearable');
      expect(item.payload.containsKey('stress'), isFalse);
      expect(item.payload.containsKey('breathRate'), isFalse);
      expect(item.payload.containsKey('batteryPercent'), isFalse);
    });

    test('an unchanged snapshot does not cost a write every poll', () async {
      final c = AppController();
      final fake = _fakeBatcher();
      c.attachRuntime(batcher: fake.batcher);
      await c.addDevice(const PairedDevice(id: 'BAND-42', name: 'GTS10', kind: DeviceKind.band));

      final base = DateTime(2026, 8, 12, 10);
      for (var i = 0; i < 5; i++) {
        c.onWearableMetrics(
            WearableMetrics(at: base.add(Duration(seconds: 30 * i)), steps: 100, worn: true));
      }
      expect(fake.sent.where((i) => i.type == 'wearable'), hasLength(1));

      c.onWearableMetrics(WearableMetrics(at: base, steps: 140, worn: true));
      expect(fake.sent.where((i) => i.type == 'wearable'), hasLength(2),
          reason: 'a figure that changed is news');
    });

    test('nothing is queued when no band is paired', () async {
      final c = AppController();
      final fake = _fakeBatcher();
      c.attachRuntime(batcher: fake.batcher);
      c.onWearableMetrics(WearableMetrics(at: DateTime(2026, 8, 12), steps: 6480));
      expect(fake.sent.where((i) => i.type == 'wearable'), isEmpty,
          reason: 'the server could not attribute it to any device');
    });
  });

  group('the pairing step can actually find a watch', () {
    test('the app passes a real scanner into onboarding', () {
      // `_PairBandPage` renders its skip line whenever `scanBands` is null, so
      // without this the step asks her to choose her bracelet from a list that
      // cannot exist — which is what onboarding did on a real handset: a title,
      // an instruction, and an empty area below it.
      final source = File('lib/app/app.dart').readAsStringSync();
      expect(source.contains('scanBands: scanForBands'), isTrue);
    });

    test('the first thing a listener gets is an empty list, not an error', () async {
      // The pairing page renders `snap.data ?? const []` and shows its scanning
      // line while that is empty, so the stream must OPEN with a frame the page
      // can draw and must never deliver an error — a phone with Bluetooth off,
      // a declined permission and a test binding with no platform channel all
      // have to land on the same honest "nothing found yet".
      //
      // Only the first emission is asserted: everything past it needs a radio,
      // and the scan itself is verified on the device suite.
      final first = await scanForBands(timeout: const Duration(milliseconds: 10))
          .first
          .timeout(const Duration(seconds: 2));
      expect(first, isA<List<DiscoveredBand>>());
      expect(first, isEmpty);
    });
  });

  group('a refused batch is not a delivered one', () {
    test('a 200 that stored nothing is reported', () {
      const summary = IngestSummary(0, 0, 0, 3);
      expect(summary.storedNothing, isTrue);
      final report = ingestRejectionReport(summary);
      expect(report, isNotNull);
      expect(report, contains('3'));
    });

    test('a clean batch says nothing', () {
      expect(ingestRejectionReport(const IngestSummary(4, 0, 0, 0)), isNull);
    });
  });

  group('which advertisement is our watch', () {
    test('the Nordic UART service is enough', () {
      expect(
        looksLikeStarmaxWatch(
            name: '', serviceUuids: const ['6e400001-b5a3-f393-e0a9-e50e24dcca9e']),
        isTrue,
      );
    });

    test('a model name is enough', () {
      expect(looksLikeStarmaxWatch(name: 'GTS10'), isTrue);
      expect(looksLikeStarmaxWatch(name: 'Mi Band 7'), isFalse);
    });

    test("the vendor's advertising marker is enough", () {
      expect(
        looksLikeStarmaxWatch(name: 'unknown', manufacturerData: const {
          0x0000: [0x01, 0x02, 0x03]
        }),
        isTrue,
      );
    });

    test('a serial from the box is not something the radio can dial', () {
      expect(looksLikeBleRemoteId('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(looksLikeBleRemoteId('7F1C0E52-9A4B-4A2C-9E6F-2B7C1D3E4F50'), isTrue);
      expect(looksLikeBleRemoteId('UMAY-W-000431'), isFalse,
          reason: 'a claimed serial must send the manager scanning instead');
    });
  });
}
