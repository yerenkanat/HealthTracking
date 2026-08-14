/// Builds a shareable, localized plain-text health summary from the latest
/// readings + advisories. Presentation-layer (it localizes), but the string
/// assembly is otherwise pure — the caller just copies it to the clipboard, so
/// there are NO native share dependencies. Verified via verify_summary.dart.
library;

import '../../domain/current_advisories.dart';
import '../../domain/health_series.dart';
import '../../domain/sleep.dart';
import '../../l10n/l10n.dart';

/// Assemble the multi-line summary. Only metrics that actually have data appear.
/// Order: header → latest readings → advisories → non-medical disclaimer.
///
/// [now] anchors the age printed beside every reading. It is passed in rather
/// than read here so the copied text agrees with the screen it was copied from.
/// [bpCalibrationStale] reaches the advisory gate below; it changes nothing
/// about the rows, whose blood pressure is cuff-only already.
String buildHealthSummary(
  L10n l,
  List<HealthSample> samples, {
  List<SleepSummary> nights = const [],
  String name = '',
  String status = '', // optional pregnancy/cycle status line
  DateTime? now,
  bool bpCalibrationStale = true,
}) {
  final at = now ?? DateTime.now();
  final b = StringBuffer();
  b.writeln(l.t('share_summary_title'));
  if (name.isNotEmpty) b.writeln(name);
  if (status.isNotEmpty) b.writeln(status);
  b.writeln();

  /// «• Пульс: 78 bpm (2 мин назад)».
  ///
  /// The age is part of the row, not a footnote, because this text leaves the
  /// app: a bare «Пульс: 78» in a chat is read as "now" by whoever receives it,
  /// and the freshness line it was copied from stays behind on the screen.
  /// [metric] names which reading's clock to read — the whole of backlog 1.1 is
  /// that these differ, so one timestamp for the block would repeat the defect
  /// in a place nobody can check it. Omitted when the age cannot be described.
  String row(String label, String value, String metric) {
    final when = _ageOf(l, latestAtFor(samples, metric), at);
    return when == null ? '• $label: $value' : '• $label: $value ($when)';
  }

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
  if (hr != null) rows.add(row(l.metricLabel('hr'), '${hr.latest.round()} bpm', 'hr'));
  if (spo2 != null) rows.add(row(l.metricLabel('spo2'), '${spo2.latest.round()}%', 'spo2'));
  if (sys != null && dia != null) {
    // The cuff-only pool, so the age is the age of the reading actually
    // printed — the wrist estimate that was filtered out has its own, later
    // timestamp, and reading that one would date this row from a number that
    // is not in it.
    final when = _ageOf(l, latestAtFor(cuffOnly, 'systolic'), at);
    final v = '${sys.latest.round()}/${dia.latest.round()} mmHg';
    rows.add(when == null
        ? '• ${l.t('metric_bp')}: $v'
        : '• ${l.t('metric_bp')}: $v ($when)');
  } else if (anyBp) {
    // She has blood-pressure readings and none of them came off a cuff. Saying
    // so is better than a silent gap, which a reader fills with "nothing to
    // report about her blood pressure" — the reassurance this whole change
    // exists to remove.
    rows.add('• ${l.t('share_bp_cuff_only')}');
  }
  if (temp != null) {
    rows.add(row(l.metricLabel('temp'), '${temp.latest.toStringAsFixed(1)} °C', 'temp'));
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
  // No age: sleep is the row the freshness table puts in «48 h is fine», and
  // the night it names is already in the value.
  if (night != null) {
    rows.add('• ${l.t('metric_sleep')}: ${l.duration(night.asleepMin)}');
  }

  if (rows.isEmpty) {
    b.writeln('• ${l.t('share_summary_nodata')}');
  } else {
    for (final r in rows) {
      b.writeln(r);
    }
  }

  // Advisories (watch-first) as a short "notes" block.
  //
  // currentAdvisories, not generateAdvisories. This block is the absorber the
  // rule was written about, and it is the worst-placed one: the export sends
  // advisory TITLES only, so «Часы не увидели ничего необычного» arrives in
  // somebody's chat with no body text, no numbers, and none of the ages
  // printed above it. Warnings are unaffected — they are computed from every
  // reading whatever its age. See domain/current_advisories.dart.
  final advisories = currentAdvisories(samples, now: at, lastNight: night,
      bpCalibrationStale: bpCalibrationStale);
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

/// «2 мин назад», or null when the age cannot honestly be described.
String? _ageOf(L10n l, DateTime? at, DateTime now) {
  if (at == null) return null;
  final age = now.difference(at);
  return l.agoIfKnown(age.isNegative ? Duration.zero : age);
}
