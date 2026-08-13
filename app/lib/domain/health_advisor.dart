/// HealthAdvisor — turns the mother's smart-band data into a few plain, safe,
/// data-grounded advisory cards. This is the app's "AI advisor": it reasons over
/// the actual telemetry (BP, HR, SpO2, temperature trends) rather than free chat.
/// Pure Dart → unit-testable. Owned by OB-GYN (thresholds) + AI Engineer.
///
/// Safety: advisories are gentle wellness guidance, NEVER a diagnosis. True
/// emergencies are handled separately by the triage layer (assessTelemetry →
/// Emergency Rescue screen), which always wins. Each advisory carries a CODE that
/// the UI localizes (ru/kk/en), so no language is baked into the logic.
library;

import '../core/triage.dart' show TriageThresholds;
import 'health_series.dart';
import 'sleep.dart';

enum AdviceTone { positive, info, watch }

class Advisory {
  final String code; // localized by the UI, e.g. 'ADV_BP_ELEVATED'
  final AdviceTone tone;
  final String metric; // 'systolic' | 'hr' | 'spo2' | 'temp' | 'general'
  final double? value; // the number behind the advice (for "{value}" interpolation)
  const Advisory(this.code, this.tone, this.metric, {this.value});
}

/// Generate advisories from recent samples. Ordered watch-first so the UI shows
/// the most important guidance on top.
List<Advisory> generateAdvisories(
  List<HealthSample> samples, {
  int minSamples = 3,
  SleepSummary? lastNight,
  int? waterCount, // today's water glasses (null = not tracked)
  int waterGoal = 0,
  int hour = 12, // local hour of day, for time-aware hydration nudges
  List<SleepSummary> recentNights = const [], // last several nights, for a trend
}) {
  if (samples.length < minSamples) {
    return const [Advisory('ADV_GATHERING', AdviceTone.info, 'general')];
  }

  final watch = <Advisory>[];
  final positive = <Advisory>[];

  // ---- Blood pressure ----
  final sys = statsFor(buildSeries(samples, 'systolic'));
  final dia = statsFor(buildSeries(samples, 'diastolic'));
  if (sys != null && dia != null) {
    // "elevated" = below the emergency cutoff but worth watching.
    final sysElevated = sys.latest >= 135 && sys.latest < TriageThresholds.bpSystolicEmergency;
    final diaElevated = dia.latest >= 85 && dia.latest < TriageThresholds.bpDiastolicEmergency;
    if (sysElevated || diaElevated) {
      watch.add(Advisory('ADV_BP_ELEVATED', AdviceTone.watch, 'systolic', value: sys.latest));
    } else if (sys.latest < 130 && dia.latest < 85) {
      positive.add(Advisory('ADV_BP_STEADY', AdviceTone.positive, 'systolic', value: sys.latest));
    }
  }

  // ---- Heart rate trend (first half vs second half of the window) ----
  final hrSeries = buildSeries(samples, 'hr');
  if (hrSeries.length >= 4) {
    final mid = hrSeries.length ~/ 2;
    final firstAvg = _mean(hrSeries.sublist(0, mid).map((p) => p.value));
    final secondAvg = _mean(hrSeries.sublist(mid).map((p) => p.value));
    if (secondAvg - firstAvg >= 8) {
      watch.add(Advisory('ADV_HR_RISING', AdviceTone.watch, 'hr', value: secondAvg));
    } else if ((secondAvg - firstAvg).abs() < 5) {
      positive.add(Advisory('ADV_HR_STEADY', AdviceTone.positive, 'hr', value: secondAvg));
    }
  }

  // ---- SpO2 during sleep ----
  final sleepDips = samples
      .where((s) => s.duringSleep && s.spo2 != null && s.spo2! < TriageThresholds.spo2Warning)
      .toList();
  if (sleepDips.isNotEmpty) {
    final lowest = sleepDips.map((s) => s.spo2!).reduce((a, b) => a < b ? a : b);
    watch.add(Advisory('ADV_SPO2_SLEEP_DIP', AdviceTone.watch, 'spo2', value: lowest));
  }

  // ---- Temperature ----
  //
  // WHAT MAY BE SAID DEPENDS ON WHO MEASURED IT. From a thermometer reading she
  // typed in, both cards are true. From a wrist estimate — whose dominant error
  // term is the room, the bedding and how tightly the strap is done up — only
  // one of them is:
  //
  //   * a device reading below the threshold produces NOTHING. «Температура по
  //     браслету держится ровно» is a normality verdict on a body, off one
  //     estimate, and the woman whose wrist reads 35.9 while her core is 39 was
  //     being reassured by name. Refused sentence #15 in
  //     docs/CLINICAL-REVIEW-WATCH.md. Silence is the correct output, and it is
  //     honest silence: the same fever in a cool room raises nothing either way.
  //   * a high device reading gets its own card, which asserts the SENSOR's
  //     reading rather than her temperature and names the instrument to measure
  //     with. ADV_TEMP_ELEVATED's «измерьте снова» is refused sentence #16 here:
  //     the only instrument to hand is the same wrist, and re-reading it is not
  //     a second measurement.
  final temp = statsFor(buildSeries(samples, 'temp'));
  final tempFromDevice = _latestTempIsDeviceEstimate(samples);
  if (temp != null && temp.latest >= TriageThresholds.feverWarningC) {
    watch.add(Advisory(
      tempFromDevice ? 'ADV_TEMP_DEVICE_HIGH' : 'ADV_TEMP_ELEVATED',
      AdviceTone.watch,
      'temp',
      value: temp.latest,
    ));
  } else if (temp != null && !tempFromDevice) {
    positive.add(Advisory('ADV_TEMP_STEADY', AdviceTone.positive, 'temp', value: temp.latest));
  }

  // ---- Blood glucose (a wellness estimate — graded here, never triaged) ----
  final glucose = statsFor(buildSeries(samples, 'glucose'));
  if (glucose != null) {
    if (glucose.latest >= GlucoseThresholds.elevatedMmol) {
      watch.add(Advisory('ADV_GLUCOSE_HIGH', AdviceTone.watch, 'glucose', value: glucose.latest));
    } else if (glucose.latest < GlucoseThresholds.lowMmol) {
      watch.add(Advisory('ADV_GLUCOSE_LOW', AdviceTone.watch, 'glucose', value: glucose.latest));
    } else {
      positive.add(Advisory('ADV_GLUCOSE_STEADY', AdviceTone.positive, 'glucose', value: glucose.latest));
    }
  }

  // ---- SpO2 steady (healthy oxygen, no sleep dips) ----
  final spo2Stats = statsFor(buildSeries(samples, 'spo2'));
  if (spo2Stats != null && spo2Stats.min >= 96 && sleepDips.isEmpty) {
    positive.add(Advisory('ADV_SPO2_STEADY', AdviceTone.positive, 'spo2', value: spo2Stats.latest));
  }

  // ---- Sleep: a multi-night trend takes precedence over a single night ----
  // Three short nights in a row is worth naming as a pattern — rest matters more
  // in pregnancy, and one short night is ordinary where a run of them is not.
  final threeShortNights = _lastNShort(recentNights, 3);
  // ---- Sleep last night (nightly summary from the band, when available) ----
  if (threeShortNights) {
    watch.add(const Advisory('ADV_SLEEP_DEBT', AdviceTone.watch, 'general'));
  } else if (lastNight != null) {
    if (lastNight.asleepMin < SleepThresholds.fairAsleepMin) {
      watch.add(const Advisory('ADV_SLEEP_SHORT', AdviceTone.watch, 'general'));
    } else if (lastNight.quality == SleepQuality.good) {
      positive.add(const Advisory('ADV_SLEEP_GOOD', AdviceTone.positive, 'general'));
    }
  } else {
    // Fallback: restful sleep inferred from sleep samples with no oxygen dips.
    final sleepCount = samples.where((s) => s.duringSleep).length;
    if (sleepCount >= 2 && sleepDips.isEmpty) {
      positive.add(Advisory('ADV_SLEEP_OK', AdviceTone.positive, 'general', value: sleepCount.toDouble()));
    }
  }

  // ---- Hydration (from the water tracker, when available). Ranked after the
  // medical checks so band-driven concerns always come first. ----
  if (waterCount != null && waterGoal > 0) {
    if (waterCount >= waterGoal) {
      positive.add(Advisory('ADV_HYDRATED', AdviceTone.positive, 'general', value: waterCount.toDouble()));
    } else if (hour >= 17 && waterCount * 2 < waterGoal) {
      // Evening and under half the goal → a gentle nudge.
      watch.add(Advisory('ADV_HYDRATE_LOW', AdviceTone.watch, 'general', value: waterCount.toDouble()));
    }
  }

  // ---- Overall reassurance when nothing needs watching ----
  if (watch.isEmpty) {
    return [const Advisory('ADV_ALL_STEADY', AdviceTone.positive, 'general'), ...positive];
  }
  return [...watch, ...positive];
}

