/// Everything the health watch tracks beyond the four triage vitals — activity,
/// sleep, and the wellness signals — in one app-level model.
///
/// PURE Dart → verified by tool/verify_wearable_metrics.dart. Decoupled from the
/// Starmax SDK on purpose: the BLE bridge builds this, the controller stores it,
/// and the dashboard reads it, none of them touching vendor types.
///
/// The heart rate / SpO₂ / blood pressure / temperature still flow through
/// BandTelemetry and triage, because those can raise an emergency. THESE do not
/// — steps and sleep and stress are shown, not triaged — so they live here,
/// apart from the safety path.
///
/// THE ZERO RULE, AGAIN
///
/// The watch reports 0 for a "current" wellness field (stress, breathing rate,
/// blood sugar) it has not measured recently. Those are nullable here and a 0
/// becomes null — an un-measured stress of 0 must read as "no reading", not as
/// perfect calm. Daily TOTALS (steps, calories, distance, sleep) are different:
/// 0 steps at 6am is a real, true zero, so those are plain ints.
library;

class WearableMetrics {
  /// When this snapshot was taken (app clock, stamped by the bridge).
  final DateTime at;

  // Daily totals — 0 is a real value early in the day.
  final int steps;
  final int kcal;
  final int meters;
  final int sleepMinutes;
  final int deepSleepMinutes;
  final int lightSleepMinutes;

  // Current wellness signals — 0 means "not measured" → null.
  final int? stress; // 0–100
  final int? breathRate; // breaths per minute
  final int? bloodSugarTenths; // 0.1 mmol/L units

  /// Whether the watch reports it is being worn — stale readings from a watch on
  /// the nightstand are worth flagging.
  final bool worn;

  const WearableMetrics({
    required this.at,
    this.steps = 0,
    this.kcal = 0,
    this.meters = 0,
    this.sleepMinutes = 0,
    this.deepSleepMinutes = 0,
    this.lightSleepMinutes = 0,
    this.stress,
    this.breathRate,
    this.bloodSugarTenths,
    this.worn = false,
  });

  /// Distance in kilometres.
  double get km => meters / 1000.0;

  /// Blood sugar in mmol/L, or null when unknown.
  double? get bloodSugar => bloodSugarTenths == null ? null : bloodSugarTenths! / 10.0;

  /// True when there is anything worth showing — a watch that has synced nothing
  /// yet (all zeros, no wellness) should not render an empty activity panel.
  bool get hasAnything =>
      steps > 0 ||
      kcal > 0 ||
      meters > 0 ||
      sleepMinutes > 0 ||
      stress != null ||
      breathRate != null ||
      bloodSugarTenths != null;
}
