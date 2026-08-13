/// CANONICAL MEDICAL TRIAGE — Dart / on-device (Flutter) implementation.
///
/// This is the exact behavioural twin of the Node backend's `triage.ts`. Both
/// consume the shared JSON contract in `packages/contract/` and are held identical
/// by the golden vectors (see app/test + packages/shared conformance suites).
///
/// Runs ON-DEVICE on every telemetry frame so an emergency escalates instantly,
/// even with no network. Pure Dart (only dart:core/math) → unit-testable without
/// Flutter. Owned by the OB-GYN specialist.
library;

import '../domain/emergency_confirmation.dart' show ReadingSource;

/// Re-exported so anything that already imports the triage rules can name the
/// provenance of a reading without a second import. There is ONE vocabulary in
/// this app for "where did this number come from", and this is it.
export '../domain/emergency_confirmation.dart' show ReadingSource;

/// Thresholds — MUST equal packages/contract/triage_thresholds.json.
/// A contract test loads that JSON and asserts equality, so these cannot drift.
class TriageThresholds {
  static const bpSystolicEmergency = 140;
  static const bpDiastolicEmergency = 90;
  static const bpSystolicSevere = 160;
  static const bpDiastolicSevere = 110;
  static const feverEmergencyC = 38.5;
  static const feverWarningC = 37.8;
  static const spo2Emergency = 90;
  static const spo2Warning = 95;
  static const hrTachyWarning = 120;
  static const hrTachyEmergency = 140;
  static const hrBradyWarning = 50;
  static const hrBradyEmergency = 40;
}

enum TriageSeverity { ok, info, warning, emergency }

int _rank(TriageSeverity s) => switch (s) {
      TriageSeverity.ok => 0,
      TriageSeverity.info => 1,
      TriageSeverity.warning => 2,
      TriageSeverity.emergency => 3,
    };

TriageSeverity _maxSeverity(TriageSeverity a, TriageSeverity b) =>
    _rank(a) >= _rank(b) ? a : b;

TriageSeverity severityFromString(String s) => switch (s) {
      'info' => TriageSeverity.info,
      'warning' => TriageSeverity.warning,
      'emergency' => TriageSeverity.emergency,
      _ => TriageSeverity.ok,
    };

String severityToString(TriageSeverity s) => s.name;

class BandTelemetry {
  final double? coreTempC;
  final double? skinTempC;

  /// A temperature a DEVICE reported with no stated measurement site and no
  /// stated accuracy — today the Starmax watch's `当前体温`.
  ///
  /// Deliberately not [coreTempC]. The vendor names the quantity and nothing
  /// else, so there is no defensible conversion to a core estimate, and
  /// applying the band's `skinToCoreTempC` to it would be inventing a
  /// calibration. Every consumer of `coreTempC` reads it as "estimated core
  /// temperature"; this one has not earned that reading.
  ///
  /// Carried, shown and graded — never triaged, exactly like [glucoseMmol].
  /// See docs/CLINICAL-REVIEW-WATCH.md, "Device temperature — closed
  /// 2026-08-13".
  final double? deviceTempC;
  final int? heartRateBpm;
  final int? spo2Pct;
  final int? systolicMmHg;
  final int? diastolicMmHg;
  // Blood glucose in mmol/L. A WELLNESS reading (typed glucometer / band estimate).
  // Carried so it syncs to the backend, but assessTelemetry never reads it — it is
  // not a triage vital and must never force the Emergency screen.
  final double? glucoseMmol;
  final bool duringSleep;

  /// How this reading was obtained — the branch the fever rule turns on.
  ///
  /// Defaults to [ReadingSource.manual] because the ONLY place this class is
  /// built by hand is the typed-reading path (`AppController.logManualVitals`);
  /// every device path is a decoder — `band_parser`, `ble_device_manager`,
  /// `starmax_health_bridge` — and each states [ReadingSource.sensor]
  /// explicitly, pinned by test. The default is chosen in the direction that
  /// cannot DISARM the one escalation this product is entitled to make: a
  /// thermometer reading she typed in. A missing label on a device path costs a
  /// false alarm; a missing label on the manual path would cost a real fever.
  ///
  /// [fromJson] deliberately defaults the other way — see there.
  final ReadingSource source;

  const BandTelemetry({
    this.coreTempC,
    this.skinTempC,
    this.deviceTempC,
    this.heartRateBpm,
    this.spo2Pct,
    this.systolicMmHg,
    this.diastolicMmHg,
    this.glucoseMmol,
    this.duringSleep = false,
    this.source = ReadingSource.manual,
  });

  /// Wire name for [source]. 'band' is the server's word for "a device
  /// measured this" (`packages/shared/src/types.ts`), and one vocabulary on the
  /// wire is worth more than a prettier one.
  static String sourceToWire(ReadingSource s) =>
      s == ReadingSource.manual ? 'manual' : 'band';

