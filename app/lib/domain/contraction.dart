/// Contraction timing — a live labour-companion tool. Each contraction records
/// its start and end; the interval is the gap between consecutive STARTS (the
/// standard way contractions are timed). PURE Dart → unit-testable via
/// verify_contractions.dart. It measures duration + frequency and surfaces the
/// widely-taught "5-1-1" childbirth-education pattern as INFORMATIONAL progress
/// (never a directive) — the UI always defers to the user's own provider.
library;

class Contraction {
  final DateTime start;
  final DateTime end;
  const Contraction({required this.start, required this.end});

  Duration get duration {
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Interval from the previous contraction's start to [current]'s start (how far
/// apart they are). Null for the first contraction.
Duration? intervalBefore(List<Contraction> earlierToLater, int index) {
  if (index <= 0 || index >= earlierToLater.length) return null;
  final d = earlierToLater[index].start.difference(earlierToLater[index - 1].start);
  return d.isNegative ? Duration.zero : d;
}

class ContractionStats {
  final int count;
  final Duration avgDuration;
  final Duration avgInterval; // averaged over the gaps between starts
  const ContractionStats(this.count, this.avgDuration, this.avgInterval);
}

/// A finished contraction-timing session, kept in history. Pure + JSON.
class ContractionSessionRecord {
  final DateTime endedAt;
  final int count;
  final int avgDurationSec;
  final int avgIntervalSec;
  const ContractionSessionRecord({
    required this.endedAt,
    required this.count,
    required this.avgDurationSec,
    required this.avgIntervalSec,
  });

  Duration get avgDuration => Duration(seconds: avgDurationSec);
  Duration get avgInterval => Duration(seconds: avgIntervalSec);

  Map<String, dynamic> toJson() => {
        'endedAt': endedAt.toIso8601String(),
        'count': count,
        'avgDurationSec': avgDurationSec,
        'avgIntervalSec': avgIntervalSec,
      };

  factory ContractionSessionRecord.fromJson(Map<String, dynamic> j) => ContractionSessionRecord(
        endedAt: DateTime.parse(j['endedAt'] as String),
        count: (j['count'] as num).toInt(),
        avgDurationSec: (j['avgDurationSec'] as num).toInt(),
        avgIntervalSec: (j['avgIntervalSec'] as num).toInt(),
      );
}

/// Progress against the "5-1-1" pattern taught in childbirth classes:
/// contractions about 5 minutes apart, each lasting about 1 minute, sustained
/// for 1 hour. Purely descriptive of the timed data — NOT medical advice.
class FivOneOneProgress {
  final bool intervalMet; // avg interval ≤ 5 min
  final bool durationMet; // avg duration ≥ 1 min
  final bool sustainedMet; // pattern has spanned ≥ 1 hour
  const FivOneOneProgress(this.intervalMet, this.durationMet, this.sustainedMet);

  /// How many of the three 5-1-1 criteria are currently met (0–3).
  int get metCount => (intervalMet ? 1 : 0) + (durationMet ? 1 : 0) + (sustainedMet ? 1 : 0);

  /// All three criteria met.
  bool get allMet => intervalMet && durationMet && sustainedMet;
}

/// Evaluate the 5-1-1 pattern over [list] (earliest-first). Needs ≥2
/// contractions for the interval/sustained checks; with fewer, those are false.
FivOneOneProgress fiveOneOneProgress(List<Contraction> list) {
  final stats = contractionStats(list);
  final hasPair = list.length >= 2;
  final spanSec = hasPair ? list.last.start.difference(list.first.start).inSeconds : 0;
  return FivOneOneProgress(
    hasPair && stats.avgInterval.inSeconds > 0 && stats.avgInterval.inSeconds <= 300,
    stats.avgDuration.inSeconds >= 60,
    hasPair && spanSec >= 3600,
  );
}

/// Averages over [list] (assumed earliest-first). Interval average needs ≥2
/// contractions; with fewer it is Duration.zero.
ContractionStats contractionStats(List<Contraction> list) {
  if (list.isEmpty) return const ContractionStats(0, Duration.zero, Duration.zero);
  var durSum = 0;
  for (final c in list) {
    durSum += c.duration.inSeconds;
  }
  var intSum = 0, intCount = 0;
  for (var i = 1; i < list.length; i++) {
    intSum += list[i].start.difference(list[i - 1].start).inSeconds;
    intCount++;
  }
  return ContractionStats(
    list.length,
    Duration(seconds: (durSum / list.length).round()),
    intCount == 0 ? Duration.zero : Duration(seconds: (intSum / intCount).round()),
  );
}
