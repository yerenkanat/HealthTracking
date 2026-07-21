/// Menstrual cycle prediction (Flo-style) — PURE Dart, unit-testable via
/// `dart run tool/verify_cycle.dart`. Given the set of days the user logged a
/// period, it derives period-start days, the average cycle + period length, and
/// predicts the next period, the fertile window, and ovulation.
///
/// This is wellness estimation, NOT contraception guidance — predictions are
/// approximate and clearly labelled as such in the UI.
library;

import 'cycle_log.dart' show dateKey;

/// How a calendar day relates to the cycle, for colouring the month grid.
/// Priority (highest first): logged period → ovulation → fertile → predicted period.
enum CycleDayType { period, predictedPeriod, ovulation, fertile, none }

class CycleInfo {
  final int avgCycleLength; // days between period starts (clamped 21..35)
  final int avgPeriodLength; // bleeding days (clamped 2..8)
  final DateTime? lastPeriodStart;
  final DateTime? nextPeriodStart; // predicted, on/after today
  final DateTime? ovulation; // predicted (nextPeriodStart - 14)
  final DateTime? fertileStart;
  final DateTime? fertileEnd;
  final int? cycleDay; // 1-based day within the current cycle
  final bool hasData; // enough logs to predict
  final DateTime today; // anchor the prediction was computed against

  const CycleInfo({
    required this.avgCycleLength,
    required this.avgPeriodLength,
    required this.lastPeriodStart,
    required this.nextPeriodStart,
    required this.ovulation,
    required this.fertileStart,
    required this.fertileEnd,
    required this.cycleDay,
    required this.hasData,
    required this.today,
  });

  int? get daysUntilNextPeriod => nextPeriodStart?.difference(today).inDays;

