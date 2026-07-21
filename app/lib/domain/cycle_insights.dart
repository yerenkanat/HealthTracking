/// Cycle insights — analytics over the user's OWN logged data (past cycle
/// lengths, period lengths, and how often each mood/symptom was logged). PURE
/// Dart → unit-testable via verify_cycle.dart. No medical content: just counts
/// and gaps over what the user recorded.
library;

import 'cycle_log.dart';
import 'cycle_predictions.dart' show CycleInfo, CyclePhase, cyclePhaseFor, periodStarts;

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
    while (normalized.contains(_key(addDays(start, len)))) {
      len++;
    }
    return len;
  }

  final spans = <CycleSpan>[];
  for (var i = 0; i < starts.length; i++) {
    final next = i + 1 < starts.length ? starts[i + 1] : null;
    final cycleLen = next == null ? null : daysBetween(starts[i], next);
    spans.add(CycleSpan(starts[i], cycleLen, periodLen(starts[i])));
  }
  return spans.reversed.toList(); // newest first
}

/// Min / average / max over the user's COMPLETED cycle lengths, with the count
/// considered. Null when there are no completed cycles yet.
class CycleLengthStats {
  final int count;
  final int min;
  final int max;
  final int avg;
  const CycleLengthStats(this.count, this.min, this.max, this.avg);
}

/// Compute length stats from [history] (as returned by [cycleHistory]). Null if
/// no cycle has a recorded length (i.e. only the ongoing cycle exists).
CycleLengthStats? cycleLengthStats(List<CycleSpan> history) {
  final lengths = [for (final s in history) if (s.cycleLength != null) s.cycleLength!];
  if (lengths.isEmpty) return null;
  var min = lengths.first, max = lengths.first, sum = 0;
  for (final v in lengths) {
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
  }
  return CycleLengthStats(lengths.length, min, max, (sum / lengths.length).round());
}

/// How much to trust the cycle predictions, given how much history backs them.
///
/// [variable] is separate from [building] on purpose. Both mean "this date is
/// approximate", but they mean opposite things about what to do next:
/// `building` says keep logging and it will sharpen, `variable` says there is
/// plenty of history and her cycles genuinely differ from each other.
///
/// They were one value, so a woman whose cycles run 24 to 42 days — a year of
/// diligent logging — was told indefinitely that confidence was still
/// "building". That reads as a promise the app cannot keep: more logging was
/// never going to improve it, because the spread is a fact about her body
/// rather than a gap in the data. Irregular cycles are common enough (PCOS
/// alone is around one woman in ten) that this is not an edge case.
enum PredictionConfidence { low, building, variable, good }

