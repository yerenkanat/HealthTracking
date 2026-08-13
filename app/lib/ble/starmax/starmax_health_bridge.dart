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
    met: _nz(s.met),
    worn: s.isWorn,
  );
}

/// Map a snapshot to telemetry. Blood pressure is included but, like the band's,
/// is watch-estimated; triage treats it accordingly.
///
/// Blood sugar rides along because BandTelemetry is the ONLY thing that reaches
/// `/ingest` — and `pregnancy_health_metrics.glucose_mmol` has been waiting for
/// it since the column was added. It was dropped here, so the watch's estimate
/// reached the dashboard tile and the local advisor and stopped at the handset:
/// her clinician's view showed glucose only for readings she had typed in. It is
/// a wellness value, not a triage vital — `assessTelemetry` never reads it, so
/// carrying it cannot raise an emergency.
BandTelemetry bandTelemetryFromSnapshot(StarmaxHealthSnapshot s) {
  return BandTelemetry(
    // NOT coreTempC. The vendor names the quantity (`当前体温`) and states
    // neither a measurement site nor an accuracy, so there is no defensible
    // conversion to a core estimate — and applying the OEM band's
    // `skinToCoreTempC` to it would be inventing a calibration, which is worse
    // than leaving it raw. It rides along like glucose: carried to the server,
    // shown, graded, never triaged. See docs/CLINICAL-REVIEW-WATCH.md.
    deviceTempC: s.tempCelsius, // null when unknown or out of the plausible band
    heartRateBpm: _nz(s.heartRate),
    spo2Pct: _nz(s.bloodOxygen),
    systolicMmHg: _nz(s.bpSystolic),
    diastolicMmHg: _nz(s.bpDiastolic),
    glucoseMmol: s.bloodSugar == 0 ? null : s.bloodSugar / 10.0,
    // The snapshot has no sleep flag; the daytime path never claims sleep.
    duringSleep: false,
    // A watch measured this, not a woman with a thermometer. Stated rather than
    // defaulted: the fever rule branches on it, and the whole point of the
    // branch is that this side of it may warn and may not escalate.
    source: ReadingSource.sensor,
  );
}

/// True when a snapshot carries at least one usable vital — worth pushing
/// through triage. An all-zero snapshot (watch idle, not worn) is dropped rather
/// than emitted as an empty reading.
///
/// Blood sugar counts even though it is never triaged: this same predicate gates
/// the only path to `/ingest`, so a snapshot whose one measured value is glucose
/// would otherwise be discarded before it could be stored anywhere but memory.
bool snapshotHasVitals(StarmaxHealthSnapshot s) =>
    s.heartRate != 0 ||
    s.bloodOxygen != 0 ||
    s.tempCelsius != null ||
    s.bloodSugar != 0;