/// The single most important advisory for the dashboard's "peace of mind"
/// banner: watch-first, else the overall-steady reassurance. Never null — mirrors
/// [generateAdvisories], which always returns at least one card. The banner reads
/// green for a positive tone, warm amber for a watch tone, neutral while gathering.
Advisory overallStatus(List<HealthSample> samples) => generateAdvisories(samples).first;

/// True when the most recent [n] nights all fell below the "fair" sleep floor.
/// Defensive about order — sorts by date descending — and needs at least [n]
/// nights before it will call a trend.
bool _lastNShort(List<SleepSummary> nights, int n) {
  if (nights.length < n) return false;
  final sorted = [...nights]..sort((a, b) => b.night.compareTo(a.night));
  return sorted.take(n).every((s) => s.asleepMin < SleepThresholds.fairAsleepMin);
}

/// Who measured the temperature the card would be about.
///
/// Matches `statsFor(buildSeries(samples, 'temp')).latest` exactly — that is the
/// CHRONOLOGICALLY last sample carrying a temperature, not the last one in the
/// list — so the provenance and the number can never come from different
/// readings. Nothing to say about? Treated as a device estimate, which says
/// nothing.
bool _latestTempIsDeviceEstimate(List<HealthSample> samples) {
  HealthSample? latest;
  for (final s in samples) {
    if (s.coreTemp == null) continue;
    if (latest == null || !s.at.isBefore(latest.at)) latest = s;
  }
  return latest?.isDeviceEstimate ?? true;
}

double _mean(Iterable<double> xs) {
  var sum = 0.0, n = 0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}
