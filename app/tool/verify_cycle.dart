/// Pure-Dart verification of women's-health day logging + gestation math.
/// `dart run tool/verify_cycle.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/cycle_predictions.dart';

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

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
