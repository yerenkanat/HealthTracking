/// Weight tracking — the mother's weight log over pregnancy. One entry per day
/// (kilograms); logging the same day again replaces it. PURE Dart + JSON round-
/// trip → unit-testable via verify_weight.dart. No medical targets live here; it
/// just stores and summarizes the trend.
library;

import 'cycle_log.dart' show dateKey, dateFromKey;

const double minWeightKg = 30;
const double maxWeightKg = 200;

class WeightEntry {
  final String date; // dateKey (yyyy-mm-dd)
  final double kg;
  const WeightEntry({required this.date, required this.kg});

  DateTime? get day => dateFromKey(date);

  Map<String, dynamic> toJson() => {'date': date, 'kg': kg};

  factory WeightEntry.fromJson(Map<String, dynamic> j) =>
      WeightEntry(date: j['date'] as String, kg: (j['kg'] as num).toDouble());
}

/// Upsert [kg] for [day] into [entries] (replacing any same-day entry), returning
/// a new chronological list. Clamps the value to a sane range.
List<WeightEntry> upsertWeight(List<WeightEntry> entries, DateTime day, double kg) {
  final key = dateKey(day);
  final clamped = kg < minWeightKg ? minWeightKg : (kg > maxWeightKg ? maxWeightKg : kg);
  final out = [
    for (final e in entries)
      if (e.date != key) e,
    WeightEntry(date: key, kg: clamped),
  ];
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Remove the entry for [dateKey] (if any), returning a new list.
List<WeightEntry> removeWeight(List<WeightEntry> entries, String dateKeyToRemove) =>
    [for (final e in entries) if (e.date != dateKeyToRemove) e];

class WeightStats {
  final double latest;
  final double first;
  final double min;
  final double max;
  final int count;
  const WeightStats(this.latest, this.first, this.min, this.max, this.count);

  /// Change since the first recorded entry (can be negative).
  double get delta => latest - first;
}

/// Remaining distance to a target weight (target − latest). Positive = still to
/// gain, negative = above the target.
double weightRemaining(double latest, double target) => target - latest;

/// Whether the latest weight has reached the target (within 0.05 kg).
bool weightTargetReached(double latest, double target) => (target - latest) <= 0.05;

/// Summary over the (assumed sorted) [entries], or null when empty.
WeightStats? computeWeightStats(List<WeightEntry> entries) {
  if (entries.isEmpty) return null;
  var min = entries.first.kg, max = entries.first.kg;
  for (final e in entries) {
    if (e.kg < min) min = e.kg;
    if (e.kg > max) max = e.kg;
  }
  return WeightStats(entries.last.kg, entries.first.kg, min, max, entries.length);
}
