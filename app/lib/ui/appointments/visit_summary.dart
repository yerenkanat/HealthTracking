/// Builds a shareable plain-text summary for a clinic visit: what happened
/// SINCE the last appointment, rather than what's true right now.
///
/// That's the distinction from the two existing summaries — buildHealthSummary
/// reports the latest readings, buildCycleSummary reports current predictions.
/// A clinician wants ranges over a period ("BP 105/68–132/85, avg 118/76 over
/// 12 readings"), plus the things neither of those carries: the medication list,
/// weight movement, and which symptoms were logged.
///
/// String assembly only — the caller copies it to the clipboard, so there are no
/// native share dependencies. Verified via verify_visit_summary.dart.
library;

import '../../domain/cycle_insights.dart' show symptomFrequencySince;
import '../../domain/cycle_log.dart';
import '../../domain/health_series.dart';
import '../../domain/medication.dart';
import '../../domain/weight.dart';
import '../../l10n/l10n.dart';

/// Samples recorded on/after [since].
List<HealthSample> samplesSince(List<HealthSample> samples, DateTime since) =>
    [for (final s in samples) if (!s.at.isBefore(since)) s];

/// Assemble the visit summary. Sections with no data are omitted entirely, so a
/// user who only tracks one thing doesn't hand over a page of blanks.
String buildVisitSummary(
  L10n l, {
  required List<HealthSample> samples,
  required Map<String, DayLog> dayLogs,
  required List<Medication> medications,
  required List<WeightEntry> weights,
  required DateTime now,
  int days = 14,
  String name = '',
  String status = '', // pregnancy week / cycle day, for context
}) {
  final since = now.subtract(Duration(days: days));
  final windowed = samplesSince(samples, since);
  final b = StringBuffer();

  b.writeln(l.t('visit_title'));
  if (name.isNotEmpty) b.writeln(name);
  b.writeln(l.t('visit_period', {'n': days}));
  if (status.isNotEmpty) b.writeln(status);

  String one(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  // ---- Vitals, as ranges rather than a single reading ----
  final sys = statsFor(buildSeries(windowed, 'systolic'));
  final dia = statsFor(buildSeries(windowed, 'diastolic'));
  final hr = statsFor(buildSeries(windowed, 'hr'));
  final spo2 = statsFor(buildSeries(windowed, 'spo2'));
  final temp = statsFor(buildSeries(windowed, 'temp'));

  final vitals = <String>[];
  if (sys != null && dia != null) {
    vitals.add('• ${l.t('metric_bp')}: ${l.t('visit_avg')} ${sys.mean.round()}/${dia.mean.round()} '
        '(${sys.min.round()}/${dia.min.round()}–${sys.max.round()}/${dia.max.round()}) mmHg');
  }
  if (hr != null) {
    vitals.add('• ${l.metricLabel('hr')}: ${l.t('visit_avg')} ${hr.mean.round()} (${hr.min.round()}–${hr.max.round()}) bpm');
  }
  if (spo2 != null) {
    vitals.add('• ${l.metricLabel('spo2')}: ${l.t('visit_avg')} ${spo2.mean.round()}% (${spo2.min.round()}–${spo2.max.round()}%)');
  }
  if (temp != null) {
    vitals.add('• ${l.metricLabel('temp')}: ${l.t('visit_avg')} ${one(temp.mean)} (${one(temp.min)}–${one(temp.max)}) °C');
  }
  if (vitals.isNotEmpty) {
    b.writeln();
    b.writeln(l.t('visit_vitals', {'n': windowed.length}));
    vitals.forEach(b.writeln);
  }

  // ---- Medications ----
  if (medications.isNotEmpty) {
    b.writeln();
    b.writeln(l.t('visit_meds'));
    for (final m in medications) {
      final parts = [m.name, if (m.dose.isNotEmpty) m.dose];
      b.writeln('• ${parts.join(' ')} — ${l.t('med_per_day', {'n': m.perDay})}');
    }
  }

  // ---- Weight ----
  final w = computeWeightStats(weights);
  if (w != null) {
    b.writeln();
    b.writeln(l.t('visit_weight'));
    final sign = w.delta >= 0 ? '+' : '−';
    b.writeln('• ${one(w.latest)} kg'
        '${w.count >= 2 ? ' ($sign${one(w.delta.abs())} kg ${l.t('visit_since_start')})' : ''}');
  }

  // ---- Symptoms logged in the window ----
  final symptoms = symptomFrequencySince(dayLogs.values, since)
      .where((s) => s.symptom != Symptom.allGood)
      .toList();
  if (symptoms.isNotEmpty) {
    b.writeln();
    b.writeln(l.t('visit_symptoms'));
    b.writeln('• ${symptoms.map((s) => '${l.t('sym_${s.symptom.name}')} ×${s.count}').join(', ')}');
  }

  b.writeln();
  b.writeln(l.t('visit_disclaimer'));
  return b.toString().trimRight();
}
