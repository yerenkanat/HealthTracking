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

  /// The second half of a PAIRED reading — today only the diastolic behind a
  /// blood-pressure card.
  ///
  /// It exists because a blood pressure is a pair and half of one is not a
  /// reading: the advisor card used to badge `ADV_BP_ELEVATED` with a bare,
  /// unitless «137» in bold, which is refused sentence #19 in
  /// docs/CLINICAL-REVIEW-WATCH.md. The UI shows the pair or shows nothing, so
  /// a `systolic` advisory that leaves this null gets no badge at all.
  final double? pairedValue;
  const Advisory(this.code, this.tone, this.metric, {this.value, this.pairedValue});
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
  //
  // The same rule as temperature below, for the same reason, and if anything a
  // stronger one. «Давление ровное» is a normality verdict on a body; from a
  // wrist PPG estimate it is not one this product can make. The review puts
  // that estimate at ±10–15 mmHg against a 140 threshold — the uncertainty is
  // the size of the decision — and `bpCalibrationMaxAgeDays` exists precisely
  // because the calibration behind it expires.
  //
  // What makes it worse than the temperature case rather than merely equal: the
  // antenatal protocol pairs blood pressure with urine protein at EVERY visit
  // from the second, so a reassurance here can defer a scheduled check. A wrist
  // estimate cannot exclude preeclampsia and must not sound like it did.
  //
  // The WARNING still fires from every source — refusing to reassure is not the
  // same as refusing to warn, and the two costs are not symmetric: a missed
  // warning is a woman at home with preeclampsia, a missed reassurance is a
  // woman not told she is fine. What changes with provenance is what the card
  // is allowed to SAY, so it branches into two codes rather than going quiet.
  final sys = statsFor(buildSeries(samples, 'systolic'));
  final dia = statsFor(buildSeries(samples, 'diastolic'));
  final bpFromDevice = _latestBpIsDeviceEstimate(samples);
  if (sys != null && dia != null) {
    // BOTH halves must be under the triage cutoff before this block says
    // anything, and that is a fix rather than a tidy-up.
    //
    // `assessTelemetry` raises PREECLAMPSIA_BP at EMERGENCY severity on
    // `sys >= 140 || dia >= 90`. This card used to fire on
    // `sysElevated || diaElevated`, each bounded separately — so a reading of
    // 150/86 satisfied the diastolic half (85–89) and produced a calm
    // «повышено — отдохните и измерьте снова» advisory while the triage layer
    // was opening the Emergency screen on the very same sample. Two screens in
    // one app disagreeing about whether she is in danger. With the AND, this
    // card is strictly the band BELOW the one triage acts on, and above it the
    // advisor says nothing because triage is already speaking.
    final belowEmergency = sys.latest < TriageThresholds.bpSystolicEmergency &&
        dia.latest < TriageThresholds.bpDiastolicEmergency;
    // "elevated" = below the emergency cutoff but worth watching. 135/85 fire
    // the card and appear in NO source this product cites, which is why no
    // user-facing string may state either of them.
    final sysElevated = sys.latest >= 135;
    final diaElevated = dia.latest >= 85;
    if (belowEmergency && (sysElevated || diaElevated)) {
      watch.add(bpFromDevice
          // A wrist estimate. The card's own firing window sits ENTIRELY inside
          // the ±10–15 mmHg the estimate carries, so «давление повышено» states
          // as fact the one thing the reading cannot establish (refused
          // sentence #17). Its own code, whose title names the SENSOR — and no
          // number: `value` is null by ruling, because a bare unitless systolic
          // in bold beside copy explaining it is not a measurement is refused
          // sentence #19, and 140/90 beside a wrist estimate is #20.
          ? const Advisory('ADV_BP_DEVICE_HIGH', AdviceTone.watch, 'systolic')
          // A cuff reading she typed in — known instrument, deliberate act — so
          // the card may name the number and may cite 140/90 (ACOG, via
          // packages/shared/src/triage.ts). The badge carries BOTH halves:
          // 137/88 is a blood pressure, 137 is not.
          : Advisory('ADV_BP_ELEVATED', AdviceTone.watch, 'systolic',
              value: sys.latest, pairedValue: dia.latest));
    } else if (belowEmergency && !bpFromDevice && sys.latest < 130 && dia.latest < 85) {
      // `belowEmergency` is redundant against 130/85 today and is stated anyway,
      // so that the day someone widens the reassurance band it cannot reach
      // over the cutoff triage escalates on.
      positive.add(Advisory('ADV_BP_STEADY', AdviceTone.positive, 'systolic',
          value: sys.latest, pairedValue: dia.latest));
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
  //
  // «Сахар в норме» IS GONE, and it was refused sentence #5 shipping word for
  // word. Blood sugar was withdrawn from the admin panel on 2026-08-13 because
  // the vendor documents the field as 血糖（0.1）with NO UNIT STATED anywhere in
  // 3,248 pages — the computation was deleted rather than stubbed, so that no
  // scale could be quietly reintroduced. The app went on grading the same
  // number against the same absent unit for another day. A withdrawal on one
  // surface is not a withdrawal.
  //
  // Silence is the whole fix for the positive card, and it needs no copy: a
  // number whose unit its own source never states cannot be called normal on
  // any scale, and the pregnancy stakes are specific — GDM screening is a
  // scheduled protocol item, and a reassuring number displaces the OGTT window
  // at 24–28 weeks, which closes.
  //
  // The two WATCH cards are deliberately still here, pending their own ruling.
  // Removing them is not the same act: gate the positives, never the warnings —
  // a missed reassurance costs her a sentence she was owed anyway, a missed
  // warning can cost more. They are refused too (they name a value in the same
  // absent unit) but the replacement is a clinical decision, not this one.
  final glucose = statsFor(buildSeries(samples, 'glucose'));
  if (glucose != null) {
    if (glucose.latest >= GlucoseThresholds.elevatedMmol) {
      watch.add(Advisory('ADV_GLUCOSE_HIGH', AdviceTone.watch, 'glucose', value: glucose.latest));
    } else if (glucose.latest < GlucoseThresholds.lowMmol) {
      watch.add(Advisory('ADV_GLUCOSE_LOW', AdviceTone.watch, 'glucose', value: glucose.latest));
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

  // ---- The absorber: what is said when nothing needs watching ----
  //
  // This is where silencing a metric goes to die. Gating ADV_BP_STEADY on
  // provenance did not produce silence — a day of normal wrist readings fell
  // through to «Всё стабильно», so a blood-pressure reassurance was PROMOTED
  // into a whole-body one, and it travelled to the clipboard too, because the
  // export sends titles only. A broader reassurance is worse than the specific
  // one that was removed.
  //
  // ADV_NOTHING_UNUSUAL claims no more than the readings it was computed from:
  // it is about the READINGS, not about her; it says outright that this is not
  // a health check and that some of the numbers are estimates; and it tells her
  // that feeling unwell outranks it. That last sentence is the load-bearing one
  // — it is what stops a green banner from talking a woman who feels wrong out
  // of calling. Approved copy; see docs/CLINICAL-REVIEW-WATCH.md, refused
  // sentence #21 and "The absorber rule".
  if (watch.isEmpty) {
    return [const Advisory('ADV_NOTHING_UNUSUAL', AdviceTone.positive, 'general'), ...positive];
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

/// Who measured the blood pressure the card would be about.
///
/// Keyed on `systolic`, which is what `sys.latest` is built from, so the
/// provenance and the number cannot come from different readings. A sample
/// carrying only a diastolic value is not a blood-pressure reading, and the
/// advisory it would feed is guarded on both being present anyway.
///
/// Deliberately a SECOND function rather than a parameter on the temperature
/// one, matching the note there: these two are allowed to diverge, and the day
/// one of them earns a different empty case is the day a shared helper quietly
/// applies the wrong rule to the other. Empty means device, so nothing is said.
bool _latestBpIsDeviceEstimate(List<HealthSample> samples) {
  HealthSample? latest;
  for (final s in samples) {
    if (s.systolic == null) continue;
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
