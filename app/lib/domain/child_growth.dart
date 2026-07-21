/// The child's growth: weight and height over time.
///
/// PURE Dart → verified by tool/verify_child_growth.dart.
///
/// WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT
///
/// It plots what the parent measured, and reports the change between
/// measurements. That is genuinely useful: a parent leaves the polyclinic with
/// two numbers on a slip of paper and nowhere to put them, and "gained 600 g
/// since last month" is the thing they actually want to know.
///
/// It does NOT draw WHO percentile bands, and that is a decision rather than an
/// omission. Percentiles come from the WHO's published LMS tables — a
/// three-parameter distribution per sex per day of age — and the honest way to
/// have them is to import that data file, not to type approximate numbers from
/// memory into a medical chart. A band that is 300 g off tells a mother her
/// healthy child is underweight.
///
/// See docs/INTEGRATION_STATUS.md for what adding them properly involves. Until
/// then this screen shows her child against her child, which is a comparison
/// the app can actually stand behind.
library;

import 'cycle_log.dart' show dateKey, daysBetween;

/// One visit's measurements. Either value may be absent — clinics do not always
/// record both, and a height-only visit should not be unrepresentable.
class GrowthPoint {
  final DateTime at;
  final double? weightKg;
  final double? heightCm;

  const GrowthPoint({required this.at, this.weightKg, this.heightCm});

  bool get isEmpty => weightKg == null && heightCm == null;

  /// Day key, so one visit per day replaces rather than duplicates.
  String get key => dateKey(at);

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        if (weightKg != null) 'weightKg': weightKg,
        if (heightCm != null) 'heightCm': heightCm,
      };

  /// Throws on an unusable row, so the tolerant list parser drops that visit
  /// rather than the whole child — the same contract every other entry here
  /// follows.
  factory GrowthPoint.fromJson(Map<String, dynamic> j) {
    final at = DateTime.parse(j['at'] as String);
    final w = (j['weightKg'] as num?)?.toDouble();
    final h = (j['heightCm'] as num?)?.toDouble();
    if (w == null && h == null) throw const FormatException('growth point with no measurement');
    if (w != null && !isPlausibleWeight(w)) throw FormatException('implausible weight $w');
    if (h != null && !isPlausibleHeight(h)) throw FormatException('implausible height $h');
    return GrowthPoint(at: at, weightKg: w, heightCm: h);
  }
}

/// Bounds on what a measurement can be.
///
/// Not a medical judgement — a typo filter. 100 kg in the weight field of a
/// baby's record is a slipped decimal point, and storing it would wreck the
/// chart's scale and every "gained since last time" below it.
const growthWeightMinKg = 0.3;
const growthWeightMaxKg = 60.0;
const growthHeightMinCm = 20.0;
const growthHeightMaxCm = 160.0;

bool isPlausibleWeight(double kg) =>
    kg.isFinite && kg >= growthWeightMinKg && kg <= growthWeightMaxKg;
bool isPlausibleHeight(double cm) =>
    cm.isFinite && cm >= growthHeightMinCm && cm <= growthHeightMaxCm;

/// Add or replace a measurement, keeping the list sorted oldest-first.
///
/// One point per DAY: a parent correcting a typo should end up with a corrected
/// figure, not two conflicting ones an hour apart.
List<GrowthPoint> upsertGrowth(List<GrowthPoint> points, GrowthPoint p) {
  if (p.isEmpty) return points;
  final out = [for (final e in points) if (e.key != p.key) e]..add(p);
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

List<GrowthPoint> removeGrowthOn(List<GrowthPoint> points, DateTime day) =>
    [for (final e in points) if (e.key != dateKey(day)) e];

/// Points that carry a weight, oldest first.
List<GrowthPoint> weightSeries(List<GrowthPoint> points) =>
    [for (final p in points) if (p.weightKg != null) p];

/// Points that carry a height, oldest first.
List<GrowthPoint> heightSeries(List<GrowthPoint> points) =>
    [for (final p in points) if (p.heightCm != null) p];

/// Change since the previous measurement of the same kind.
///
/// Null when there is nothing to compare against — the first visit has no
/// "since last time", and saying "+0" there would read as no growth rather
/// than no data.
({double delta, int days})? weightChange(List<GrowthPoint> points) {
  final s = weightSeries(points);
  if (s.length < 2) return null;
  final last = s[s.length - 1], prev = s[s.length - 2];
  return (
    delta: last.weightKg! - prev.weightKg!,
    days: daysBetween(prev.at, last.at),
  );
}

({double delta, int days})? heightChange(List<GrowthPoint> points) {
  final s = heightSeries(points);
  if (s.length < 2) return null;
  final last = s[s.length - 1], prev = s[s.length - 2];
  return (
    delta: last.heightCm! - prev.heightCm!,
    days: daysBetween(prev.at, last.at),
  );
}

/// Min and max of a series, padded, for a chart axis.
///
/// Padded because a flat series would otherwise collapse to a zero-height axis
/// and divide by zero; and because a line drawn hard against the top and bottom
/// of its box reads as clipped.
({double min, double max}) axisFor(List<double> values) {
  if (values.isEmpty) return (min: 0, max: 1);
  var lo = values.first, hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi - lo < 0.001) {
    // A single point, or several identical ones.
    return (min: lo - 1, max: hi + 1);
  }
  final pad = (hi - lo) * 0.15;
  return (min: lo - pad, max: hi + pad);
}