  /// True when the user is currently within a predicted/logged period window.
  bool get isPredictedLate =>
      nextPeriodStart != null && daysUntilNextPeriod != null && daysUntilNextPeriod! < 0;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A day is a period START if it was logged and the previous day was not.
List<DateTime> periodStarts(Set<DateTime> periodDays) {
  final norm = {for (final d in periodDays) dateKey(d)};
  final sorted = periodDays.map(_dayOnly).toSet().toList()..sort();
  final starts = <DateTime>[];
  for (final d in sorted) {
    if (!norm.contains(dateKey(d.subtract(const Duration(days: 1))))) starts.add(d);
  }
  return starts;
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// A gap longer than this isn't a cycle — it's a stretch the user didn't log,
/// or several cycles rolled into one. Counting it as a single cycle length is
/// what let one break in logging distort every later prediction.
const int _maxPlausibleGapDays = 60;

/// How many recent cycles inform the estimate. Enough to be stable, few enough
/// that a real change in rhythm is not outvoted by old history.
const int _recentCyclesConsidered = 6;

/// Compute cycle info from logged [periodDays] relative to [today].
CycleInfo computeCycle(
  Set<DateTime> periodDays,
  DateTime today, {
  int defaultCycle = 28,
  int defaultPeriod = 5,
}) {
  final t = _dayOnly(today);
  final starts = periodStarts(periodDays);

  if (starts.isEmpty) {
    return CycleInfo(
      avgCycleLength: 28, avgPeriodLength: 5,
      lastPeriodStart: null, nextPeriodStart: null, ovulation: null,
      fertileStart: null, fertileEnd: null, cycleDay: null, hasData: false, today: t,
    );
  }

  // Typical cycle length from the gaps between consecutive starts.
  //
  // The MEDIAN of recent gaps, not the mean of all of them. A mean is wrecked
  // by a single outlier, and outliers here are ordinary life rather than rare:
  // one skipped period (stress, illness, travel) turned a true 28-day rhythm
  // into 35 — the clamp ceiling — so every prediction was a week late until
  // enough new data diluted it. Six months of not logging did the same.
  //
  // Gaps longer than [_maxPlausibleGapDays] are dropped before the median: a
  // gap that long is time the user didn't log, not a cycle they lived.
  //
  // Only the most recent cycles count, so a genuine change in rhythm shows up
  // instead of being outvoted by years of old history.
  // Clamped, not trusted. The settings slider is bounded 21-35, but this value
  // also arrives from a RESTORED BACKUP — a hand-editable JSON file we show the
  // user and encourage her to keep — and from any future caller. Unclamped, a
  // baseline of 1 predicts her next period today, every day; 999 predicts it in
  // three years. The derived-median path below already clamps; this is the path
  // taken when there is not yet enough logged history, which is exactly when a
  // new user is relying on the baseline.
  var avgCycle = _clamp(defaultCycle, 21, 35);
  final gaps = <int>[
    for (var i = 1; i < starts.length; i++) starts[i].difference(starts[i - 1]).inDays,
  ];
  final usable = gaps.where((g) => g > 0 && g <= _maxPlausibleGapDays).toList();
  final recent = usable.length > _recentCyclesConsidered
      ? usable.sublist(usable.length - _recentCyclesConsidered)
      : usable;
  if (recent.isNotEmpty) {
    recent.sort();
    final mid = recent.length ~/ 2;
    final median = recent.length.isOdd
        ? recent[mid]
        : ((recent[mid - 1] + recent[mid]) / 2).round();
    avgCycle = _clamp(median, 21, 35);
  }

  // Average period length: consecutive logged days from each start.
  final norm = {for (final d in periodDays) dateKey(d)};
  var periodSum = 0;
  for (final s in starts) {
    var len = 1;
    while (norm.contains(dateKey(s.add(Duration(days: len))))) {
      len++;
    }
    periodSum += len;
  }
  final avgPeriod = _clamp((periodSum / starts.length).round(), 2, 8);

  final lastStart = starts.last;

  // Next predicted start: roll forward from the last start until on/after today.
  //
  // The step is asserted positive rather than assumed. avgCycle is clamped
  // above, but this loop's termination should not depend on a guard several
  // lines away: with a step of zero or less it never exits, and the failure is
  // not a wrong prediction — it is the app hanging on the calendar screen.
  // That is exactly what happened when the clamp was removed to test it.
  final step = avgCycle < 1 ? 28 : avgCycle;
  var next = lastStart.add(Duration(days: step));
  while (next.isBefore(t)) {
    next = next.add(Duration(days: step));
  }
  final ovulation = next.subtract(const Duration(days: 14));
  final fertileStart = ovulation.subtract(const Duration(days: 5));
  final fertileEnd = ovulation.add(const Duration(days: 1));

  final cycleDay = t.isBefore(lastStart) ? null : t.difference(lastStart).inDays + 1;

  return CycleInfo(
    avgCycleLength: avgCycle,
    avgPeriodLength: avgPeriod,
    lastPeriodStart: lastStart,
    nextPeriodStart: next,
    ovulation: ovulation,
    fertileStart: fertileStart,
    fertileEnd: fertileEnd,
    cycleDay: cycleDay,
    hasData: true,
    today: t,
  );
}

bool _inRange(DateTime d, DateTime? start, DateTime? end) =>
    start != null && end != null && !d.isBefore(start) && !d.isAfter(end);

/// The four broad phases of the menstrual cycle. Educational framing over the
/// user's own predicted cycle — not a medical determination.
enum CyclePhase { menstrual, follicular, fertile, luteal }

/// Where today sits in the cycle: the [phase], the 1-based [dayInPhase], and the
/// approximate [phaseLength] in days. Returned by [cyclePhaseFor].
class CyclePhaseInfo {
  final CyclePhase phase;
  final int dayInPhase;
  final int phaseLength;
  const CyclePhaseInfo(this.phase, this.dayInPhase, this.phaseLength);
}

/// Where the fertile window sits relative to today.
enum FertileWindowState { upcoming, active, passed }

/// A countdown to (or within) the predicted fertile window. [daysToStart] is how
/// many days until the window opens (upcoming only); [daysToOvulation] is the
/// signed day distance to ovulation (0 = today, negative = already passed).
class FertileCountdown {
  final FertileWindowState state;
  final int daysToStart;
  final int daysToOvulation;
  const FertileCountdown(this.state, this.daysToStart, this.daysToOvulation);
}

/// Compute the fertile-window countdown from [info]. Null when the window can't
/// be predicted (not enough data).
FertileCountdown? fertileCountdown(CycleInfo info) {
  final fs = info.fertileStart, fe = info.fertileEnd, ov = info.ovulation;
  if (!info.hasData || fs == null || fe == null || ov == null) return null;
  final t = _dayOnly(info.today);
  final start = _dayOnly(fs), end = _dayOnly(fe), ovul = _dayOnly(ov);
  final toOv = ovul.difference(t).inDays;
  if (t.isBefore(start)) return FertileCountdown(FertileWindowState.upcoming, start.difference(t).inDays, toOv);
  if (!t.isAfter(end)) return FertileCountdown(FertileWindowState.active, 0, toOv);
  return FertileCountdown(FertileWindowState.passed, 0, toOv);
}

/// Classify the current phase from a computed [info]. Null when there isn't
/// enough data (no prediction, or today precedes the last period start).
/// Boundaries: menstrual = bleeding days; fertile = the predicted fertile window
/// (incl. ovulation); follicular = between period and fertile window; luteal =
/// after the fertile window up to the next period.
CyclePhaseInfo? cyclePhaseFor(CycleInfo info) {
  final start = info.lastPeriodStart;
  final day = info.cycleDay;
  if (!info.hasData || start == null || day == null || day < 1) return null;
  final t = _dayOnly(info.today);
  final s = _dayOnly(start);
  int cd(DateTime d) => _dayOnly(d).difference(s).inDays + 1; // 1-based cycle day
  final p = info.avgPeriodLength;

  // Menstrual: the bleeding days at the top of the cycle.
  if (day <= p) return CyclePhaseInfo(CyclePhase.menstrual, day, p);

  final fStart = info.fertileStart, fEnd = info.fertileEnd;
  // Fertile window (inclusive), when known.
  if (_inRange(t, fStart == null ? null : _dayOnly(fStart), fEnd == null ? null : _dayOnly(fEnd))) {
    final len = cd(fEnd!) - cd(fStart!) + 1;
    return CyclePhaseInfo(CyclePhase.fertile, day - cd(fStart) + 1, len);
  }
  // Follicular: after the period, before the fertile window opens.
  if (fStart != null && t.isBefore(_dayOnly(fStart))) {
    final len = (cd(fStart) - 1) - p; // days between end of period and fertile start
    return CyclePhaseInfo(CyclePhase.follicular, day - p, len < 1 ? 1 : len);
  }
  // Luteal: after the fertile window, up to the next period.
  final afterEnd = fEnd == null ? p : cd(fEnd);
  final cycleEnd = info.avgCycleLength; // next period starts at cycleEnd+1
  final len = cycleEnd - afterEnd;
  return CyclePhaseInfo(CyclePhase.luteal, day - afterEnd, len < 1 ? 1 : len);
}

/// Classify [day] for the calendar. [loggedPeriod] is whether the day itself has
/// a flow logged (checked by the caller from dayLogs).
CycleDayType cycleDayType(DateTime day, CycleInfo info, {required bool loggedPeriod}) {
  final d = _dayOnly(day);
  if (loggedPeriod) return CycleDayType.period;
  if (!info.hasData) return CycleDayType.none;
  if (info.ovulation != null && dateKey(d) == dateKey(info.ovulation!)) return CycleDayType.ovulation;
  if (_inRange(d, info.fertileStart, info.fertileEnd)) return CycleDayType.fertile;
  final next = info.nextPeriodStart;
  if (next != null && !d.isBefore(next) && d.isBefore(next.add(Duration(days: info.avgPeriodLength)))) {
    return CycleDayType.predictedPeriod;
  }
  return CycleDayType.none;
}
