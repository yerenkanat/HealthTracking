/// The backfill: ask the watch which days it holds, then read them.
///
/// PURE Dart over an injected [StarmaxHistoryReader] → verified by
/// test/starmax_history_sync_test.dart with a fake reader. No BLE here.
///
/// WHY IT ASKS FIRST
///
/// §5.53 `getValidHistoryDates` exists precisely so a sync does not have to
/// guess. Walking a fixed fourteen-day window costs one request per day per
/// stream — 140 round trips — and most of them are answered «数据无效» by a
/// watch that only keeps seven days. Asking first costs ten tiny requests and
/// then only reads days that exist.
///
/// The valid-date set is asked PER STREAM, because it is per stream: a watch
/// with continuous heart rate switched on and blood pressure switched off holds
/// different days for the two, and requesting blood pressure for a day it never
/// measured is the round trip this call was added to avoid.
library;

import 'dart:async';

import '../../domain/health_series.dart';
import '../../domain/wearable_day.dart';
import 'starmax_history.dart';

/// What a backfill needs from a connected watch. [StarmaxClient] implements it;
/// tests supply a fake, so the whole walk is exercised without a radio.
abstract class StarmaxHistoryReader {
  Future<List<DateTime>> readValidHistoryDates(StarmaxHistoryType type);
  Future<StarmaxDaySeries?> readDaySeries(StarmaxHistoryType type, DateTime day);
  Future<StarmaxBpDay?> readBloodPressureDay(DateTime day);
  Future<StarmaxStepDay?> readStepDay(DateTime day);
}

/// The streams a backfill reads, in the order it reads them.
///
/// Every one of these has somewhere to land in `wearable_days`. Three more the
/// vendor documents — MAI (§5.52), exercise intensity + stand hours (§5.62) and
/// head-shake (§5.64) — are decodable and are deliberately NOT read: nothing
/// stores them, and a sync that spends radio time on data with no destination is
/// battery spent for nothing.
const starmaxBackfillStreams = <StarmaxHistoryType>[
  StarmaxHistoryType.step,
  StarmaxHistoryType.sleep,
  StarmaxHistoryType.heartRate,
  StarmaxHistoryType.bloodOxygen,
  StarmaxHistoryType.bloodPressure,
  StarmaxHistoryType.temp,
  StarmaxHistoryType.stress,
  StarmaxHistoryType.respirationRate,
  StarmaxHistoryType.met,
  StarmaxHistoryType.bloodSugar,
];

int? _mean(Iterable<int> xs) {
  if (xs.isEmpty) return null;
  var sum = 0, n = 0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return (sum / n).round();
}

/// A day being assembled from several streams.
class _DayBuilder {
  final DateTime date;
  _DayBuilder(this.date);

  int steps = 0, kcal = 0, meters = 0;
  int sleepMin = 0, deepMin = 0, lightMin = 0;
  final hr = <int>[];
  final spo2 = <int>[];
  final sys = <int>[];
  final dia = <int>[];
  final temp = <int>[];
  final stress = <int>[];
  final breath = <int>[];
  final met = <int>[];
  final sugar = <int>[];

  /// Hourly buckets for the local chart series, so a week of backfill adds
  /// twenty-four points a day per metric rather than two hundred and eighty.
  final buckets = <int, _HourBucket>{};

  _HourBucket _bucket(double minuteOfDay) =>
      buckets.putIfAbsent((minuteOfDay / 60).floor().clamp(0, 23), () => _HourBucket());

  WearableDay build() => WearableDay(
        date: date,
        steps: steps,
        kcal: kcal,
        meters: meters,
        sleepMinutes: sleepMin,
        deepSleepMinutes: deepMin,
        lightSleepMinutes: lightMin,
        stress: _mean(stress),
        breathRate: _mean(breath),
        met: _mean(met),
        heartRateAvg: _mean(hr),
        heartRateMin: hr.isEmpty ? null : hr.reduce((a, b) => a < b ? a : b),
        heartRateMax: hr.isEmpty ? null : hr.reduce((a, b) => a > b ? a : b),
        spo2Avg: _mean(spo2),
        spo2Min: spo2.isEmpty ? null : spo2.reduce((a, b) => a < b ? a : b),
        systolicAvg: _mean(sys),
        diastolicAvg: _mean(dia),
        tempAvgTenths: _mean(temp),
        bloodSugarTenths: _mean(sugar),
      );

