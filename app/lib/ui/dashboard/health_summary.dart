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
  final sys = statsFor(buildSeries(samples, 'systolic'));
  final dia = statsFor(buildSeries(samples, 'diastolic'));
  final temp = statsFor(buildSeries(samples, 'temp'));
  final night = latestNight(nights);

  final rows = <String>[];
  if (hr != null) rows.add(row(l.metricLabel('hr'), '${hr.latest.round()} bpm'));
  if (spo2 != null) rows.add(row(l.metricLabel('spo2'), '${spo2.latest.round()}%'));
  if (sys != null && dia != null) {
    rows.add(row(l.t('metric_bp'), '${sys.latest.round()}/${dia.latest.round()} mmHg'));
  }
  if (temp != null) rows.add(row(l.metricLabel('temp'), '${temp.latest.toStringAsFixed(1)} °C'));
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