  /// Anything that is not explicitly 'manual' — including ABSENT — is read as a
  /// device reading. A row written before provenance existed cannot be shown to
  /// have come off a thermometer, and the safe interpretation of an unlabelled
  /// temperature is the one that neither escalates nor reassures.
  static ReadingSource sourceFromWire(Object? v) =>
      v == 'manual' ? ReadingSource.manual : ReadingSource.sensor;

  factory BandTelemetry.fromJson(Map<String, dynamic> j) => BandTelemetry(
        coreTempC: (j['coreTempC'] as num?)?.toDouble(),
        skinTempC: (j['skinTempC'] as num?)?.toDouble(),
        deviceTempC: (j['deviceTempC'] as num?)?.toDouble(),
        heartRateBpm: (j['heartRateBpm'] as num?)?.toInt(),
        spo2Pct: (j['spo2Pct'] as num?)?.toInt(),
        systolicMmHg: (j['systolicMmHg'] as num?)?.toInt(),
        diastolicMmHg: (j['diastolicMmHg'] as num?)?.toInt(),
        glucoseMmol: (j['glucoseMmol'] as num?)?.toDouble(),
        duringSleep: (j['duringSleep'] as bool?) ?? false,
        source: sourceFromWire(j['source']),
      );

  /// Sensor fields only (no deviceId/recordedAt — the transport layer stamps those).
  Map<String, dynamic> toJson() => {
        if (coreTempC != null) 'coreTempC': coreTempC,
        if (skinTempC != null) 'skinTempC': skinTempC,
        if (deviceTempC != null) 'deviceTempC': deviceTempC,
        'source': sourceToWire(source),
        if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
        if (spo2Pct != null) 'spo2Pct': spo2Pct,
        if (systolicMmHg != null) 'systolicMmHg': systolicMmHg,
        if (diastolicMmHg != null) 'diastolicMmHg': diastolicMmHg,
        if (glucoseMmol != null) 'glucoseMmol': glucoseMmol,
        'duringSleep': duringSleep,
      };
}

class TriageFinding {
  final String code;
  final TriageSeverity severity;
  final String metric;
  final String message;
  final num? value;
  final num? threshold;
  const TriageFinding({
    required this.code,
    required this.severity,
    required this.metric,
    required this.message,
    this.value,
    this.threshold,
  });
}

class TriageResult {
  final TriageSeverity severity;
  final List<TriageFinding> findings;
  final bool forceEmergencyScreen;
  const TriageResult(this.severity, this.findings, this.forceEmergencyScreen);
}