  List<HealthSample> chartSamples() {
    final out = <HealthSample>[];
    final hours = buckets.keys.toList()..sort();
    for (final h in hours) {
      final b = buckets[h]!;
      final s = b.toSample(DateTime(date.year, date.month, date.day, h, 30));
      if (s != null) out.add(s);
    }
    return out;
  }
}

class _HourBucket {
  final hr = <int>[];
  final spo2 = <int>[];
  final sys = <int>[];
  final dia = <int>[];
  final tempTenths = <int>[];
  bool asleep = false;

  HealthSample? toSample(DateTime at) {
    final h = _mean(hr);
    final o = _mean(spo2);
    final sy = _mean(sys);
    final di = _mean(dia);
    final t = _mean(tempTenths);
    if (h == null && o == null && sy == null && t == null) return null;
    // Same plausibility window the live frame and the OEM band apply (20–45 °C).
    // The history stream is u16 tenths off the same external device, so it can
    // produce the same 400 °C, and these samples land on the chart the advisor
    // reads.
    final tempC = t == null ? null : t / 10.0;
    return HealthSample(
      at: at,
      heartRate: h?.toDouble(),
      spo2: o?.toDouble(),
      systolic: sy?.toDouble(),
      diastolic: di?.toDouble(),
      coreTemp: (tempC != null && tempC >= 20 && tempC <= 45) ? tempC : null,
      // No `glucose:` here, and no `/ 10.0` to produce one. A backfilled day of
      // wrist sugar has no scale to be drawn or graded on, so it does not
      // become a chart point at all; the day's mean still goes to the server as
      // the raw integer it is.
      duringSleep: asleep,
      // A watch recorded these while the phone was away. Stated rather than
      // defaulted: without it a backfilled day of wrist estimates would earn
      // «температура держится ровно», which is the defect this whole change
      // exists to remove — arriving by the back door.
      source: ReadingSource.sensor,
    );
  }
}

/// Run a backfill.
///
/// [maxDays] caps how far back to go; the newest days are read first, because a
/// sync that is interrupted halfway should have delivered the days she is most
/// likely to be asked about. [notBefore] skips days already stored, so a second
/// sync on the same day is cheap.
///
/// [onDay] fires as each day completes, so the days reach the batcher (and the
/// screen) progressively rather than all at the end — a backfill interrupted by
/// a walk out of range still delivered what it had.
Future<WearableHistoryReport> syncStarmaxHistory(
  StarmaxHistoryReader reader, {
  int maxDays = 7,
  DateTime? notBefore,
  void Function(WearableDay day)? onDay,
}) async {
  // 1. Which days does the watch hold, per stream?
  final perStream = <StarmaxHistoryType, Set<DateTime>>{};
  final all = <DateTime>{};
  for (final type in starmaxBackfillStreams) {
    final dates = await reader.readValidHistoryDates(type);
    final normalised = dates.map((d) => DateTime(d.year, d.month, d.day)).toSet();
    perStream[type] = normalised;
    all.addAll(normalised);
  }

  var days = all.toList()..sort((a, b) => b.compareTo(a)); // newest first
  if (notBefore != null) {
    final floor = DateTime(notBefore.year, notBefore.month, notBefore.day);
    days = days.where((d) => !d.isBefore(floor)).toList();
  }
  if (days.length > maxDays) days = days.sublist(0, maxDays);

  final built = <WearableDay>[];
  final samples = <HealthSample>[];

  for (final date in days) {
    final b = _DayBuilder(date);

    for (final type in starmaxBackfillStreams) {
      if (!(perStream[type]?.contains(date) ?? false)) continue;
      switch (type) {
        case StarmaxHistoryType.step:
          final d = await reader.readStepDay(date);
          if (d != null) {
            b.steps = d.totalSteps;
            b.kcal = d.totalKcal;
            b.meters = d.totalMetres;
          }
        case StarmaxHistoryType.sleep:
          final d = await reader.readDaySeries(type, date);
          if (d != null) _foldSleep(b, d);
        case StarmaxHistoryType.bloodPressure:
          final d = await reader.readBloodPressureDay(date);
          if (d != null) {
            for (final s in d.samples) {
              if (s.systolic <= 0 || s.diastolic <= 0) continue;
              b.sys.add(s.systolic);
              b.dia.add(s.diastolic);
              b._bucket(s.minuteOfDay)
                ..sys.add(s.systolic)
                ..dia.add(s.diastolic);
            }
          }
        default:
          final d = await reader.readDaySeries(type, date);
          if (d != null) _foldSeries(b, type, d);
      }
    }

    final day = b.build();
    if (!day.hasAnything) continue;
    built.add(day);
    samples.addAll(b.chartSamples());
    onDay?.call(day);
  }

  return WearableHistoryReport(days: built, samples: samples, requestedDays: maxDays);
}

