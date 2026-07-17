/// Pure-Dart verification of the shareable cycle summary builder.
/// `dart run tool/verify_cycle_summary.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_predictions.dart';
import '../lib/l10n/l10n.dart';
import '../lib/ui/calendar/cycle_summary.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

// Deterministic, locale-free date formatter for testing.
String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  const l = L10n(AppLocale.en);

  // Two logged cycles ~28 days apart → hasData, predicts forward.
  final periodDays = <DateTime>{
    DateTime(2026, 6, 1), DateTime(2026, 6, 2), DateTime(2026, 6, 3),
    DateTime(2026, 6, 29), DateTime(2026, 6, 30), DateTime(2026, 7, 1),
  };
  final info = computeCycle(periodDays, DateTime(2026, 7, 15));
  final s = buildCycleSummary(l, info, formatDate: _fmt);

  _chk('has title', s.contains('Cycle forecast'));
  _chk('next period line', s.contains('Next period:') && s.contains(_fmt(info.nextPeriodStart!)));
  _chk('fertile window line', s.contains('Fertile') && s.contains('–'));
  _chk('ovulation line', s.contains('Ovulation:') && s.contains(_fmt(info.ovulation!)));
  _chk('avg cycle line', s.contains('${info.avgCycleLength}'));
  _chk('has disclaimer', s.contains('not contraception guidance'));

  // No data → graceful fallback + still disclaimed.
  final empty = computeCycle(const <DateTime>{}, DateTime(2026, 7, 15));
  final es = buildCycleSummary(l, empty, formatDate: _fmt);
  _chk('empty → not-enough-data line', es.contains('Not enough data'));
  _chk('empty → no next-period line', !es.contains('Next period:'));
  _chk('empty → still disclaimed', es.contains('not contraception guidance'));

  // Russian localization.
  const ru = L10n(AppLocale.ru);
  final rs = buildCycleSummary(ru, info, formatDate: _fmt);
  _chk('ru title', rs.contains('Прогноз цикла'));
  _chk('ru next-period label', rs.contains('Следующие месячные:'));
  _chk('ru disclaimer', rs.contains('не средство контрацепции'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
