/// Builds a shareable plain-text summary for a clinic visit: what happened
/// SINCE the last appointment, rather than what's true right now.
///
/// That's the distinction from the two existing summaries — buildHealthSummary
/// reports the latest readings, buildCycleSummary reports current predictions.
/// A clinician wants ranges over a period ("BP 105/68–132/85, avg 118/76 over
/// 12 readings"), plus the things neither of those carries: the medication list,
/// weight movement, and which symptoms were logged.
///
/// Its reader is a clinician, which is why two vitals are treated differently
/// from the rest: temperature appears ONLY when a thermometer produced it, and
/// blood pressure ONLY when a cuff did. See the blocks that build them below,
/// and docs/CLINICAL-REVIEW-WATCH.md.
///
/// The reading count sits on each ROW rather than on the section header, because
/// after those two filters no two rows are built from the same pool: a header
/// saying «40 измерений» over a blood-pressure row resting on two is a claim
/// about the evidence that is not true of the evidence.
///
/// String assembly only — the caller copies it to the clipboard, so there are no
/// native share dependencies. Verified via verify_visit_summary.dart,
/// test/device_temperature_test.dart and test/visit_summary_bp_test.dart.
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
  final since = now.subtract(Duration(days: days)); // elapsed-ok: a cutoff instant, compared against timestamps
  final windowed = samplesSince(samples, since);
  final b = StringBuffer();

  b.writeln(l.t('visit_title'));
  if (name.isNotEmpty) b.writeln(name);
  b.writeln(l.t('visit_period', {'n': days}));
  if (status.isNotEmpty) b.writeln(status);

  String one(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  // ---- Vitals, as ranges rather than a single reading ----
  //
  // The readings she took with an instrument and typed in. `isDeviceEstimate`
  // is this product's single vocabulary for that distinction — see
  // domain/health_series.dart, which also explains why an unlabelled stored row
  // counts as a device one. The pool is filtered HERE, before any series is
  // built, because buildSeries yields bare (t, value) pairs and throws
  // provenance away: after it there is nothing left to filter on, and a mean
  // over a mixed pool has no instrument that could honestly be named beside it.
  final measured = [for (final s in windowed) if (!s.isDeviceEstimate) s];

  // Heart rate and blood oxygen are still built from the WHOLE window, wrist
  // estimates and typed readings together, and that is a known gap rather than
  // a decision this file is entitled to make. The review graded both CHANGES,
  // not REFUSED (docs/CLINICAL-REVIEW-WATCH.md): they may be shown, but its
  // requirement is that the extremes be labelled — a day minimum is the
  // sleeping minimum, a maximum is the stairs — and this summary holds neither
  // an activity signal nor, for a day extreme, a sleep flag, so labelling them
  // here would mean inventing the label. Two further consequences are visible
  // in the output above: the pool is mixed, so no single instrument can be
  // named beside the mean, and a typed oximeter reading is averaged together
  // with a wrist estimate as though they were the same kind of thing.
  final hrSeries = buildSeries(windowed, 'hr');
  final spo2Series = buildSeries(windowed, 'spo2');
  final hr = statsFor(hrSeries);
  final spo2 = statsFor(spo2Series);

  // ---- Blood pressure: only what a cuff measured ------------------------
  //
  // The same refusal as the temperature block below, and for stronger reasons.
  // docs/CLINICAL-REVIEW-WATCH.md REFUSED the wrist blood-pressure day average
  // outright for the admin panel, whose reader is the owner; this page is put
  // into a clinician's hand, and a clinician will reasonably read a number on
  // it as a measurement. Three of the review's findings carry over intact:
  //
  //   * the peak is the clinical object and a mean hides it — a fortnight
  //     touching 158/104 and resting at 105/68 prints «118/76» and looks
  //     reassuring while failing;
  //   * emergency_confirmation.dart puts wrist PPG blood pressure at
  //     ±10–15 mmHg against the 140 threshold, so the uncertainty is the size
  //     of the decision the reader is making;
  //   * calibration state is not on the row and cannot be — bpCalibrationMaxAgeDays
  //     exists precisely because a calibration expires, and this text is copied
  //     to a clipboard and read hours or days later.
  //
  // And an aggravating one that is specific to this page: blood pressure is
  // what the antenatal protocol acts on. packages/contract/antenatal_protocol.json
  // pairs blood pressure with urine protein at every visit from the second, and
  // a reassuring wrist estimate can defer the very check the protocol
  // schedules. A wrist estimate cannot stand in for either of that pair.
  //
  // A cuff reading she took and typed in is a different evidential object —
  // known instrument, deliberate act, no calibration to expire — and it is
  // distinguishable in the store: AppController.logManualVitals builds its
  // HealthSample with the default ReadingSource.manual, and every device path
  // states ReadingSource.sensor explicitly. Those are presentable, and unlike
  // the panel this row does carry the extremes alongside the mean, which was
  // the review's first objection. The row names the instrument so the doctor is
  // not the one who has to ask.
  //
  // When only wrist estimates exist, the summary carries no blood pressure at
  // all. A caveat is not what stops a figure in a patient-presented summary
  // from being read as data.
  //
  // NOT fixed here, and it should be looked at: «105/68–132/85» is a bounding
  // box over two independent series, not two readings. The lowest systolic and
  // the lowest diastolic may come from different moments, so a pair printed
  // here need never have been recorded together. It errs on the safe side —
  // every real reading lies inside the box, and the top corner is the most
  // alarming pair rather than the least — but it still reads like two readings.
  final sysSeries = buildSeries(measured, 'systolic');
  final diaSeries = buildSeries(measured, 'diastolic');
  final sys = statsFor(sysSeries);
  final dia = statsFor(diaSeries);

  // ---- Temperature: only what a thermometer measured --------------------
  //
  // This page is handed to a clinician, who will reasonably read any number on
  // it as a measurement — there is nothing in «36.9 (35.4–37.2)» that says it
  // came off a strap. docs/CLINICAL-REVIEW-WATCH.md refused exactly this
  // construct (a temperature mean with a span) for the admin panel, and the
  // reader here is worse placed than the panel's: the panel's reader is an
  // owner who can go and ask, this one is deciding care. The two device paths
  // in this product also disagree about what the degrees mean — the OEM band
  // applies skinToCoreTempC, the watch path deliberately does not — so a mixed
  // pool has no single referent even before the mean flattens it.
  //
  // Readings she took with a thermometer and typed in are a different object:
  // known instrument, known site, deliberate, and the one temperature path this
  // product is entitled to act on at all. Those are presentable, and the row
  // names the instrument so the doctor is not the one who has to ask.
  //
  // When there are none, the summary simply carries no temperature. Silence is
  // the correct output: printing the wrist estimates under a caveat would still
  // put a number in front of a clinician, and a caveat is not what stops a
  // number in a patient-presented summary from being read as data.
  final tempSeries = buildSeries(measured, 'temp');
  final temp = statsFor(tempSeries);

  // What a row is built on, in brackets after its name: the instrument where
  // one can be named, and the number of readings behind the figures.
  //
  // The count belongs here rather than on the section header. The header used
  // to carry a single count of every sample in the window, which after the two
  // provenance filters above can be twenty times a row's own denominator — «40
  // измерений» over a blood-pressure row resting on two. One count cannot
  // describe four differently-sourced rows.
  //
  // Omitted at one reading, where the row prints a bare value and no mean: "1"
  // would be saying what the absence of a range already says, and it keeps the
  // plural agreement out of Russian entirely.
  String about(int n, [String? instrument]) {
    final parts = [
      if (instrument != null) instrument,
      if (n >= 2) l.t('visit_row_readings', {'n': n}),
    ];
    return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
  }

  // One reading has no average and no span; «сред. 38.6 (38.6–38.6)» dresses a
  // single measurement up as a series. True of every row here.
  final vitals = <String>[];
  if (sys != null && dia != null) {
    final label = '${l.t('metric_bp')}${about(sysSeries.length, l.t('visit_bp_cuff'))}';
    vitals.add(sysSeries.length == 1 && diaSeries.length == 1
        ? '• $label: ${sys.latest.round()}/${dia.latest.round()} mmHg'
        : '• $label: ${l.t('visit_avg')} ${sys.mean.round()}/${dia.mean.round()} '
            '(${sys.min.round()}/${dia.min.round()}–${sys.max.round()}/${dia.max.round()}) mmHg');
  }
  if (hr != null) {
    final label = '${l.metricLabel('hr')}${about(hrSeries.length)}';
    vitals.add(hrSeries.length == 1
        ? '• $label: ${hr.latest.round()} bpm'
        : '• $label: ${l.t('visit_avg')} ${hr.mean.round()} (${hr.min.round()}–${hr.max.round()}) bpm');
  }
  if (spo2 != null) {
    final label = '${l.metricLabel('spo2')}${about(spo2Series.length)}';
    vitals.add(spo2Series.length == 1
        ? '• $label: ${spo2.latest.round()}%'
        : '• $label: ${l.t('visit_avg')} ${spo2.mean.round()}% (${spo2.min.round()}–${spo2.max.round()}%)');
  }
  if (temp != null) {
    final label = '${l.metricLabel('temp')}${about(tempSeries.length, l.t('visit_temp_thermometer'))}';
    vitals.add(tempSeries.length == 1
        ? '• $label: ${one(temp.latest)} °C'
        : '• $label: ${l.t('visit_avg')} ${one(temp.mean)} (${one(temp.min)}–${one(temp.max)}) °C');
  }
  if (vitals.isNotEmpty) {
    b.writeln();
    b.writeln(l.t('visit_vitals_head'));
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