void _foldSeries(_DayBuilder b, StarmaxHistoryType type, StarmaxDaySeries d) {
  for (final s in d.samples) {
    if (s.value <= 0) continue; // 0 is the device's "not measured"
    switch (type) {
      case StarmaxHistoryType.heartRate:
        b.hr.add(s.value);
        b._bucket(s.minuteOfDay).hr.add(s.value);
      case StarmaxHistoryType.bloodOxygen:
        b.spo2.add(s.value);
        b._bucket(s.minuteOfDay).spo2.add(s.value);
      case StarmaxHistoryType.temp:
        b.temp.add(s.value);
        b._bucket(s.minuteOfDay).tempTenths.add(s.value);
      case StarmaxHistoryType.bloodSugar:
        // Day-level only. The raw value still reaches the server as an integer
        // column, and it no longer reaches the hourly chart samples, because
        // there is nothing to put it on: the `/ 10.0` that made it a mmol/L is
        // deleted, not stubbed (docs/CLINICAL-REVIEW-WATCH.md — the vendor
        // documents `当前血糖（0.1）`, a decimal place and not a unit).
        b.sugar.add(s.value);
      case StarmaxHistoryType.stress:
        // The column is CHECKed 0–100; a firmware that reports outside it is
        // dropped rather than rejected by the database on arrival.
        if (s.value <= 100) b.stress.add(s.value);
      case StarmaxHistoryType.respirationRate:
        if (s.value >= 1 && s.value <= 80) b.breath.add(s.value);
      case StarmaxHistoryType.met:
        b.met.add(s.value);
      default:
        break;
    }
  }
}

/// Fold the sleep stream into the day's minutes.
///
/// Each sample stands for `1440 / dataLength` minutes. Deep, light and REM are
/// counted as sleep; «清醒» (awake) and the 0 filler are not, which is the whole
/// point — a night spent awake in bed is not eight hours of sleep. A code above
/// 128 is a NAP of the same stage (§5.45), and a nap is sleep.
///
/// `sleepMinutes` is the TOTAL, which is deep + light + REM + the onset marker;
/// the app's sleep card derives REM as the remainder, exactly as it already does
/// for the live snapshot, so the three parts and the total stay consistent.
void _foldSleep(_DayBuilder b, StarmaxDaySeries d) {
  final n = d.samples.length;
  if (n == 0) return;
  final minutesPerSample = 1440 / n;
  var total = 0.0, deep = 0.0, light = 0.0;
  for (final s in d.samples) {
    if (!StarmaxSleepStage.isAsleep(s.value)) continue;
    final stage = StarmaxSleepStage.stage(s.value);
    total += minutesPerSample;
    if (stage == StarmaxSleepStage.deep) deep += minutesPerSample;
    if (stage == StarmaxSleepStage.light) light += minutesPerSample;
    b._bucket(s.minuteOfDay).asleep = true;
  }
  b.sleepMin = total.round();
  b.deepMin = deep.round();
  b.lightMin = light.round();
}
