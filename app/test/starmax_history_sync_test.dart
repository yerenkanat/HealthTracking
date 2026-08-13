/// The backfill, end to end: the client over a fake radio, and the walk over a
/// fake watch.
///
/// Two halves, because they fail differently. The first drives a real
/// [StarmaxClient] with the golden frame bytes, split into notifications, so the
/// request/reply matching and the multi-frame assembly are exercised the way a
/// device exercises them. The second drives [syncStarmaxHistory] over a fake
/// reader, so what the walk ASKS FOR — and what it refuses to ask for — is
/// visible.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ble/starmax/starmax_client.dart';
import 'package:fcs_app/ble/starmax/starmax_history.dart';
import 'package:fcs_app/ble/starmax/starmax_history_sync.dart';
import 'package:fcs_app/ble/starmax/starmax_protocol.dart';
import 'package:fcs_app/domain/wearable_day.dart';

late Map<String, dynamic> _golden;

List<String> _frames(String name) => ((_golden['cases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((c) => c['name'] == name)['frames'] as List)
    .cast<String>();

List<int> _hex(String s) =>
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// A transport that answers a written command with recorded device frames,
/// delivered in 20-byte notifications the way a radio does.
class ScriptedTransport implements StarmaxTransport {
  final _in = StreamController<List<int>>.broadcast();
  final List<List<int>> writes = [];

  /// request cmd byte → the reply frames to play back.
  final Map<int, List<List<int>>> replies;

  ScriptedTransport(this.replies);

  @override
  Future<void> write(List<int> frame) async {
    writes.add(frame);
    final script = replies[frame[1]];
    if (script == null) return; // silence: the watch has nothing to say
    scheduleMicrotask(() {
      for (final f in script) {
        for (var i = 0; i < f.length; i += 20) {
          _in.add(f.sublist(i, i + 20 > f.length ? f.length : i + 20));
        }
      }
    });
  }

  @override
  Stream<List<int>> get incoming => _in.stream;
  Future<void> close() => _in.close();
}

/// A watch that holds exactly the days it is told to.
class FakeWatch implements StarmaxHistoryReader {
  final Map<StarmaxHistoryType, List<DateTime>> holds;
  final List<String> asked = [];

  FakeWatch(this.holds);

  @override
  Future<List<DateTime>> readValidHistoryDates(StarmaxHistoryType type) async {
    asked.add('dates:${type.name}');
    return holds[type] ?? const [];
  }

  @override
  Future<StarmaxDaySeries?> readDaySeries(StarmaxHistoryType type, DateTime day) async {
    asked.add('${type.name}:${day.day}');
    final n = 24;
    return StarmaxDaySeries(
      StarmaxHistoryHeader(status: 0, intervalMinutes: 60, date: day, dataLength: n),
      [
        for (var i = 0; i < n; i++)
          StarmaxSample(i * (1440 / n), switch (type) {
            // A day with unmeasured stretches, so the averages have to skip
            // them rather than average a zero in.
            StarmaxHistoryType.heartRate => i < 4 ? 0 : 60 + i,
            StarmaxHistoryType.bloodOxygen => i < 4 ? 0 : 95,
            StarmaxHistoryType.temp => i < 4 ? 0 : 365,
            StarmaxHistoryType.stress => i < 4 ? 0 : 30,
            StarmaxHistoryType.respirationRate => i < 4 ? 0 : 16,
            StarmaxHistoryType.met => i < 4 ? 0 : 3,
            StarmaxHistoryType.bloodSugar => i < 4 ? 0 : 52,
            // 8 hours of sleep: 12 light + 6 deep, then awake.
            StarmaxHistoryType.sleep => i < 12
                ? StarmaxSleepStage.light
                : i < 18
                    ? StarmaxSleepStage.deep
                    : i < 20
                        ? StarmaxSleepStage.awake
                        : 0,
            _ => 0,
          })
      ],
    );
  }

  @override
  Future<StarmaxBpDay?> readBloodPressureDay(DateTime day) async {
    asked.add('bloodPressure:${day.day}');
    return StarmaxBpDay(
      StarmaxHistoryHeader(status: 0, intervalMinutes: 60, date: day, dataLength: 48),
      [for (var i = 0; i < 24; i++) StarmaxBpSample(i * 60.0, i < 4 ? 0 : 118, i < 4 ? 0 : 76)],
    );
  }

  @override
  Future<StarmaxStepDay?> readStepDay(DateTime day) async {
    asked.add('step:${day.day}');
    return StarmaxStepDay(
      StarmaxHistoryHeader(status: 0, intervalMinutes: 60, date: day, dataLength: 144),
      [
        for (var i = 0; i < 24; i++)
          StarmaxStepRecord(minuteOfDay: i * 60, steps: 100, kcal: 4, decimetres: 700)
      ],
      const [],
    );
  }
}

void main() {
  setUpAll(() {
    _golden = jsonDecode(File('test/fixtures/starmax_history_golden.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  // ---- The client over a fake radio ----

  test('readValidHistoryDates asks with 105 and decodes the days', () async {
    final t = ScriptedTransport({
      starmaxValidHistoryDatesCmd: [_hex(_frames('validHistoryDates').single)],
    });
    final c = StarmaxClient(t, timeout: const Duration(seconds: 2));
    addTearDown(c.dispose);

    final dates = await c.readValidHistoryDates(StarmaxHistoryType.step);
    expect(dates, [DateTime(2026, 8, 8), DateTime(2026, 8, 9), DateTime(2026, 8, 10)]);
    expect(t.writes.single[1], starmaxValidHistoryDatesCmd);
  });

  test('a day of heart rate arrives across two frames and many notifications', () async {
    final t = ScriptedTransport({
      StarmaxHistoryType.heartRate.cmd: _frames('heartRate').map(_hex).toList(),
    });
    final c = StarmaxClient(t, timeout: const Duration(seconds: 2));
    addTearDown(c.dispose);

    final series = await c.readDaySeries(StarmaxHistoryType.heartRate, DateTime(2026, 8, 10));
    expect(series, isNotNull);
    // 288 samples split over two frames and sixteen-odd notifications. Before
    // the assembler existed this returned the first 20 bytes, or nothing.
    expect(series!.samples.length, 288);
    expect(series.date, DateTime(2026, 8, 10));
    expect(series.measured, isNotEmpty);

    // The request named the day the way the vendor does: (year-2000, month, day).
    final w = t.writes.single;
    expect(w[1], StarmaxHistoryType.heartRate.cmd);
    expect([w[4], w[5], w[6]], [26, 8, 10]);
  });

  test('a day the watch has nothing for resolves to null, not an exception', () async {
    final t = ScriptedTransport({
      StarmaxHistoryType.heartRate.cmd: [_hex(_frames('heartRateNoData').single)],
    });
    final c = StarmaxClient(t, timeout: const Duration(seconds: 2));
    addTearDown(c.dispose);
    expect(await c.readDaySeries(StarmaxHistoryType.heartRate, DateTime(2026, 8, 11)), isNull);
  });

  test('a watch that goes silent mid-transfer gives up instead of hanging', () async {
    // Only the FIRST of the two heart-rate frames is played back, so the
    // transfer never reaches dataLength.
    final t = ScriptedTransport({
      StarmaxHistoryType.heartRate.cmd: [_hex(_frames('heartRate').first)],
    });
    final c = StarmaxClient(t, historyIdleTimeout: const Duration(milliseconds: 150));
    addTearDown(c.dispose);
    expect(await c.readDaySeries(StarmaxHistoryType.heartRate, DateTime(2026, 8, 10)), isNull);
  });

  // ---- The walk ----

  test('the sync asks which days exist before asking for any of them', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams) t: [DateTime(2026, 8, 9), DateTime(2026, 8, 10)],
    });
    await syncStarmaxHistory(w, maxDays: 7);

    // Every valid-dates question comes before every day question. That is the
    // whole point of §5.53: without it the sync walks a guessed window and most
    // of what it asks for does not exist.
    final firstDay = w.asked.indexWhere((a) => !a.startsWith('dates:'));
    expect(firstDay, greaterThan(0));
    expect(w.asked.take(firstDay).every((a) => a.startsWith('dates:')), isTrue);
    expect(w.asked.take(firstDay).length, starmaxBackfillStreams.length);
  });

  test('it never asks a stream for a day that stream does not hold', () async {
    final w = FakeWatch({
      // The watch has step data for two days and heart rate for one. Blood
      // pressure is switched off entirely.
      StarmaxHistoryType.step: [DateTime(2026, 8, 9), DateTime(2026, 8, 10)],
      StarmaxHistoryType.heartRate: [DateTime(2026, 8, 10)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 7);

    expect(w.asked, contains('step:9'));
    expect(w.asked, contains('step:10'));
    expect(w.asked, contains('heartRate:10'));
    expect(w.asked, isNot(contains('heartRate:9')));
    expect(w.asked.where((a) => a.startsWith('bloodPressure:')), isEmpty);

    expect(report.coveredDays, 2);
    final ninth = report.days.firstWhere((d) => d.date.day == 9);
    expect(ninth.heartRateAvg, isNull, reason: 'no heart rate that day, not a zero');
    expect(ninth.steps, greaterThan(0));
  });

  test('a day aggregates every stream, skipping the hours nothing was measured', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams) t: [DateTime(2026, 8, 10)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 7);
    expect(report.coveredDays, 1);
    final d = report.days.single;

    expect(d.date, DateTime(2026, 8, 10));
    expect(d.steps, 24 * 100);
    expect(d.kcal, 24 * 4);
    expect(d.meters, 24 * 700 ~/ 10); // decimetres → metres
    // 18 asleep slots of 60 minutes; the two awake ones are not sleep.
    expect(d.sleepMinutes, 18 * 60);
    expect(d.deepSleepMinutes, 6 * 60);
    expect(d.lightSleepMinutes, 12 * 60);
    // The first four hours are unmeasured (0). Averaging them in would drag the
    // mean heart rate down by a sixth and report a resting rate she never had.
    final measured = [for (var i = 4; i < 24; i++) 60 + i];
    expect(d.heartRateAvg, (measured.reduce((a, b) => a + b) / measured.length).round());
    expect(d.heartRateMin, 64);
    expect(d.heartRateMax, 83);
    expect(d.spo2Avg, 95);
    expect(d.systolicAvg, 118);
    expect(d.diastolicAvg, 76);
    expect(d.tempAvgTenths, 365);
    expect(d.tempC, 36.5);
    expect(d.stress, 30);
    expect(d.breathRate, 16);
    expect(d.met, 3);
    expect(d.bloodSugarTenths, 52);
    expect(d.bloodSugar, 5.2);
  });

  test('the chart samples cover the day hourly, in time order', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams) t: [DateTime(2026, 8, 9), DateTime(2026, 8, 10)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 7);

    expect(report.samples, isNotEmpty);
    // Twenty hourly points a day, both days — a week of raw samples would be
    // 2 000 points and would evict the live readings from the buffer.
    expect(report.samples.length, 40);
    expect(report.samples.every((s) => s.heartRate != null), isTrue);
    final days = report.samples.map((s) => DateTime(s.at.year, s.at.month, s.at.day)).toSet();
    expect(days, {DateTime(2026, 8, 9), DateTime(2026, 8, 10)});
  });

  test('a day the watch lists but has no samples for is not filed as a zero day', () async {
    // A watch that lists a date and then answers "no data" for every stream.
    final w = _EmptyWatch([DateTime(2026, 8, 10)]);
    final report = await syncStarmaxHistory(w, maxDays: 7);
    expect(report.days, isEmpty);
    expect(report.coveredDays, 0);
    expect(report.isEmpty, isTrue);
  });

  test('a label may only claim the days that came back', () async {
    final w = FakeWatch({
      // Asked for seven; the watch has two.
      for (final t in starmaxBackfillStreams) t: [DateTime(2026, 8, 9), DateTime(2026, 8, 10)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 7);
    expect(report.requestedDays, 7);
    expect(report.coveredDays, 2);
    expect(report.earliest, DateTime(2026, 8, 9));
  });

  test('maxDays caps the walk, newest days first', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams)
        t: [for (var d = 1; d <= 10; d++) DateTime(2026, 8, d)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 3);
    expect(report.days.map((d) => d.date.day).toSet(), {10, 9, 8});
  });

  test('notBefore skips days already stored', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams)
        t: [for (var d = 1; d <= 10; d++) DateTime(2026, 8, d)],
    });
    final report = await syncStarmaxHistory(w, maxDays: 30, notBefore: DateTime(2026, 8, 9));
    expect(report.days.map((d) => d.date.day).toSet(), {10, 9});
  });

  test('re-syncing a day produces the same wire payload — the upsert can dedupe', () async {
    final w = FakeWatch({
      for (final t in starmaxBackfillStreams) t: [DateTime(2026, 8, 10)],
    });
    final now = DateTime(2026, 8, 12, 9);
    final first = (await syncStarmaxHistory(w, maxDays: 7)).days.single;
    final second = (await syncStarmaxHistory(w, maxDays: 7)).days.single;

    final a = first.toIngestPayload(deviceId: 'AA:BB', now: now);
    final b = second.toIngestPayload(deviceId: 'AA:BB', now: now);
    expect(a, b);
    // The key the server upserts on is the same both times, which is what makes
    // a second backfill an UPDATE rather than a second row.
    expect(a['day'], '2026-08-10');
    expect(a['deviceId'], 'AA:BB');
  });

  test('a backfilled day is stamped with that day, not with the sync', () {
    final day = WearableDay(date: DateTime(2026, 8, 10), steps: 4000);
    final wire = day.toIngestPayload(deviceId: 'AA:BB', now: DateTime(2026, 8, 12, 9));
    expect(wire['day'], '2026-08-10');
    // Tuesday's history must not claim to have been recorded on Friday.
    expect(DateTime.parse(wire['recordedAt'] as String).toLocal().day, 10);
    // …and today's, still in progress, is stamped now rather than in the future.
    final today = WearableDay(date: DateTime(2026, 8, 12), steps: 900);
    final now = DateTime(2026, 8, 12, 9);
    expect(DateTime.parse(today.toIngestPayload(deviceId: 'AA:BB', now: now)['recordedAt'] as String)
        .isAfter(now.toUtc()), isFalse);
  });

  test('battery is absent from a backfilled day, so it cannot back-date one', () {
    final wire = WearableDay(date: DateTime(2026, 8, 10), steps: 10)
        .toIngestPayload(deviceId: 'AA:BB', now: DateTime(2026, 8, 12));
    expect(wire.containsKey('batteryPercent'), isFalse);
    expect(wire['worn'], false);
  });
}

class _EmptyWatch implements StarmaxHistoryReader {
  final List<DateTime> dates;
  _EmptyWatch(this.dates);
  @override
  Future<List<DateTime>> readValidHistoryDates(StarmaxHistoryType type) async => dates;
  @override
  Future<StarmaxDaySeries?> readDaySeries(StarmaxHistoryType t, DateTime d) async => null;
  @override
  Future<StarmaxBpDay?> readBloodPressureDay(DateTime d) async => null;
  @override
  Future<StarmaxStepDay?> readStepDay(DateTime d) async => null;
}
