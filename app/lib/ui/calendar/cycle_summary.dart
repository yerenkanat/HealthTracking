/// Builds a shareable, localized plain-text cycle summary from the current
/// predictions (next period + status, fertile window, ovulation, average cycle).
/// The date formatting is injected so the assembly stays pure and testable; the
/// caller passes a locale-aware formatter (e.g. MaterialLocalizations). Copied to
/// the clipboard by the caller — no native share deps. Verified via
/// verify_cycle_summary.dart.
library;

import '../../domain/cycle_predictions.dart';
import '../../l10n/l10n.dart';

String buildCycleSummary(
  L10n l,
  CycleInfo info, {
  required String Function(DateTime) formatDate,
  /// Whether she moved the cycle-length slider herself.
  ///
  /// Only distinguishes «her setting» from «our default» — both of which are
  /// assumptions. Passed rather than derived so this file stays pure, and so
  /// the sentence here cannot drift from the one the card prints.
  bool baselineChosen = false,
}) {
  final b = StringBuffer();
  b.writeln(l.t('cyc_share_title'));
  b.writeln();

  if (!info.hasData || info.nextPeriodStart == null) {
    b.writeln('• ${l.t('cyc_share_nodata')}');
  } else {
    final until = info.daysUntilNextPeriod ?? 0;
    final status = until > 0
        ? l.t('cyc_period_in', {'n': until})
        : until == 0
            ? l.t('cyc_period_today')
            : l.t('cyc_period_late', {'n': -until});
    b.writeln('• ${l.t('cyc_next_period')}: ${formatDate(info.nextPeriodStart!)} ($status)');
    if (info.fertileStart != null && info.fertileEnd != null) {
      b.writeln('• ${l.t('cyc_phase_fertile')}: ${formatDate(info.fertileStart!)} – ${formatDate(info.fertileEnd!)}');
    }
    if (info.ovulation != null) {
      b.writeln('• ${l.t('cyc_ovulation')}: ${formatDate(info.ovulation!)}');
    }
    // The screen stopped asserting this after one logged period; this text
    // did not, and it is the one that goes to a doctor. «Средний цикл: 28 дн.»
    // over zero completed cycles is a measurement she never provided, in a
    // document a clinician may reasonably act on.
    b.writeln('• ${l.t(
      info.avgCycleMeasured
          ? 'cyc_avg_cycle'
          : baselineChosen
              ? 'cyc_avg_cycle_setting'
              : 'cyc_avg_cycle_assumed',
      {'n': info.avgCycleLength},
    )}');
  }

  b.writeln();
  b.write(l.t('cyc_share_disclaimer'));
  return b.toString();
}
