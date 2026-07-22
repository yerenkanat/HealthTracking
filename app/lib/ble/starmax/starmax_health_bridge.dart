/// Turn a Starmax health snapshot into the app's own [BandTelemetry], so the
/// watch feeds exactly the same triage → dashboard → batching pipeline the OEM
/// band does.
///
/// PURE Dart → verified in test/starmax_client_test.dart. The only real work is
/// the "0 means unknown" rule: the watch reports 0 for a metric it has not
/// measured recently, and a 0 heart rate pushed into triage would read as a
/// dangerous bradycardia. Every field maps 0 → null so triage sees "no reading",
/// not a false emergency.
library;

import '../../core/triage.dart';
import '../../domain/wearable_metrics.dart';
import 'starmax_frames.dart';

int? _nz(int v) => v == 0 ? null : v;

/// Map a snapshot to the app-level [WearableMetrics] — the activity, sleep and
/// wellness fields the triage path drops. [at] is stamped by the caller (the
/// clock is not reachable from a pure function).
WearableMetrics wearableMetricsFromSnapshot(StarmaxHealthSnapshot s, DateTime at) {
  return WearableMetrics(
    at: at,
    steps: s.totalSteps,
    kcal: s.totalKcal,
    meters: s.totalMeters,
    sleepMinutes: s.totalSleepMin,
    deepSleepMinutes: s.deepSleepMin,
    lightSleepMinutes: s.lightSleepMin,
    stress: _nz(s.stress),
    breathRate: _nz(s.breathRate),
    bloodSugarTenths: _nz(s.bloodSugar),
    worn: s.isWorn,
  );
}

/// Map a snapshot to telemetry. Blood pressure is included but, like the band's,
/// is watch-estimated; triage treats it accordingly.
BandTelemetry bandTelemetryFromSnapshot(StarmaxHealthSnapshot s) {
  return BandTelemetry(
    coreTempC: s.tempCelsius, // already null when unknown
    heartRateBpm: _nz(s.heartRate),
    spo2Pct: _nz(s.bloodOxygen),
    systolicMmHg: _nz(s.bpSystolic),
    diastolicMmHg: _nz(s.bpDiastolic),
    // The snapshot has no sleep flag; the daytime path never claims sleep.
    duringSleep: false,
  );
}

/// True when a snapshot carries at least one usable vital — worth pushing
/// through triage. An all-zero snapshot (watch idle, not worn) is dropped rather
/// than emitted as an empty reading.
bool snapshotHasVitals(StarmaxHealthSnapshot s) =>
    s.heartRate != 0 || s.bloodOxygen != 0 || s.tempCelsius != null;
