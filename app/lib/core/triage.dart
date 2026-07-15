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
  final int? heartRateBpm;
  final int? spo2Pct;
  final int? systolicMmHg;
  final int? diastolicMmHg;
  final bool duringSleep;

  const BandTelemetry({
    this.coreTempC,
    this.skinTempC,
    this.heartRateBpm,
    this.spo2Pct,
    this.systolicMmHg,
    this.diastolicMmHg,
    this.duringSleep = false,
  });

  factory BandTelemetry.fromJson(Map<String, dynamic> j) => BandTelemetry(
        coreTempC: (j['coreTempC'] as num?)?.toDouble(),
        skinTempC: (j['skinTempC'] as num?)?.toDouble(),
        heartRateBpm: (j['heartRateBpm'] as num?)?.toInt(),
        spo2Pct: (j['spo2Pct'] as num?)?.toInt(),
        systolicMmHg: (j['systolicMmHg'] as num?)?.toInt(),
        diastolicMmHg: (j['diastolicMmHg'] as num?)?.toInt(),
        duringSleep: (j['duringSleep'] as bool?) ?? false,
      );

  /// Sensor fields only (no deviceId/recordedAt — the transport layer stamps those).
  Map<String, dynamic> toJson() => {
        if (coreTempC != null) 'coreTempC': coreTempC,
        if (skinTempC != null) 'skinTempC': skinTempC,
        if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
        if (spo2Pct != null) 'spo2Pct': spo2Pct,
        if (systolicMmHg != null) 'systolicMmHg': systolicMmHg,
        if (diastolicMmHg != null) 'diastolicMmHg': diastolicMmHg,
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
  if (t.coreTempC != null) {
    if (t.coreTempC! >= TriageThresholds.feverEmergencyC) {
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
