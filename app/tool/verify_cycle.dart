/// Pure-Dart verification of women's-health day logging + gestation math.
/// `dart run tool/verify_cycle.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/cycle_predictions.dart';
import '../lib/domain/cycle_insights.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Date keys ----
  _chk('dateKey pads month/day', dateKey(DateTime(2026, 3, 5)) == '2026-03-05');
  _chk('dateFromKey round-trip', dateFromKey('2026-03-05') == DateTime(2026, 3, 5));
  _chk('dateFromKey rejects junk', dateFromKey('nope') == null);
  _chk('isSameDay ignores time',
      isSameDay(DateTime(2026, 3, 5, 8), DateTime(2026, 3, 5, 22)) && !isSameDay(DateTime(2026, 3, 5), DateTime(2026, 3, 6)));

  // ---- Empty log ----
  const empty = DayLog(date: '2026-03-05');
  _chk('empty log isEmpty', empty.isEmpty && !empty.isNotEmpty);

  // ---- Mood toggle ----
  final happy = empty.withMoodToggled(Mood.happy);
  _chk('mood set', happy.mood == Mood.happy && happy.isNotEmpty);
  _chk('mood re-toggle clears', happy.withMoodToggled(Mood.happy).mood == null);
  _chk('mood switch replaces', happy.withMoodToggled(Mood.tired).mood == Mood.tired);

  // ---- Symptom toggle ----
  final cramps = empty.toggleSymptom(Symptom.cramps);
  _chk('symptom add', cramps.symptoms.contains(Symptom.cramps));
  _chk('symptom remove', cramps.toggleSymptom(Symptom.cramps).symptoms.isEmpty);
  final two = cramps.toggleSymptom(Symptom.headache);
  _chk('multiple symptoms', two.symptoms.length == 2);
  // "All good" is exclusive both ways.
  _chk('allGood clears others', two.toggleSymptom(Symptom.allGood).symptoms.toSet().length == 1 &&
      two.toggleSymptom(Symptom.allGood).symptoms.contains(Symptom.allGood));
  final allGood = empty.toggleSymptom(Symptom.allGood);
  _chk('real symptom clears allGood',
      allGood.toggleSymptom(Symptom.spotting).symptoms.contains(Symptom.spotting) &&
          !allGood.toggleSymptom(Symptom.spotting).symptoms.contains(Symptom.allGood));
  _chk('allGood re-toggle clears', allGood.toggleSymptom(Symptom.allGood).symptoms.isEmpty);

  // ---- Kicks ----
  final k = empty.addKick().addKick().addKick();
  _chk('kicks accumulate', k.kicks == 3 && k.isNotEmpty);
  _chk('kicks reset', k.resetKicks().kicks == 0);
  _chk('kicks clamp at 0', empty.copyWith(kicks: 0).addKick(-5).kicks == 0);

  // ---- Round-trip ----
  final rich = empty.withMoodToggled(Mood.calm).toggleSymptom(Symptom.nausea).addKick().addKick();
  final back = DayLog.fromJson(rich.toJson());
  _chk('log round-trip mood', back.mood == Mood.calm);
  _chk('log round-trip symptoms', back.symptoms.contains(Symptom.nausea));
  _chk('log round-trip kicks', back.kicks == 2);
  _chk('logbook round-trip drops empties',
      dayLogsFromJson(dayLogsToJson({'a': rich, 'b': empty})).length == 1);

  // ---- Gestation math ----
  final today = DateTime(2026, 7, 15);
  _chk('gestation null without due date', gestationFor(null, today) == null);
  // Due in 112 days → 280-112 = 168 gestational days = 24w0d.
  final g = gestationFor(today.add(const Duration(days: 112)), today)!;
  _chk('gestation week 24', g.week == 24 && g.dayOfWeek == 0);
  _chk('gestation daysUntilDue', g.daysUntilDue == 112);
  _chk('gestation progress 0..1', g.progress > 0.5 && g.progress < 0.65);
  _chk('gestation trimester 2', g.trimester == 2);
  // 24w3d → due in 109 days.
  final g2 = gestationFor(today.add(const Duration(days: 109)), today)!;
  _chk('gestation 24w3d', g2.week == 24 && g2.dayOfWeek == 3);
  // Overdue clamps, daysUntilDue negative.
  final over = gestationFor(today.subtract(const Duration(days: 5)), today)!;
  _chk('gestation overdue negative', over.daysUntilDue == -5 && over.progress == 1.0);
  // Mistyped far-future date clamps at 0.
  final clampLow = gestationFor(today.add(const Duration(days: 400)), today)!;
  _chk('gestation clamps low', clampLow.totalDays == 0 && clampLow.week == 0);

  // ---- Flow on DayLog ----
  final period = empty.withFlowToggled(Flow.medium);
  _chk('flow set', period.flow == Flow.medium && period.hasPeriod && period.isNotEmpty);
  _chk('flow re-toggle clears', period.withFlowToggled(Flow.medium).flow == null);
  _chk('flow switch replaces', period.withFlowToggled(Flow.heavy).flow == Flow.heavy);
  _chk('flow round-trip', DayLog.fromJson(period.toJson()).flow == Flow.medium);

  // ---- Cycle predictions ----
  Set<DateTime> periodSet(List<DateTime> ds) => ds.toSet();
  // No data → no prediction.
  _chk('no period data → hasData false', !computeCycle({}, DateTime(2026, 7, 15)).hasData);

  // Two 28-day cycles: starts Jun 3 and Jul 1, each 5 days.
  final days = <DateTime>[
    for (var i = 0; i < 5; i++) DateTime(2026, 6, 3).add(Duration(days: i)),
    for (var i = 0; i < 5; i++) DateTime(2026, 7, 1).add(Duration(days: i)),
  ];
  final info = computeCycle(periodSet(days), DateTime(2026, 7, 15));
  _chk('period starts detected', periodStarts(periodSet(days)).length == 2);
  _chk('avg cycle 28', info.avgCycleLength == 28);
  _chk('avg period 5', info.avgPeriodLength == 5);
  _chk('last start Jul 1', info.lastPeriodStart == DateTime(2026, 7, 1));
  _chk('next start Jul 29', info.nextPeriodStart == DateTime(2026, 7, 29));
  _chk('days until next = 14', info.daysUntilNextPeriod == 14);
  _chk('ovulation Jul 15', info.ovulation == DateTime(2026, 7, 15));
  _chk('cycle day 15', info.cycleDay == 15);
  _chk('fertile window Jul 10..16',
      info.fertileStart == DateTime(2026, 7, 10) && info.fertileEnd == DateTime(2026, 7, 16));

  // Day classification.
  _chk('logged day → period', cycleDayType(DateTime(2026, 7, 2), info, loggedPeriod: true) == CycleDayType.period);
  _chk('ovulation day type', cycleDayType(DateTime(2026, 7, 15), info, loggedPeriod: false) == CycleDayType.ovulation);
  _chk('fertile day type', cycleDayType(DateTime(2026, 7, 12), info, loggedPeriod: false) == CycleDayType.fertile);
  _chk('predicted period type', cycleDayType(DateTime(2026, 7, 30), info, loggedPeriod: false) == CycleDayType.predictedPeriod);
  _chk('ordinary day → none', cycleDayType(DateTime(2026, 7, 20), info, loggedPeriod: false) == CycleDayType.none);

  // ---- Cycle insights (history + frequencies) ----
  final hist = cycleHistory(periodSet(days));
  _chk('two cycles in history', hist.length == 2);
  _chk('newest cycle first (Jul 1, ongoing)', hist.first.start == DateTime(2026, 7, 1) && hist.first.cycleLength == null);
  _chk('older cycle length 28', hist.last.start == DateTime(2026, 6, 3) && hist.last.cycleLength == 28);
  _chk('period length 5', hist.first.periodLength == 5);
  _chk('empty history', cycleHistory({}).isEmpty);

  final logs = [
    const DayLog(date: '2026-07-01', mood: Mood.happy, symptoms: {Symptom.cramps}),
    const DayLog(date: '2026-07-02', mood: Mood.happy, symptoms: {Symptom.cramps, Symptom.headache}),
    const DayLog(date: '2026-07-03', mood: Mood.tired, symptoms: {Symptom.cramps}),
  ];
  final mf = moodFrequency(logs);
  _chk('mood frequency ranks happy first', mf.first.mood == Mood.happy && mf.first.count == 2);
  final sf = symptomFrequency(logs);
  _chk('symptom frequency ranks cramps first', sf.first.symptom == Symptom.cramps && sf.first.count == 3);
  _chk('symptom frequency includes headache', sf.any((e) => e.symptom == Symptom.headache && e.count == 1));

  // ---- Cycle regularity ----
  RegularityInsight reg(List<int?> cycleLengths) => cycleRegularity(
      [for (final c in cycleLengths) CycleSpan(DateTime(2026, 1, 1), c, 5)]);
  _chk('insufficient with <2 completed', reg([28, null]).level == CycleRegularity.insufficient);
  final regular = reg([28, 29, 27, null]);
  _chk('regular when spread ≤4', regular.level == CycleRegularity.regular && regular.variationDays == 2);
  _chk('regular avg cycle', regular.avgCycle == 28 && regular.cyclesConsidered == 3);
  _chk('variable when spread 5..8', reg([26, 32, null]).level == CycleRegularity.variable);
  _chk('irregular when spread >8', reg([24, 40]).level == CycleRegularity.irregular);

  // ---- Recent notes ----
  final noteLogs = [
    const DayLog(date: '2026-07-01', note: 'first scan'),
    const DayLog(date: '2026-07-05', note: '  '), // blank → excluded
    const DayLog(date: '2026-07-10', note: 'felt tired'),
    const DayLog(date: '2026-07-03', mood: Mood.happy), // no note → excluded
    const DayLog(date: '2026-07-08', note: 'good day'),
  ];
  final notes = recentNotes(noteLogs);
  _chk('recent notes excludes blank/none', notes.length == 3);
  _chk('recent notes newest first', notes.first.date == '2026-07-10' && notes.last.date == '2026-07-01');
  _chk('recent notes respects limit', recentNotes(noteLogs, limit: 2).length == 2);
  _chk('recent notes empty when none', recentNotes(const [DayLog(date: '2026-07-01')]).isEmpty);

  // ---- Symptom frequency within a recent window ----
  final windowLogs = [
    const DayLog(date: '2026-07-01', symptoms: {Symptom.cramps}), // old
    const DayLog(date: '2026-07-14', symptoms: {Symptom.cramps, Symptom.nausea}), // in window
    const DayLog(date: '2026-07-16', symptoms: {Symptom.cramps}), // in window
  ];
  final since = DateTime(2026, 7, 10);
  final recent = symptomFrequencySince(windowLogs, since);
  _chk('recent symptom counts exclude old logs', recent.first.symptom == Symptom.cramps && recent.first.count == 2);
  _chk('recent symptoms include in-window nausea', recent.any((e) => e.symptom == Symptom.nausea && e.count == 1));
  _chk('recent window boundary is inclusive', symptomFrequencySince([const DayLog(date: '2026-07-10', symptoms: {Symptom.cramps})], since).length == 1);
  _chk('recent window empty when all older', symptomFrequencySince([const DayLog(date: '2026-07-01', symptoms: {Symptom.cramps})], since).isEmpty);

  // ---- Mood frequency within a recent window ----
  final moodWindow = [
    const DayLog(date: '2026-07-02', mood: Mood.sad), // old
    const DayLog(date: '2026-07-14', mood: Mood.happy), // in window
    const DayLog(date: '2026-07-16', mood: Mood.happy), // in window
  ];
  final recentMoods = moodFrequencySince(moodWindow, since);
  _chk('recent mood counts exclude old', recentMoods.first.mood == Mood.happy && recentMoods.first.count == 2);
  _chk('recent mood excludes out-of-window', !recentMoods.any((e) => e.mood == Mood.sad));

  // ---- Logging streak ----
  final t = DateTime(2026, 7, 16);
  List<DayLog> logged(List<int> daysAgo) =>
      [for (final d in daysAgo) DayLog(date: dateKey(t.subtract(Duration(days: d))), mood: Mood.happy)];
  _chk('streak counts consecutive incl today', loggingStreak(logged([0, 1, 2]), t) == 3);
  _chk('streak stops at a gap', loggingStreak(logged([0, 1, 3]), t) == 2);
  _chk('pending today counts from yesterday', loggingStreak(logged([1, 2, 3]), t) == 3);
  _chk('empty logs → 0 streak', loggingStreak(const [], t) == 0);
  _chk('empty day log does not count', loggingStreak([DayLog(date: dateKey(t))], t) == 0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
