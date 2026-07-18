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
  final temp = statsFor(buildSeries(samples, 'temp'));
  if (temp != null && temp.latest >= TriageThresholds.feverWarningC) {
    watch.add(Advisory('ADV_TEMP_ELEVATED', AdviceTone.watch, 'temp', value: temp.latest));
  } else if (temp != null) {
    positive.add(Advisory('ADV_TEMP_STEADY', AdviceTone.positive, 'temp', value: temp.latest));
  }

  // ---- SpO2 steady (healthy oxygen, no sleep dips) ----
  final spo2Stats = statsFor(buildSeries(samples, 'spo2'));
  if (spo2Stats != null && spo2Stats.min >= 96 && sleepDips.isEmpty) {
    positive.add(Advisory('ADV_SPO2_STEADY', AdviceTone.positive, 'spo2', value: spo2Stats.latest));
  }

  // ---- Sleep last night (nightly summary from the band, when available) ----
  if (lastNight != null) {
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

double _mean(Iterable<double> xs) {
  var sum = 0.0, n = 0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}