/// Pure, synchronous. Branch order matches triage.ts exactly so `findings[0]`
/// (the "top" finding surfaced in UI/push) is identical across languages.
TriageResult assessTelemetry(BandTelemetry t) {
  final findings = <TriageFinding>[];

  // --- Blood pressure (preeclampsia) ---
  if (t.systolicMmHg != null || t.diastolicMmHg != null) {
    final sys = t.systolicMmHg ?? 0;
    final dia = t.diastolicMmHg ?? 0;
    if (sys >= TriageThresholds.bpSystolicSevere || dia >= TriageThresholds.bpDiastolicSevere) {
      findings.add(TriageFinding(
        code: 'PREECLAMPSIA_BP_SEVERE',
        severity: TriageSeverity.emergency,
        metric: sys >= TriageThresholds.bpSystolicSevere ? 'systolicMmHg' : 'diastolicMmHg',
        value: sys >= TriageThresholds.bpSystolicSevere ? sys : dia,
        threshold: sys >= TriageThresholds.bpSystolicSevere ? TriageThresholds.bpSystolicSevere : TriageThresholds.bpDiastolicSevere,
        message:
            'Severe-range blood pressure detected. This can signal severe preeclampsia. Seek emergency care now.',
      ));
    } else if (sys >= TriageThresholds.bpSystolicEmergency || dia >= TriageThresholds.bpDiastolicEmergency) {
      findings.add(TriageFinding(
        code: 'PREECLAMPSIA_BP',
        severity: TriageSeverity.emergency,
        metric: sys >= TriageThresholds.bpSystolicEmergency ? 'systolicMmHg' : 'diastolicMmHg',
        value: sys >= TriageThresholds.bpSystolicEmergency ? sys : dia,
        threshold: sys >= TriageThresholds.bpSystolicEmergency ? TriageThresholds.bpSystolicEmergency : TriageThresholds.bpDiastolicEmergency,
        message:
            'High blood pressure detected — a warning sign of preeclampsia. Contact your doctor immediately.',
      ));
    }
  }

  // --- Fever ---
  //
  // BRANCHES ON PROVENANCE, and the twin in packages/shared/src/triage.ts does
  // the same. See docs/CLINICAL-REVIEW-WATCH.md, "Device temperature — closed
  // 2026-08-13": no device path may raise `emergency`, not because a wrist
  // sensor is imprecise but because the error source the conversion would have
  // to correct for — the room, the bedding, the strap — is not one of its
  // inputs, and that error is systematic rather than transient, so the
  // two-minute confirmation gate confirms it rather than filtering it.
  //
  // A thermometer reading she typed in is unchanged, at full emergency weight.
  // It is the one temperature this product is entitled to escalate on, and the
  // device branch's job is to route her to it.
  if (t.coreTempC != null) {
    if (t.source != ReadingSource.manual) {
      if (t.coreTempC! >= TriageThresholds.feverWarningC) {
        findings.add(TriageFinding(
          // MUST NOT end in 'FEVER': emergencyFamily() sweeps anything matching
          // endsWith('FEVER') into the escalation gate. The name is load-bearing.
          code: 'DEVICE_TEMP_HIGH',
          severity: TriageSeverity.warning,
          metric: 'coreTempC',
          value: t.coreTempC,
          threshold: TriageThresholds.feverWarningC,
          message:
              'The device estimated a raised temperature. A wrist sensor cannot tell a fever from a warm room. Take your temperature with a thermometer and enter it here; call your doctor today if it is raised or you feel unwell.',
        ));
      }
    } else if (t.coreTempC! >= TriageThresholds.feverEmergencyC) {
      findings.add(TriageFinding(
        code: 'HIGH_FEVER',
        severity: TriageSeverity.emergency,
        metric: 'coreTempC',
        value: t.coreTempC,
        threshold: TriageThresholds.feverEmergencyC,
        message: 'High fever detected during pregnancy. Urgent medical review is needed.',
      ));
    } else if (t.coreTempC! >= TriageThresholds.feverWarningC) {
      findings.add(TriageFinding(
        code: 'LOW_FEVER',
        severity: TriageSeverity.warning,
        metric: 'coreTempC',
        value: t.coreTempC,
        threshold: TriageThresholds.feverWarningC,
        message: 'Raised temperature. Rest, hydrate, and monitor. Call your clinic if it climbs.',
      ));
    }
  }

  // --- SpO2 (sleep hypoxia) ---
  if (t.spo2Pct != null) {
    if (t.spo2Pct! < TriageThresholds.spo2Emergency) {
      findings.add(TriageFinding(
        code: 'HYPOXIA_SEVERE',
        severity: TriageSeverity.emergency,
        metric: 'spo2Pct',
        value: t.spo2Pct,
        threshold: TriageThresholds.spo2Emergency,
        message: 'Very low blood oxygen detected. Seek emergency care now.',
      ));
    } else if (t.spo2Pct! < TriageThresholds.spo2Warning) {
      findings.add(TriageFinding(
        code: 'HYPOXIA_SLEEP',
        severity: t.duringSleep ? TriageSeverity.warning : TriageSeverity.info,
        metric: 'spo2Pct',
        value: t.spo2Pct,
        threshold: TriageThresholds.spo2Warning,
        message:
            'Blood oxygen dipped below 95% during sleep. If this repeats, discuss sleep-disordered breathing with your doctor.',
      ));
    }
  }

  // --- Heart rate (pregnancy-adjusted) ---
  if (t.heartRateBpm != null) {
    final hr = t.heartRateBpm!;
    if (hr >= TriageThresholds.hrTachyEmergency || hr <= TriageThresholds.hrBradyEmergency) {
      findings.add(TriageFinding(
        code: hr >= TriageThresholds.hrTachyEmergency ? 'TACHYCARDIA_SEVERE' : 'BRADYCARDIA_SEVERE',
        severity: TriageSeverity.emergency,
        metric: 'heartRateBpm',
        value: hr,
        threshold: hr >= TriageThresholds.hrTachyEmergency ? TriageThresholds.hrTachyEmergency : TriageThresholds.hrBradyEmergency,
        message: 'Dangerous heart rate detected. Seek urgent medical help.',
      ));
    } else if (hr >= TriageThresholds.hrTachyWarning || hr <= TriageThresholds.hrBradyWarning) {
      findings.add(TriageFinding(
        code: hr >= TriageThresholds.hrTachyWarning ? 'TACHYCARDIA' : 'BRADYCARDIA',
        severity: TriageSeverity.warning,
        metric: 'heartRateBpm',
        value: hr,
        threshold: hr >= TriageThresholds.hrTachyWarning ? TriageThresholds.hrTachyWarning : TriageThresholds.hrBradyWarning,
        message:
            'Your heart rate is outside the expected range while resting. Sit down and re-measure.',
      ));
    }
  }

  var severity = TriageSeverity.ok;
  for (final f in findings) {
    severity = _maxSeverity(severity, f.severity);
  }
  return TriageResult(severity, findings, severity == TriageSeverity.emergency);
}
