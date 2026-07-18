/// Cycle insights — analytics over the user's OWN logged data (past cycle
/// lengths, period lengths, and how often each mood/symptom was logged). PURE
/// Dart → unit-testable via verify_cycle.dart. No medical content: just counts
/// and gaps over what the user recorded.
library;

import 'cycle_log.dart';
import 'cycle_predictions.dart' show periodStarts;

/// One recorded cycle: its start, how many days it ran to the next period start
/// ([cycleLength] — null for the most recent/ongoing cycle), and the bleeding
/// length ([periodLength]).
class CycleSpan {
  final DateTime start;
  final int? cycleLength;
  final int periodLength;
  const CycleSpan(this.start, this.cycleLength, this.periodLength);
}

String _key(DateTime d) => dateKey(d);

/// Past cycles, newest first, from the set of logged period days.
List<CycleSpan> cycleHistory(Set<DateTime> periodDays) {
  final starts = periodStarts(periodDays); // ascending
  if (starts.isEmpty) return const [];
  final normalized = {for (final d in periodDays) _key(d)};

  int periodLen(DateTime start) {
    var len = 1;
    while (normalized.contains(_key(start.add(Duration(days: len))))) {
      len++;
    }
    return len;
  }

  final spans = <CycleSpan>[];
  for (var i = 0; i < starts.length; i++) {
    final next = i + 1 < starts.length ? starts[i + 1] : null;
    final cycleLen = next?.difference(starts[i]).inDays;
    spans.add(CycleSpan(starts[i], cycleLen, periodLen(starts[i])));
  }
  return spans.reversed.toList(); // newest first
}

enum CycleRegularity { insufficient, regular, variable, irregular }

/// A read on how consistent the user's cycles are, over their completed cycles.
class RegularityInsight {
  final CycleRegularity level;
  final int cyclesConsidered; // completed cycles used (need ≥2 for a verdict)
  final int variationDays; // spread between the longest and shortest cycle
  final int avgCycle; // average completed cycle length (0 when insufficient)
  const RegularityInsight(this.level, this.cyclesConsidered, this.variationDays, this.avgCycle);
}

/// Classify cycle regularity from [history] (as returned by [cycleHistory]).
/// Needs ≥2 completed cycles; otherwise [CycleRegularity.insufficient]. The
/// spread (max − min) buckets it: ≤4 days regular, ≤8 variable, else irregular.
RegularityInsight cycleRegularity(List<CycleSpan> history) {
  final lengths = [for (final s in history) if (s.cycleLength != null) s.cycleLength!];
  if (lengths.length < 2) return RegularityInsight(CycleRegularity.insufficient, lengths.length, 0, 0);
  var min = lengths.first, max = lengths.first, sum = 0;
  for (final v in lengths) {
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
  }
  final variation = max - min;
  final level = variation <= 4
      ? CycleRegularity.regular
      : variation <= 8
          ? CycleRegularity.variable
          : CycleRegularity.irregular;
  return RegularityInsight(level, lengths.length, variation, (sum / lengths.length).round());
}

/// Count of each mood across the given day logs (descending by count).
List<({Mood mood, int count})> moodFrequency(Iterable<DayLog> logs) {
  final counts = <Mood, int>{};
  for (final l in logs) {
    if (l.mood != null) counts[l.mood!] = (counts[l.mood!] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (mood: e.key, count: e.value)];
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// Count of each symptom across the given day logs (descending by count).
List<({Symptom symptom, int count})> symptomFrequency(Iterable<DayLog> logs) {
  final counts = <Symptom, int>{};
  for (final l in logs) {
    for (final s in l.symptoms) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (symptom: e.key, count: e.value)];
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}
