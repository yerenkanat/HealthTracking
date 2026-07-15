/// Chart-ready data prep for the health dashboard. Pure Dart → unit-testable,
/// so the UI just renders what this computes. Owned by the dataviz/UX specialists.
///
/// Turns raw telemetry samples into per-metric series with downsampling (so a week
/// of minute-data doesn't choke a sparkline), summary stats, and danger bands
/// derived from the SAME triage thresholds the alerts use — the chart's red zone
/// and the emergency alert can never disagree.
library;

import '../core/triage.dart' show TriageThresholds;

class HealthSample {
  final DateTime at;
  final double? heartRate;
  final double? spo2;
  final double? systolic;
  final double? diastolic;
  final double? coreTemp;
  final bool duringSleep;
  const HealthSample({
    required this.at,
    this.heartRate,
    this.spo2,
    this.systolic,
    this.diastolic,
    this.coreTemp,
    this.duringSleep = false,
  });

  factory HealthSample.fromJson(Map<String, dynamic> j) => HealthSample(
        at: DateTime.parse(j['recordedAt'] as String),
        heartRate: (j['heartRateBpm'] as num?)?.toDouble(),
        spo2: (j['spo2Pct'] as num?)?.toDouble(),
        systolic: (j['systolicMmHg'] as num?)?.toDouble(),
        diastolic: (j['diastolicMmHg'] as num?)?.toDouble(),
        coreTemp: (j['coreTempC'] as num?)?.toDouble(),
        duringSleep: (j['duringSleep'] as bool?) ?? false,
      );
}

class SeriesPoint {
  final DateTime t;
  final double value;
  const SeriesPoint(this.t, this.value);
}

enum Trend { up, down, flat }

class SeriesStats {
  final double latest;
  final double min;
  final double max;
  final double mean;
  final double delta; // latest - first
  final Trend trend;
  const SeriesStats(this.latest, this.min, this.max, this.mean, this.delta, this.trend);
}

/// warnAbove/warnBelow mark the danger zone the chart shades. Pulled from the
/// canonical thresholds so UI and alerts stay consistent.
class MetricBand {
  final double? warnAbove;
  final double? warnBelow;
  const MetricBand({this.warnAbove, this.warnBelow});
}

const metricKeys = ['hr', 'spo2', 'systolic', 'diastolic', 'temp'];

MetricBand bandFor(String metric) {
  switch (metric) {
    case 'hr':
      return MetricBand(warnAbove: TriageThresholds.hrTachyWarning.toDouble());
    case 'spo2':
      return MetricBand(warnBelow: TriageThresholds.spo2Warning.toDouble());
    case 'systolic':
      return MetricBand(warnAbove: TriageThresholds.bpSystolicEmergency.toDouble());
    case 'diastolic':
      return MetricBand(warnAbove: TriageThresholds.bpDiastolicEmergency.toDouble());
    case 'temp':
      return const MetricBand(warnAbove: TriageThresholds.feverWarningC);
    default:
      return const MetricBand();
  }
}

double? _pick(HealthSample s, String metric) => switch (metric) {
      'hr' => s.heartRate,
      'spo2' => s.spo2,
      'systolic' => s.systolic,
      'diastolic' => s.diastolic,
      'temp' => s.coreTemp,
      _ => null,
    };

/// Build one metric's series (chronological, nulls dropped).
List<SeriesPoint> buildSeries(List<HealthSample> samples, String metric) {
  final pts = <SeriesPoint>[];
  for (final s in samples) {
    final v = _pick(s, metric);
    if (v != null) pts.add(SeriesPoint(s.at, v));
  }
  pts.sort((a, b) => a.t.compareTo(b.t));
  return pts;
}

/// Bucket into at most [maxPoints] mean-averaged points (time-uniform buckets).
/// Keeps sparklines cheap and readable without dropping outliers wholesale.
List<SeriesPoint> downsampleMean(List<SeriesPoint> pts, int maxPoints) {
  if (maxPoints <= 0) return const [];
  if (pts.length <= maxPoints) return pts;
  final startMs = pts.first.t.millisecondsSinceEpoch;
  final endMs = pts.last.t.millisecondsSinceEpoch;
  final span = (endMs - startMs).clamp(1, 1 << 62);
  final bucketMs = span / maxPoints;

  final sums = List<double>.filled(maxPoints, 0);
  final counts = List<int>.filled(maxPoints, 0);
  final firstMs = List<int>.filled(maxPoints, 0);
  for (final p in pts) {
    var idx = ((p.t.millisecondsSinceEpoch - startMs) / bucketMs).floor();
    if (idx >= maxPoints) idx = maxPoints - 1;
    if (counts[idx] == 0) firstMs[idx] = p.t.millisecondsSinceEpoch;
    sums[idx] += p.value;
    counts[idx]++;
  }
  final out = <SeriesPoint>[];
  for (var i = 0; i < maxPoints; i++) {
    if (counts[i] == 0) continue;
    out.add(SeriesPoint(
      DateTime.fromMillisecondsSinceEpoch(firstMs[i], isUtc: true),
      sums[i] / counts[i],
    ));
  }
  return out;
}

SeriesStats? statsFor(List<SeriesPoint> pts, {double flatEps = 0.5}) {
  if (pts.isEmpty) return null;
  var min = pts.first.value, max = pts.first.value, sum = 0.0;
  for (final p in pts) {
    if (p.value < min) min = p.value;
    if (p.value > max) max = p.value;
    sum += p.value;
  }
  final latest = pts.last.value;
  final delta = latest - pts.first.value;
  final trend = delta.abs() <= flatEps ? Trend.flat : (delta > 0 ? Trend.up : Trend.down);
  return SeriesStats(latest, min, max, sum / pts.length, delta, trend);
}

/// Is the latest value in the danger zone? Drives the tile's alert styling.
bool latestInDanger(String metric, SeriesStats? stats) {
  if (stats == null) return false;
  final b = bandFor(metric);
  if (b.warnAbove != null && stats.latest >= b.warnAbove!) return true;
  if (b.warnBelow != null && stats.latest < b.warnBelow!) return true;
  return false;
}
