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

  // REVERT PROBE: the advisor as it was, with no idea when anything was
  // measured.
  return gen(samples);
  // ignore: dead_code
  final all = gen(samples);
  final warnings = [for (final a in all) if (a.tone == AdviceTone.watch) a];
  final fresh = gen(currentReadingsOnly(samples,
      now: now, bpCalibrationStale: bpCalibrationStale));

  // Nothing to warn about: the fresh pool answers on its own. If it is empty —
  // every reading she has is older than its metric allows — that pool falls
  // through to ADV_GATHERING, which claims nothing about her. It is the honest
  // answer to "is anything wrong?" when the app has not looked recently, and it
  // is already approved copy, so no new sentence is needed to say it.
  if (warnings.isEmpty) return fresh;

  // Something IS worth watching. The fresh pool's own fall-through has to go:
  // it would put «ничего необычного» underneath a warning, and the clipboard
  // export sends titles only, so those two sentences would travel side by side
  // with nothing to reconcile them. ADV_GATHERING goes for the same reason —
  // "gathering data" beside a finding reads as "we have not looked yet".
  const fallThroughs = {'ADV_NOTHING_UNUSUAL', 'ADV_GATHERING'};
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
