/// One WHOLE DAY as the watch recorded it — including the days the phone was
/// nowhere near it.
///
/// PURE Dart → verified by test/starmax_history_sync_test.dart and
/// test/watch_history_pipeline_test.dart.
///
/// [WearableMetrics] is a SNAPSHOT: what the watch is showing right now, polled
/// every thirty seconds while the app is open and connected. It answers "how is
/// she doing", and only for the minutes somebody was looking. This is the other
/// half: the watch stores a week or more of samples on the device itself, and
/// this is a day of them folded into the one row per day the server keeps.
///
/// THE ZERO RULE, ONCE MORE
///
/// Every wellness field here is nullable, and null means "the watch measured
/// nothing that day". The device writes 0xFF into a slot it did not measure and
/// the parser turns that into 0; a 0 averaged into a day would report a resting
/// heart rate of forty when the truth is that she took the watch off.
library;

import 'health_series.dart';

/// A whole day of watch history, aggregated to the row shape the server keeps.
class WearableDay {
  /// The WEARER's local date. The watch rolls its own totals at her midnight,
  /// and it tells us the date it filed them under — that date is used as-is
  /// rather than re-derived from a UTC instant.
  final DateTime date;

  // Activity totals. 0 is a real value: a day with no walking is a fact.
  final int steps;
  final int kcal;
  final int meters;

  // Sleep, in minutes.
  final int sleepMinutes;
  final int deepSleepMinutes;
  final int lightSleepMinutes;

  // Wellness averages over the day's measured samples — null when there were
  // none.
  final int? stress;
  final int? breathRate;
  final int? met;

  // Vitals. Averages plus the extremes that matter clinically: a day whose mean
  // heart rate is 78 and whose maximum is 165 is not the same day as one that
  // never left 80, and a mean alone cannot tell them apart.
  final int? heartRateAvg;
  final int? heartRateMin;
  final int? heartRateMax;
  final int? spo2Avg;
  final int? spo2Min;
  final int? systolicAvg;
  final int? diastolicAvg;

  /// Body temperature in TENTHS of a degree Celsius, as the device reports it
  /// (365 = 36.5 °C) — kept integral so nothing rounds twice on the way to the
  /// database.
  final int? tempAvgTenths;

  /// The day's mean blood-sugar value, in the watch's own raw units.
  ///
  /// NOT «tenths of a mmol/L», which is what this said and what the deleted
  /// `bloodSugar` getter turned it into. The vendor documents the field as
  /// `当前血糖（0.1）` — a decimal place, no unit — so the division by ten was
  /// where the unit was invented. The integer is carried to the server as-is,
  /// like the day's other raw columns; nothing converts it to a scale or prints
  /// it beside one. See docs/CLINICAL-REVIEW-WATCH.md.
  final int? bloodSugarTenths;

  /// How many days of history this row came from is a property of the SYNC, not
  /// of the day; see [WearableHistoryReport].
  const WearableDay({
    required this.date,
    this.steps = 0,
    this.kcal = 0,
    this.meters = 0,
    this.sleepMinutes = 0,
    this.deepSleepMinutes = 0,
    this.lightSleepMinutes = 0,
    this.stress,
    this.breathRate,
    this.met,
    this.heartRateAvg,
    this.heartRateMin,
    this.heartRateMax,
    this.spo2Avg,
    this.spo2Min,
    this.systolicAvg,
    this.diastolicAvg,
    this.tempAvgTenths,
    this.bloodSugarTenths,
  });

  /// yyyy-MM-dd, the wire form of [date].
  String get isoDate => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Body temperature in °C, or null.
  double? get tempC => tempAvgTenths == null ? null : tempAvgTenths! / 10.0;

  /// True when the watch recorded anything at all for this day. A day it holds
  /// a date for but no samples is not worth a network write, and would file an
  /// all-zero row that reads as "she did nothing" rather than "we know nothing".
  bool get hasAnything =>
      steps > 0 ||
      kcal > 0 ||
      meters > 0 ||
      sleepMinutes > 0 ||
      stress != null ||
      breathRate != null ||
      met != null ||
      heartRateAvg != null ||
      spo2Avg != null ||
      systolicAvg != null ||
      tempAvgTenths != null ||
      bloodSugarTenths != null;

  /// The wire form for `/ingest/batch` (a `wearable` item).
  ///
  /// `recordedAt` is the END of the wearer's day, not "now": this row describes
  /// that day, and stamping it with the moment of the sync would make a
  /// Tuesday's history claim to have been recorded on Friday. For today, the
  /// day is not over, so [now] is used instead — clamped, so a device clock
  /// running ahead cannot stamp the future.
  ///
  /// Battery and charging are deliberately absent. They describe the watch at
  /// the moment of the poll and say nothing about last Tuesday; the server's
  /// upsert COALESCEs a missing battery rather than overwriting it, so leaving
  /// them out preserves the last real reading instead of back-dating one.
  Map<String, dynamic> toIngestPayload({
    required String deviceId,
    required DateTime now,
  }) {
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final stamp = endOfDay.isAfter(now) ? now : endOfDay;
    return {
      'deviceId': deviceId,
      'day': isoDate,
      'recordedAt': stamp.toUtc().toIso8601String(),
      'steps': steps,
      'kcal': kcal,
      'meters': meters,
      'sleepMinutes': sleepMinutes,
      'deepSleepMinutes': deepSleepMinutes,
      'lightSleepMinutes': lightSleepMinutes,
      if (stress != null) 'stress': stress,
      if (breathRate != null) 'breathRate': breathRate,
      if (met != null) 'met': met,
      if (heartRateAvg != null) 'heartRateAvg': heartRateAvg,
      if (heartRateMin != null) 'heartRateMin': heartRateMin,
      if (heartRateMax != null) 'heartRateMax': heartRateMax,
      if (spo2Avg != null) 'spo2Avg': spo2Avg,
      if (spo2Min != null) 'spo2Min': spo2Min,
      if (systolicAvg != null) 'systolicAvg': systolicAvg,
      if (diastolicAvg != null) 'diastolicAvg': diastolicAvg,
      if (tempAvgTenths != null) 'tempAvgTenths': tempAvgTenths,
      if (bloodSugarTenths != null) 'bloodSugarTenths': bloodSugarTenths,
      // The history says nothing about whether the watch is on her wrist NOW.
      'charging': false,
      'worn': false,
    };
  }
}

/// What one backfill actually covered.
///
/// Carried alongside the days so the UI can say «за 7 дней» because the sync
/// returned seven days, not because seven is a nice number. [requestedDays] is
/// the window the app was willing to ask for; [days] is what the watch had.
class WearableHistoryReport {
  final List<WearableDay> days;

  /// Per-day vital samples, thinned to hourly means, for the local chart series.
  final List<HealthSample> samples;

  /// The cap the sync was run with — how far back it was prepared to look.
  final int requestedDays;

  const WearableHistoryReport({
    required this.days,
    required this.samples,
    required this.requestedDays,
  });

  /// The number of distinct days the watch actually returned data for. This —
  /// not [requestedDays] — is what a label may claim.
  int get coveredDays => days.where((d) => d.hasAnything).length;

  DateTime? get earliest {
    final withData = days.where((d) => d.hasAnything).toList();
    if (withData.isEmpty) return null;
    withData.sort((a, b) => a.date.compareTo(b.date));
    return withData.first.date;
  }

  bool get isEmpty => coveredDays == 0;
}
