/// The backfill, from the controller to the wire and the screen.
///
/// The per-day history was declared "not a capability today" on the strength of
/// the app's own source: there were request builders and no reply parsers, so
/// the charts covered the minutes the app happened to be open. The vendor
/// documentation and a complete reference implementation had been in `docs/`
/// since October.
///
/// Decoding it is only half. A week of days that reaches `_wearableHistory` and
/// stops there is the same defect the live snapshot used to have — rendered on
/// one handset, sent nowhere, gone with the process. These tests hold the three
/// edges that make it real: the chart series, the sleep history and the
/// batcher. Each fails if its wiring is reverted.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/sample_store.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/domain/wearable_day.dart';
import 'package:fcs_app/net/telemetry_batcher.dart';

({TelemetryBatcher batcher, List<QueuedItem> sent}) _fakeBatcher() {
  final sent = <QueuedItem>[];
  final batcher = TelemetryBatcher(BatcherConfig(
    maxBatch: 1000,
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

WearableDay _day(int day, {int steps = 4000, int sleep = 0, int? hr = 68}) => WearableDay(
      date: DateTime(2026, 8, day),
      steps: steps,
      kcal: 160,
      meters: 2800,
      sleepMinutes: sleep,
      deepSleepMinutes: sleep ~/ 4,
      lightSleepMinutes: sleep ~/ 2,
      heartRateAvg: hr,
      heartRateMin: hr == null ? null : hr - 8,
      heartRateMax: hr == null ? null : hr + 40,
      spo2Avg: 97,
      spo2Min: 94,
      systolicAvg: 116,
      diastolicAvg: 74,
      tempAvgTenths: 366,
      stress: 34,
      breathRate: 15,
      met: 3,
    );

WearableHistoryReport _report(List<WearableDay> days, {int requested = 7}) =>
    WearableHistoryReport(
      days: days,
      samples: [
        for (final d in days)
          for (var h = 6; h < 22; h++)
            HealthSample(
              at: DateTime(d.date.year, d.date.month, d.date.day, h, 30),
              heartRate: 68 + (h % 7).toDouble(),
              spo2: 97,
            ),
      ],
      requestedDays: requested,
    );

Future<AppController> _paired() async {
  final c = AppController();
  await c.addDevice(
      const PairedDevice(id: 'BAND-42', name: 'GTS10', kind: DeviceKind.band));
  return c;
}

void main() {
  test('a backfilled week is queued for the backend, one item per day', () async {
    final c = await _paired();
    final fake = _fakeBatcher();
    c.attachRuntime(batcher: fake.batcher);

    c.onWearableHistory(_report([for (var d = 6; d <= 12; d++) _day(d)]));

    final items = fake.sent.where((i) => i.type == 'wearable').toList();
    expect(items, hasLength(7));
    expect(
      items.map((i) => i.payload['day']).toSet(),
      {for (var d = 6; d <= 12; d++) '2026-08-${d.toString().padLeft(2, '0')}'},
    );
    // Each day names the paired watch, or the server cannot attribute it.
    expect(items.every((i) => i.payload['deviceId'] == 'BAND-42'), isTrue);
  });

  test('the vitals a day carries are on the wire, not dropped at the last step', () async {
    final c = await _paired();
    final fake = _fakeBatcher();
    c.attachRuntime(batcher: fake.batcher);

    c.onWearableHistory(_report([_day(10)]));
    final p = fake.sent.singleWhere((i) => i.type == 'wearable').payload;

    // Everything the parsers went and got. A field the watch reports, the app
    // decodes and no payload carries is the same defect wearing a new hat.
    expect(p['heartRateAvg'], 68);
    expect(p['heartRateMin'], 60);
    expect(p['heartRateMax'], 108);
    expect(p['spo2Avg'], 97);
    expect(p['spo2Min'], 94);
    expect(p['systolicAvg'], 116);
    expect(p['diastolicAvg'], 74);
    expect(p['tempAvgTenths'], 366);
    expect(p['stress'], 34);
    expect(p['breathRate'], 15);
    expect(p['met'], 3);
    expect(p['steps'], 4000);
  });

  test('a metric the watch never measured is absent, never a zero', () async {
    final c = await _paired();
    final fake = _fakeBatcher();
    c.attachRuntime(batcher: fake.batcher);

    c.onWearableHistory(_report([_day(10, hr: null)]));
    final p = fake.sent.singleWhere((i) => i.type == 'wearable').payload;
    expect(p.containsKey('heartRateAvg'), isFalse);
    expect(p.containsKey('heartRateMin'), isFalse);
    // A stored 0 reads back as a heart that stopped.
    expect(p.containsKey('bloodSugarTenths'), isFalse);
  });

  test('nothing is queued without a paired band', () {
    final c = AppController();
    final fake = _fakeBatcher();
    c.attachRuntime(batcher: fake.batcher);
    c.onWearableHistory(_report([_day(10)]));
    expect(fake.sent.where((i) => i.type == 'wearable'), isEmpty);
  });

  test('backfilled samples reach the chart series, in time order', () async {
    final c = await _paired();
    // A live reading arrives first — as it would, the poll being faster than a
    // week of history.
    c.store.addSample(HealthSample(at: DateTime(2026, 8, 12, 12), heartRate: 80));
    c.onWearableHistory(_report([_day(10), _day(11)]));

    expect(c.store.length, greaterThan(30));
    final times = c.store.all.map((s) => s.at).toList();
    // Out-of-order insertion is what makes the sparkline draw the week backwards
    // and makes a value from four days ago the "current" reading.
    for (var i = 1; i < times.length; i++) {
      expect(times[i].isBefore(times[i - 1]), isFalse, reason: 'sample $i is out of order');
    }
    expect(c.store.latest!.at, DateTime(2026, 8, 12, 12));
    // The days really are in there — the charts now reach back past today.
    expect(c.store.all.any((s) => s.at.day == 10), isTrue);
  });

  test('a backfilled night appears in the sleep history', () async {
    final c = await _paired();
    expect(c.sleepNights, isEmpty);
    c.onWearableHistory(_report([_day(10, sleep: 480), _day(11, sleep: 420)]));

    expect(c.sleepNights.length, 2);
    final tenth = c.sleepNights.firstWhere((n) => n.night.day == 10);
    expect(tenth.deepMin, 120);
    expect(tenth.lightMin, 240);
    // Whatever the watch did not split is carried as REM, so the parts add up
    // to the total it reported.
    expect(tenth.deepMin + tenth.lightMin + tenth.remMin, 480);
  });

  test('a night she typed in herself is not overwritten by the backfill', () async {
    final c = await _paired();
    c.addSleepSummary(SleepSummary(
        night: DateTime(2026, 8, 10),
        deepMin: 90,
        remMin: 60,
        lightMin: 200,
        source: SleepSource.manual));
    c.onWearableHistory(_report([_day(10, sleep: 480)]));

    final night = c.sleepNights.firstWhere((n) => n.night.day == 10);
    expect(night.source, SleepSource.manual);
    expect(night.deepMin, 90);
  });

  test('the report is exposed so a label can state the span it really has', () async {
    final c = await _paired();
    expect(c.wearableHistory, isNull);

    // Asked for seven; the watch had two. A chart that says «7 дней» on the
    // strength of the request is a claim about days nobody measured.
    c.onWearableHistory(_report([_day(11), _day(12)], requested: 7));
    expect(c.wearableHistory!.requestedDays, 7);
    expect(c.wearableHistory!.coveredDays, 2);
  });

  test('an empty day does not inflate the span', () async {
    final c = await _paired();
    // A day the watch listed and had nothing in.
    c.onWearableHistory(_report([_day(11), WearableDay(date: DateTime(2026, 8, 9))]));
    expect(c.wearableHistory!.coveredDays, 1);
  });

  test('the history stream is actually listened to', () {
    // The dominant defect in this repository is a finished feature with no
    // caller. This one costs a BLE conversation per connection and would look
    // exactly like a watch that keeps no history.
    final main_ = File('lib/main.dart').readAsStringSync();
    expect(main_.contains('onHistory.listen(controller.onWearableHistory)'), isTrue);
    // …and the manager must actually run the sync, or the stream never fires.
    final mgr = File('lib/ble/starmax/starmax_ble_transport.dart').readAsStringSync();
    expect(mgr.contains('_backfillHistory('), isTrue);
    expect(mgr.contains('syncStarmaxHistory('), isTrue);
  });

  test('the covered span reaches the dashboard', () {
    // The number on screen has to be the count of days that came back. Reading
    // it off the controller's report is what keeps it honest; a constant, or
    // the requested window, would not be.
    final shell = File('lib/ui/home_shell.dart').readAsStringSync();
    expect(shell.contains('watchHistoryDays: c.wearableHistory?.coveredDays'), isTrue);
  });

  test('SampleStore.addSamples merges old data without disordering the buffer', () {
    final s = SampleStore(capacity: 100);
    s.addSample(HealthSample(at: DateTime(2026, 8, 12, 12), heartRate: 80));
    s.addSamples([
      HealthSample(at: DateTime(2026, 8, 10, 9), heartRate: 62),
      HealthSample(at: DateTime(2026, 8, 11, 9), heartRate: 64),
    ]);
    expect(s.all.map((x) => x.at.day).toList(), [10, 11, 12]);
    expect(s.latest!.heartRate, 80);
    // An empty batch is a no-op, not a sort.
    s.addSamples(const []);
    expect(s.length, 3);
  });

  test('a backfill bigger than the buffer drops the oldest days, not the newest', () {
    final s = SampleStore(capacity: 3);
    s.addSamples([
      for (var d = 1; d <= 6; d++) HealthSample(at: DateTime(2026, 8, d), heartRate: 70)
    ]);
    expect(s.all.map((x) => x.at.day).toList(), [4, 5, 6]);
  });
}

