/// The absorber rule, applied to STALENESS.
///
/// `generateAdvisories` judges readings; it has never been told when they were
/// taken. So «Всё стабильно» — replaced by `ADV_NOTHING_UNUSUAL`, but the same
/// slot — rendered over readings the app knew were nine hours old, which is a
/// present-tense claim from an out-of-date basis.
///
/// docs/CLINICAL-REVIEW-WATCH.md, "The absorber rule":
///
/// > A reassurance may claim no more than the reading it was computed from …
/// > Corollary: **gate the positives, never the warnings.** The costs are not
/// > symmetric. A missed warning is a woman at home with preeclampsia. A missed
/// > reassurance is a woman not told she is fine.
///
/// That corollary is the whole shape of this file. Both halves matter:
///
///  * the WARNINGS are computed from every reading, whatever its age. Nothing
///    here may silence one — a stale elevated reading is still the most
///    important thing the app has seen, and the tile beside it now states its
///    age, which is the honest way to qualify it;
///  * the POSITIVES — including the nothing-unusual fall-through, which is the
///    absorber the rule was written about — are computed only from readings
///    that are current on their own metric's ladder.
///
/// A partial fix here would be worse than none, which is why every surface that
/// answers "is anything wrong?" from advisories calls this instead of
/// `generateAdvisories`: the dashboard banner and the clipboard summary. A
/// reassurance removed from one and left on the other is not removed.
library;

import 'health_advisor.dart';
import 'health_series.dart';
import 'sleep.dart';

/// The advisories that report an ABSENCE of readings rather than a finding
/// about them.
///
/// One constant, read by two surfaces that must agree: the fall-through filter
/// below, which keeps «Свежих измерений нет» from printing underneath a
/// warning, and the clipboard export in ui/dashboard/health_summary.dart, which
/// sends advisory TITLES only. That export listed `ADV_GATHERING` by hand, so
/// adding a second no-data code would have left the new one travelling out of
/// the app on its own — «Нет свежих измерений» arriving in somebody's chat
/// under a health summary that does contain numbers.
///
/// `ADV_NOTHING_UNUSUAL` is deliberately NOT here. It is a claim about the
/// readings, it is already restricted to current ones by [currentAdvisories],
/// and it is meant to travel; what it may not do is ride along under a warning,
/// which is a separate rule applied at the one call site that needs it.
const noDataAdvisories = {'ADV_GATHERING', 'ADV_NO_CURRENT_READINGS'};

/// Advisories with the staleness gate applied. Same order and same contract as
/// [generateAdvisories] — watch-first, never empty — so a caller can keep
/// taking `.first` as the headline.
///
/// Sleep is deliberately NOT filtered: the freshness table puts sleep, steps,
/// distance and calories in the row where «48 h is fine», because they are
/// complete facts about finished periods rather than claims about a body that
/// has since moved.
List<Advisory> currentAdvisories(
  List<HealthSample> samples, {
  required DateTime now,
  bool bpCalibrationStale = true,
  int minSamples = 3,
  SleepSummary? lastNight,
  int? waterCount,
  int waterGoal = 0,
  int hour = 12,
  List<SleepSummary> recentNights = const [],
}) {
  List<Advisory> gen(List<HealthSample> pool) => generateAdvisories(
        pool,
        minSamples: minSamples,
        lastNight: lastNight,
        waterCount: waterCount,
        waterGoal: waterGoal,
        hour: hour,
        recentNights: recentNights,
      );

  final all = gen(samples);
  final warnings = [for (final a in all) if (a.tone == AdviceTone.watch) a];
  final pool = currentReadingsOnly(samples,
      now: now, bpCalibrationStale: bpCalibrationStale);

  // SHE HAS READINGS AND NOT ONE OF THEM IS CURRENT on its own metric's ladder.
  //
  // `gen` on an empty pool answers ADV_GATHERING — «Собираем данные» — and that
  // sentence is simply untrue here: nothing is being gathered, the data exists,
  // and it is out of date. The card was accepted at the time as "approved copy
  // that claims nothing", but a woman whose band has been in a drawer since
  // yesterday reads «Собираем данные» as "the app is on it", which is the same
  // false reassurance as a promise to warn her.
  //
  // Its own code and its own approved copy, which says what is true — the last
  // readings are not fresh and do not describe now — and closes with the
  // sentence ADV_NOTHING_UNUSUAL_b closes with, word for word in all three
  // languages: feeling unwell outranks the numbers. That is the counterweight
  // that stops an absence-of-data card from reading as an all-clear.
  //
  // The empty pool with NO readings at all is left alone: that really is
  // ADV_GATHERING, and generateAdvisories answers it from `samples.length`.
  final fresh = pool.isEmpty && samples.isNotEmpty
      ? [const Advisory('ADV_NO_CURRENT_READINGS', AdviceTone.info, 'general')]
      : gen(pool);

  // Nothing to warn about: the fresh pool answers on its own.
  if (warnings.isEmpty) return fresh;

  // Something IS worth watching. The fresh pool's own fall-through has to go:
  // it would put «ничего необычного» underneath a warning, and the clipboard
  // export sends titles only, so those two sentences would travel side by side
  // with nothing to reconcile them. The no-data codes go for the same reason —
  // "gathering data" beside a finding reads as "we have not looked yet", and
  // «Свежих измерений нет» printed underneath a warning computed from those
  // very readings contradicts it outright.
  const fallThroughs = {'ADV_NOTHING_UNUSUAL', ...noDataAdvisories};
  return [
    ...warnings,
    for (final a in fresh)
      if (a.tone != AdviceTone.watch && !fallThroughs.contains(a.code)) a,
  ];
}

/// The single most important advisory for the dashboard's peace-of-mind banner
/// — the staleness-gated twin of `overallStatus`, which the banner used to call
/// and which cannot see a timestamp.
Advisory currentOverallStatus(
  List<HealthSample> samples, {
  required DateTime now,
  bool bpCalibrationStale = true,
}) =>
    currentAdvisories(samples, now: now, bpCalibrationStale: bpCalibrationStale)
        .first;