/// Confidence from the number of COMPLETED cycles and how much their lengths
/// vary. No completed cycles → low (predictions use defaults); under three →
/// still building; three or more → good, unless the spread is wide (>8 days),
/// which keeps it at building.
PredictionConfidence predictionConfidence({required int completedCycles, required int variationDays}) {
  if (completedCycles <= 0) return PredictionConfidence.low;
  // Too little history yet — this genuinely does improve with logging.
  if (completedCycles < 3) return PredictionConfidence.building;
  // Enough history, and the cycles disagree with each other. More logging will
  // not narrow this, so say what it is instead of promising it will improve.
  // The 8-day spread is the same boundary cycleRegularity() calls irregular.
  return variationDays > 8 ? PredictionConfidence.variable : PredictionConfidence.good;
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

/// Consecutive days (ending [today]) with any non-empty day log. A not-yet-logged
/// today doesn't break the streak — it counts from yesterday; a missed earlier day
/// ends it.
int loggingStreak(Iterable<DayLog> logs, DateTime today) {
  final logged = {for (final l in logs) if (l.isNotEmpty) l.date};
  bool has(DateTime d) => logged.contains(dateKey(d));
  final t = DateTime(today.year, today.month, today.day);
  var day = has(t) ? t : addDays(t, -1);
  var streak = 0;
  while (has(day)) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}

/// Days whose note matches [query] (case-insensitive substring; empty query =
/// all notes), most recent first.
List<DayLog> searchNotes(Iterable<DayLog> logs, String query) {
  final q = query.trim().toLowerCase();
  final matches = [
    for (final l in logs)
      if (l.note.trim().isNotEmpty && (q.isEmpty || l.note.toLowerCase().contains(q))) l
  ];
  matches.sort((a, b) => b.date.compareTo(a.date)); // dateKey sorts chronologically
  return matches;
}

/// The days that carry a free-text note, most recent first (up to [limit]).
List<DayLog> recentNotes(Iterable<DayLog> logs, {int limit = 5}) =>
    searchNotes(logs, '').take(limit).toList();

/// Mood counts restricted to logs on/after [since] (a recent window). Descending.
List<({Mood mood, int count})> moodFrequencySince(Iterable<DayLog> logs, DateTime since) {
  final sinceKey = dateKey(since);
  return moodFrequency([for (final l in logs) if (l.date.compareTo(sinceKey) >= 0) l]);
}

/// One week in the mood trend: the week's end date, its dominant (most-logged)
/// mood ([mood] — null if nothing was logged that week), and how many days that
/// dominant mood was logged.
class MoodWeek {
  final DateTime weekEnd;
  final Mood? mood;
  final int count;
  const MoodWeek(this.weekEnd, this.mood, this.count);
}

/// The dominant mood for each of the last [weeks] 7-day windows ending on
/// [today], oldest week first. Ties resolve to the mood seen first in
/// [Mood.values]. Weeks with no mood logged have a null [mood].
List<MoodWeek> moodTrend(Iterable<DayLog> logs, DateTime today, {int weeks = 6}) {
  final t = DateTime(today.year, today.month, today.day);
  final buckets = List.generate(weeks, (_) => <Mood, int>{});
  for (final l in logs) {
    if (l.mood == null) continue;
    final d = dateFromKey(l.date);
    if (d == null) continue;
    final diff = daysBetween(DateTime(d.year, d.month, d.day), t);
    if (diff < 0 || diff >= weeks * 7) continue;
    final b = diff ~/ 7;
    buckets[b][l.mood!] = (buckets[b][l.mood!] ?? 0) + 1;
  }
  final out = <MoodWeek>[];
  for (var i = weeks - 1; i >= 0; i--) {
    final counts = buckets[i];
    Mood? top;
    var topN = 0;
    for (final m in Mood.values) {
      final n = counts[m] ?? 0;
      if (n > topN) {
        topN = n;
        top = m;
      }
    }
    out.add(MoodWeek(addDays(t, -7 * i), top, topN));
  }
  return out;
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

/// Symptom counts restricted to logs on/after [since] (a recent window, e.g. the
/// last 7 days). Descending by count.
List<({Symptom symptom, int count})> symptomFrequencySince(Iterable<DayLog> logs, DateTime since) {
  final sinceKey = dateKey(since);
  return symptomFrequency([for (final l in logs) if (l.date.compareTo(sinceKey) >= 0) l]);
}

int _clampi(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// The cycle phase a historical [date] fell in, based on the cycle that CONTAINS
/// it (the period start on/before the date, running to the next start). Null when
/// the date precedes all logged periods. Reuses the verified [cyclePhaseFor]
/// classification against a reconstructed cycle.
CyclePhase? phaseOfLoggedDay(DateTime date, Set<DateTime> periodDays) {
  final starts = periodStarts(periodDays); // ascending
  if (starts.isEmpty) return null;
  final d = DateTime(date.year, date.month, date.day);

  // The containing cycle's start (greatest start ≤ date) and the following start.
  DateTime? s;
  DateTime? next;
  for (final st in starts) {
    if (!st.isAfter(d)) {
      s = st;
    } else {
      next = st;
      break;
    }
  }
  if (s == null) return null; // date is before any logged period

  final cycleLen = _clampi(next != null ? daysBetween(s, next) : 28, 21, 35);
  // Bleeding length: consecutive logged days from the start.
  final norm = {for (final pd in periodDays) dateKey(pd)};
  var periodLen = 1;
  while (norm.contains(dateKey(addDays(s, periodLen)))) {
    periodLen++;
  }
  final ovulation = addDays(s, cycleLen - 14);
  final info = CycleInfo(
    avgCycleLength: cycleLen,
    avgPeriodLength: _clampi(periodLen, 2, 8),
    lastPeriodStart: s,
    nextPeriodStart: addDays(s, cycleLen),
    ovulation: ovulation,
    fertileStart: addDays(ovulation, -5),
    fertileEnd: addDays(ovulation, 1),
    cycleDay: daysBetween(s, d) + 1,
    hasData: true,
    today: d,
  );
  return cyclePhaseFor(info)?.phase;
}

/// Which phase a symptom clusters in: the [symptom], the [phase] it was logged in
/// most, the [count] there, and the [total] placeable occurrences.
class SymptomPhaseInsight {
  final Symptom symptom;
  final CyclePhase phase;
  final int count;
  final int total;
  const SymptomPhaseInsight(this.symptom, this.phase, this.count, this.total);
}

/// For the user's most-logged symptom, which cycle phase it most often appears
/// in. Null when there's no symptom data, no period data, or nothing placeable.
SymptomPhaseInsight? topSymptomPhase(Iterable<DayLog> logs, Set<DateTime> periodDays) {
  final freq = symptomFrequency(logs);
  if (freq.isEmpty || periodDays.isEmpty) return null;
  final symptom = freq.first.symptom;

  final counts = <CyclePhase, int>{};
  var total = 0;
  for (final l in logs) {
    if (!l.symptoms.contains(symptom)) continue;
    final d = dateFromKey(l.date);
    if (d == null) continue;
    final phase = phaseOfLoggedDay(d, periodDays);
    if (phase == null) continue;
    counts[phase] = (counts[phase] ?? 0) + 1;
    total++;
  }
  if (total == 0) return null;

  CyclePhase? top;
  var topN = 0;
  for (final phase in CyclePhase.values) {
    final n = counts[phase] ?? 0;
    if (n > topN) {
      topN = n;
      top = phase;
    }
  }
  return top == null ? null : SymptomPhaseInsight(symptom, top, topN, total);
}

/// Symptoms the user has historically logged during [phase], most frequent
/// first. The inverse view of [topSymptomPhase]: given a phase, which symptoms
/// show up — used for a forward-looking "around now you often log…" heads-up.
List<({Symptom symptom, int count})> symptomsInPhase(
  Iterable<DayLog> logs,
  Set<DateTime> periodDays,
  CyclePhase phase,
) {
  final counts = <Symptom, int>{};
  for (final l in logs) {
    if (l.symptoms.isEmpty) continue;
    final d = dateFromKey(l.date);
    if (d == null) continue;
    if (phaseOfLoggedDay(d, periodDays) != phase) continue;
    for (final s in l.symptoms) {
      if (s == Symptom.allGood) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
  }
  final out = [for (final e in counts.entries) (symptom: e.key, count: e.value)];
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// The days on which [symptom] was logged, most recent first.
List<DayLog> daysWithSymptom(Iterable<DayLog> logs, Symptom symptom) {
  final matches = [for (final l in logs) if (l.symptoms.contains(symptom)) l];
  matches.sort((a, b) => b.date.compareTo(a.date)); // dateKey sorts chronologically
  return matches;
}

/// How many days were logged at each flow intensity, in [Flow.values] order
/// (light → heavy). Days without a flow are ignored. Always returns one entry
/// per level (count 0 when unseen) so the UI can render a stable breakdown.
List<({Flow flow, int count})> flowBreakdown(Iterable<DayLog> logs) {
  final counts = <Flow, int>{};
  for (final l in logs) {
    final f = l.flow;
    if (f != null) counts[f] = (counts[f] ?? 0) + 1;
  }
  return [for (final f in Flow.values) (flow: f, count: counts[f] ?? 0)];
}

/// Total days with any flow logged.
int totalFlowDays(Iterable<DayLog> logs) {
  var n = 0;
  for (final l in logs) {
    if (l.flow != null) n++;
  }
  return n;
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
