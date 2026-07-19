/// Pure-Dart verification of the clinic-visit summary text.
/// `dart run tool/verify_visit_summary.dart`
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/health_series.dart';
import '../lib/domain/medication.dart';
import '../lib/domain/weight.dart';
import '../lib/l10n/l10n.dart';
import '../lib/ui/appointments/visit_summary.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  const l = L10n(AppLocale.en);
  final now = DateTime(2026, 7, 20, 12);
  DateTime ago(int d) => now.subtract(Duration(days: d));

  final samples = [
    HealthSample(at: ago(1), heartRate: 80, spo2: 97, systolic: 132, diastolic: 85, coreTemp: 36.9),
    HealthSample(at: ago(5), heartRate: 58, spo2: 99, systolic: 105, diastolic: 68, coreTemp: 36.3),
    HealthSample(at: ago(30), heartRate: 200, spo2: 80, systolic: 200, diastolic: 130, coreTemp: 40.0), // outside window
  ];
  final dayLogs = <String, DayLog>{
    dateKey(ago(2)): DayLog(date: dateKey(ago(2)), symptoms: const {Symptom.cramps}),
    dateKey(ago(3)): DayLog(date: dateKey(ago(3)), symptoms: const {Symptom.cramps, Symptom.headache}),
    dateKey(ago(40)): DayLog(date: dateKey(ago(40)), symptoms: const {Symptom.nausea}), // outside window
  };
  final meds = [
    const Medication(id: 'm1', name: 'Folic acid', dose: '400 mcg'),
    const Medication(id: 'm2', name: 'Iron', dose: '27 mg', perDay: 2),
  ];
  final weights = const [
    WeightEntry(date: '2026-07-01', kg: 62.0),
    WeightEntry(date: '2026-07-18', kg: 63.4),
  ];

  final s = buildVisitSummary(l,
      samples: samples, dayLogs: dayLogs, medications: meds, weights: weights,
      now: now, name: 'Aigerim', status: 'Pregnancy · Week 24');

  // ---- Windowing ----
  _chk('window filters old samples', samplesSince(samples, now.subtract(const Duration(days: 14))).length == 2);
  _chk('out-of-window reading excluded', !s.contains('200'));
  _chk('out-of-window symptom excluded', !s.contains('Nausea'));

  // ---- Ranges, not single readings ----
  _chk('BP reported as a range', s.contains('105/68–132/85'));
  // (132+105)/2 = 118.5 → 119; (85+68)/2 = 76.5 → 77 (halves round up).
  _chk('BP average included', s.contains('119/77'));
  _chk('HR range', s.contains('58–80'));
  _chk('spo2 range', s.contains('97–99'));
  _chk('temperature keeps one decimal', s.contains('36.3–36.9'));
  _chk('reading count shown', s.contains('2'));

  // ---- Sections ----
  _chk('name included', s.contains('Aigerim'));
  _chk('status included', s.contains('Week 24'));
  _chk('medications listed with dose', s.contains('Folic acid 400 mcg'));
  _chk('per-day frequency shown', s.contains('Iron 27 mg'));
  _chk('weight latest', s.contains('63.4 kg'));
  _chk('weight delta', s.contains('+1.4'));
  _chk('symptoms counted', s.contains('Mild cramps ×2') && s.contains('Headache ×1'));
  _chk('disclaimer present', s.contains(l.t('visit_disclaimer')));

  // ---- Empty sections are omitted, not left blank ----
  final bare = buildVisitSummary(l,
      samples: const [], dayLogs: const {}, medications: const [], weights: const [], now: now);
  _chk('no vitals section without readings', !bare.contains(l.t('visit_vitals', {'n': 0})));
  _chk('no medications section when none', !bare.contains(l.t('visit_meds')));
  _chk('no weight section when none', !bare.contains(l.t('visit_weight')));
  _chk('no symptoms section when none', !bare.contains(l.t('visit_symptoms')));
  _chk('bare summary still has a title + disclaimer',
      bare.contains(l.t('visit_title')) && bare.contains(l.t('visit_disclaimer')));
  _chk('no trailing blank lines', !bare.endsWith('\n'));

  // A single weight entry has no delta to report.
  final oneWeight = buildVisitSummary(l,
      samples: const [], dayLogs: const {}, medications: const [],
      weights: const [WeightEntry(date: '2026-07-18', kg: 63.4)], now: now);
  _chk('single weight omits the delta', oneWeight.contains('63.4 kg') && !oneWeight.contains('('));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
