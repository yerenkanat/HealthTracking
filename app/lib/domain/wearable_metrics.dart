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
  /// The watch's raw blood-sugar value, exactly as the frame carries it.
  ///
  /// The comment here used to read «0.1 mmol/L units». That was the false claim
  /// in source form: the vendor documents the field as `当前血糖（0.1）`, which
  /// states a decimal place and NO UNIT — not in 3,248 pages. The name keeps
  /// `Tenths` because tenths-of-something is the one thing the vendor does say.
  ///
  /// So there is no `bloodSugar` getter any more, and its removal is the point
  /// rather than tidying: `/ 10.0` was where the unit was invented, and a
  /// stubbed conversion is a conversion waiting to be un-stubbed. The integer
  /// is carried and stored (the `glucoseMmol` precedent — carried, never
  /// triaged); nothing may convert it to a scale or print it beside one.
  final int? bloodSugarTenths;

  /// The watch's metabolic-equivalent estimate for the current activity — the
  /// vendor's `met` byte. 0 means "not measured" → null, like the other current
  /// signals. Parsed since the first version of the frame decoder and dropped by
  /// the bridge, so it reached nothing at all.
  final int? met;

  /// The watch's own battery, as a percentage, and whether it is on the
  /// charger. Null when no battery read has succeeded — never a guess: a watch
  /// whose battery we could not read is not a watch at 0 %.
  ///
  /// This is an indicator the SDK exposes (frame 134) that nothing ever asked
  /// for: [StarmaxClient.readPower] had no caller outside its own test, so a
  /// watch that had run flat looked exactly like a watch that was simply quiet.
  final int? batteryPercent;
  final bool charging;

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
    this.met,
    this.batteryPercent,
    this.charging = false,
    this.worn = false,
  });

  /// The same snapshot with a battery reading attached — the manager reads the
  /// battery on its own frame, so the two arrive separately and are joined
  /// rather than re-parsed.
  WearableMetrics withPower({int? percent, bool charging = false}) => WearableMetrics(
        at: at,
        steps: steps,
        kcal: kcal,
        meters: meters,
        sleepMinutes: sleepMinutes,
        deepSleepMinutes: deepSleepMinutes,
        lightSleepMinutes: lightSleepMinutes,
        stress: stress,
        breathRate: breathRate,
        bloodSugarTenths: bloodSugarTenths,
        met: met,
        batteryPercent: percent,
        charging: charging,
        worn: worn,
      );

  /// Distance in kilometres.
  double get km => meters / 1000.0;

  /// True when there is anything worth showing IN THE ACTIVITY PANEL — a watch
  /// that has synced nothing yet should not render an empty panel. Sleep is
  /// excluded on purpose: it is shown by the dedicated Sleep card, not here, so
  /// a sleep-only sync must not open an otherwise-empty activity panel.
  ///
  /// Blood sugar is excluded for the same reason, and it is a consequence of
  /// the ruling rather than a taste: the wellness grid no longer has a
  /// blood-sugar tile, so a snapshot whose only measured value is the watch's
  /// raw sugar has nothing to draw. Left in, it would open an empty panel —
  /// which is the defect this getter exists to prevent, arriving from the other
  /// direction. It is also nothing to sync: [toIngestPayload] does not carry
  /// the field, the telemetry record does.
  bool get hasAnything =>
      steps > 0 ||
      kcal > 0 ||
      meters > 0 ||
      stress != null ||
      breathRate != null;

  /// True when this snapshot carries anything the SERVER does not already have
  /// by another route — the test for "is this worth a network write".
  ///
  /// Wider than [hasAnything], which asks a display question. The battery, the
  /// MET estimate and the off-wrist flag are all things her clinician's view and
  /// the operator's fleet view need, and none of them opens the activity panel.
  bool get hasAnythingToSync =>
      hasAnything || met != null || batteryPercent != null || sleepMinutes > 0;

  /// The wire form for `/ingest/batch` (a `wearable` item).
  ///
  /// The day is the LOCAL date of [at]: the watch's step/calorie/distance
  /// figures are its own daily totals and roll over at the wearer's midnight,
  /// not at UTC's. Sending the UTC date would file an evening's walk in Almaty
  /// (UTC+5) under the following day for every user in the country.
  ///
  /// Only measured fields are sent. A watch that has not measured stress must
  /// not write a 0 into a stress column — a zero read back is a reading.
  Map<String, dynamic> toIngestPayload({required String deviceId}) => {
        'deviceId': deviceId,
        'day': '${at.year.toString().padLeft(4, '0')}-'
            '${at.month.toString().padLeft(2, '0')}-'
            '${at.day.toString().padLeft(2, '0')}',
        'recordedAt': at.toUtc().toIso8601String(),
        'steps': steps,
        'kcal': kcal,
        'meters': meters,
        'sleepMinutes': sleepMinutes,
        'deepSleepMinutes': deepSleepMinutes,
        'lightSleepMinutes': lightSleepMinutes,
        if (stress != null) 'stress': stress,
        if (breathRate != null) 'breathRate': breathRate,
        if (met != null) 'met': met,
        if (batteryPercent != null) 'batteryPercent': batteryPercent,
        'charging': charging,
        'worn': worn,
      };
}
