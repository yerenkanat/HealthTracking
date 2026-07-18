/// Pure-Dart verification of the shareable health summary builder.
/// `dart run tool/verify_summary.dart`
library;

import 'dart:io';
import '../lib/domain/health_series.dart';
import '../lib/domain/sleep.dart';
import '../lib/l10n/l10n.dart';
import '../lib/ui/dashboard/health_summary.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

List<HealthSample> _samples() {
  final base = DateTime(2026, 7, 15, 8);
  return [
    for (var i = 0; i < 6; i++)
      HealthSample(
        at: base.add(Duration(minutes: i * 10)),
        heartRate: 78 + i.toDouble(),
        spo2: 98,
        systolic: 118 + i.toDouble(),
        diastolic: 76,
        coreTemp: 36.6,
      ),
  ];
}

void main() {
  const l = L10n(AppLocale.en);
  final samples = _samples();
  final nights = [
    SleepSummary(night: DateTime(2026, 7, 15), deepMin: 90, remMin: 110, lightMin: 250, awakeMin: 20),
  ];

  final s = buildHealthSummary(l, samples, nights: nights, name: 'Aizhan');
  _chk('has title', s.contains('Health summary'));
  _chk('includes name', s.contains('Aizhan'));
  _chk('heart rate row', s.contains('Heart rate:') && s.contains('bpm'));
  _chk('blood oxygen row', s.contains('Blood oxygen:') && s.contains('98%'));
  _chk('blood pressure row', s.contains('Blood pressure:') && s.contains('mmHg') && s.contains('/'));
  _chk('temperature row', s.contains('Temperature:') && s.contains('°C'));
  _chk('sleep row (7h 30m asleep)', s.contains('Sleep:') && s.contains('7') && s.contains('30'));
  _chk('notes section', s.contains('Notes:'));
  _chk('has disclaimer', s.contains('not a medical diagnosis'));
  _chk('no gathering-data leak', !s.contains('Gathering data'));

  // No data → graceful line, still safe.
  final empty = buildHealthSummary(l, const [], name: '');
  _chk('empty → no readings line', empty.contains('No readings yet'));
  _chk('empty → still has disclaimer', empty.contains('not a medical diagnosis'));
  _chk('empty → no name blank line noise', !empty.contains('Blood oxygen'));

  // Optional status line (pregnancy/cycle) is included when provided, omitted otherwise.
  final withStatus = buildHealthSummary(l, samples, name: 'Aizhan', status: 'Pregnancy · week 20');
  _chk('status line included', withStatus.contains('Pregnancy · week 20'));
  _chk('no status → no stray line', !s.contains('Pregnancy'));

  // Localization: Russian title + labels present.
  const ru = L10n(AppLocale.ru);
  final rs = buildHealthSummary(ru, samples, nights: nights, name: 'Аружан');
  _chk('ru title', rs.contains('Сводка здоровья'));
  _chk('ru heart-rate label', rs.contains('Пульс:'));
  _chk('ru disclaimer', rs.contains('не медицинский диагноз'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
