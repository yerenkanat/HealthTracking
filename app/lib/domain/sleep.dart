/// Sleep tracking domain — nightly sleep summaries with stage breakdown and a
/// quality assessment. PURE Dart (no Flutter) so it's unit-testable via
/// `dart run tool/verify_sleep.dart`. The band reports one summary per night;
/// the UI just renders what this computes.
///
/// Convention: a [SleepSummary] is keyed by the WAKE date (the morning the
/// night ended), so "last night" is the summary whose [night] is today.
library;

/// Overall sleep quality, from total sleep + deep proportion + efficiency.
enum SleepQuality { good, fair, poor }

/// Thresholds behind the quality assessment. Adult guidance: ~7–9 h total, with
/// roughly 13–23% deep sleep and high (>85%) sleep efficiency. Kept conservative
/// and non-clinical — this is wellness guidance, never a diagnosis.
class SleepThresholds {
  static const int goodAsleepMin = 7 * 60; // ≥ 7 h
  static const int fairAsleepMin = 6 * 60; // ≥ 6 h
  static const double goodDeepFraction = 0.13; // ≥ 13% of sleep is deep
  static const double goodEfficiency = 0.85; // ≥ 85% of time in bed asleep
}

SleepQuality assessSleep(SleepSummary s) {
  if (s.asleepMin >= SleepThresholds.goodAsleepMin &&
      s.deepFraction >= SleepThresholds.goodDeepFraction &&
      s.efficiency >= SleepThresholds.goodEfficiency) {
    return SleepQuality.good;
  }
  if (s.asleepMin >= SleepThresholds.fairAsleepMin) return SleepQuality.fair;
  return SleepQuality.poor;
}

class SleepSummary {
  final DateTime night; // wake date (morning the night ended)
  final int deepMin;
  final int remMin;
  final int lightMin;
  final int awakeMin;

  const SleepSummary({
    required this.night,
    this.deepMin = 0,
    this.remMin = 0,
    this.lightMin = 0,
    this.awakeMin = 0,
  });

  int get asleepMin => deepMin + remMin + lightMin;
  int get inBedMin => asleepMin + awakeMin;

  /// Fraction of in-bed time actually asleep (0..1).
  double get efficiency => inBedMin == 0 ? 0 : asleepMin / inBedMin;
  double get deepFraction => asleepMin == 0 ? 0 : deepMin / asleepMin;
  double get remFraction => asleepMin == 0 ? 0 : remMin / asleepMin;
  double get lightFraction => asleepMin == 0 ? 0 : lightMin / asleepMin;

  int get hours => asleepMin ~/ 60;
  int get minutes => asleepMin % 60;

  SleepQuality get quality => assessSleep(this);

  Map<String, dynamic> toJson() => {
        'night': night.toIso8601String(),
        'deepMin': deepMin,
        'remMin': remMin,
        'lightMin': lightMin,
        'awakeMin': awakeMin,
      };

  factory SleepSummary.fromJson(Map<String, dynamic> j) => SleepSummary(
        night: DateTime.parse(j['night'] as String),
        deepMin: (j['deepMin'] as num?)?.toInt() ?? 0,
        remMin: (j['remMin'] as num?)?.toInt() ?? 0,
        lightMin: (j['lightMin'] as num?)?.toInt() ?? 0,
        awakeMin: (j['awakeMin'] as num?)?.toInt() ?? 0,
      );
}

/// Aggregate stats over recent nights (for the detail screen header).
class SleepStats {
  final int nights;
  final int avgAsleepMin;
  final double avgDeepFraction;
  final int bestAsleepMin;
  const SleepStats(this.nights, this.avgAsleepMin, this.avgDeepFraction, this.bestAsleepMin);
}

/// The most recent night in [nights] (by date), or null if empty.
SleepSummary? latestNight(List<SleepSummary> nights) {
  if (nights.isEmpty) return null;
  var best = nights.first;
  for (final n in nights) {
    if (n.night.isAfter(best.night)) best = n;
  }
  return best;
}

SleepStats? sleepStats(List<SleepSummary> nights) {
  if (nights.isEmpty) return null;
  var totalAsleep = 0, best = 0;
  var deepFracSum = 0.0;
  for (final n in nights) {
    totalAsleep += n.asleepMin;
    if (n.asleepMin > best) best = n.asleepMin;
    deepFracSum += n.deepFraction;
  }
  return SleepStats(
    nights.length,
    (totalAsleep / nights.length).round(),
    deepFracSum / nights.length,
    best,
  );
}

/// Nights sorted oldest → newest (for a left-to-right bar chart).
List<SleepSummary> sortedByNight(List<SleepSummary> nights) {
  final out = List<SleepSummary>.from(nights);
  out.sort((a, b) => a.night.compareTo(b.night));
  return out;
}
