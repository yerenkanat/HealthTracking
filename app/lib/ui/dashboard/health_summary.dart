/// Builds a shareable, localized plain-text health summary from the latest
/// readings + advisories. Presentation-layer (it localizes), but the string
/// assembly is otherwise pure — the caller just copies it to the clipboard, so
/// there are NO native share dependencies. Verified via verify_summary.dart.
library;

import '../../domain/health_advisor.dart';
import '../../domain/health_series.dart';
import '../../domain/sleep.dart';
import '../../l10n/l10n.dart';

/// Assemble the multi-line summary. Only metrics that actually have data appear.
/// Order: header → latest readings → advisories → non-medical disclaimer.
String buildHealthSummary(
  L10n l,
  List<HealthSample> samples, {
  List<SleepSummary> nights = const [],
  String name = '',
  String status = '', // optional pregnancy/cycle status line
}) {
  final b = StringBuffer();
  b.writeln(l.t('share_summary_title'));
  if (name.isNotEmpty) b.writeln(name);
  if (status.isNotEmpty) b.writeln(status);
  b.writeln();

  String row(String label, String value) => '• $label: $value';

  final hr = statsFor(buildSeries(samples, 'hr'));
  final spo2 = statsFor(buildSeries(samples, 'spo2'));
  final temp = statsFor(buildSeries(samples, 'temp'));
  final night = latestNight(nights);

  // ---- Blood pressure: only what a cuff measured -----------------------------
  //
  // The same decision visit_summary.dart already made, and two share paths
  // disagreeing about it is itself the defect. This text leaves the app —
  // clipboard, then whoever she sends it to — and «Давление: 137/88 mmHg» is
  // read as a measurement by anyone who receives it.
  //
  // A qualifier is NOT sufficient here, unlike temperature, where the approved
  // note travels with the number a few lines below. A wrist blood pressure's
  // accuracy depends on a calibration that expires at `bpCalibrationMaxAgeDays`
  // — and the age of that calibration cannot travel with a line of copied text,
  // so no wording pasted into a chat can tell the reader whether the number in
  // front of them is worth anything. The pool is filtered BEFORE any series is
  // built, because buildSeries yields bare (t, value) pairs and throws
  // provenance away.
  final cuffOnly = [for (final s in samples) if (!s.isDeviceEstimate) s];
  final sys = statsFor(buildSeries(cuffOnly, 'systolic'));
  final dia = statsFor(buildSeries(cuffOnly, 'diastolic'));
  final anyBp = buildSeries(samples, 'systolic').isNotEmpty;

  final rows = <String>[];
  if (hr != null) rows.add(row(l.metricLabel('hr'), '${hr.latest.round()} bpm'));
  if (spo2 != null) rows.add(row(l.metricLabel('spo2'), '${spo2.latest.round()}%'));
  if (sys != null && dia != null) {
    rows.add(row(l.t('metric_bp'), '${sys.latest.round()}/${dia.latest.round()} mmHg'));
  } else if (anyBp) {
    // She has blood-pressure readings and none of them came off a cuff. Saying
    // so is better than a silent gap, which a reader fills with "nothing to
    // report about her blood pressure" — the reassurance this whole change
    // exists to remove.
    rows.add('• ${l.t('share_bp_cuff_only')}');
  }
  if (temp != null) {
    rows.add(row(l.metricLabel('temp'), '${temp.latest.toStringAsFixed(1)} °C'));
    // This text leaves the app — clipboard, then whoever she sends it to. A
    // bare «Температура: 38.6 °C» is read as a measurement by anyone who gets
    // it, and off a wrist it is not one. The qualifier travels with the number
    // rather than staying on the screen it was copied from; the approved copy
    // is reused verbatim, and it disappears for a thermometer reading she
    // typed in, where the line is simply true.
    if (latestSourceFor(samples, 'temp') != ReadingSource.manual) {
      rows.add('  ${l.t('temp_device_estimate_note')}');
    }
  }
  if (night != null) rows.add(row(l.t('metric_sleep'), l.duration(night.asleepMin)));

  if (rows.isEmpty) {
    b.writeln('• ${l.t('share_summary_nodata')}');
  } else {
    for (final r in rows) {
      b.writeln(r);
    }
  }

  // Advisories (watch-first) as a short "notes" block.
  final advisories = generateAdvisories(samples, lastNight: night);
  final notes = advisories
      .where((a) => a.code != 'ADV_GATHERING')
      .map((a) => '– ${l.t(a.code)}')
      .toList();
  if (notes.isNotEmpty) {
    b.writeln();
    b.writeln('${l.t('share_summary_notes')}:');
    for (final n in notes) {
      b.writeln(n);
    }
  }

  b.writeln();
  b.write(l.t('chat_disclaimer'));
  return b.toString();
}
