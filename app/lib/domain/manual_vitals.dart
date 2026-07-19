/// Manual vitals entry — letting someone log a cuff/thermometer/oximeter reading
/// by hand, so the app is useful before (or without) a paired band. PURE Dart →
/// unit-testable via verify_manual_vitals.dart.
///
/// This validates PLAUSIBILITY, not health: the ranges below exist to stop a
/// typo (a systolic of 1200) from poisoning the charts and the triage core. A
/// reading can be perfectly plausible and still be dangerous — judging that is
/// triage's job, and manual readings go through exactly the same triage the band
/// does.
library;

/// Which vital a validation message refers to.
enum VitalField { heartRate, spo2, systolic, diastolic, temperature }

/// Plausible input ranges. Deliberately wide — anything a real person could
/// actually measure is accepted, including clearly dangerous values.
const vitalRanges = <VitalField, ({num min, num max})>{
  VitalField.heartRate: (min: 20, max: 250),
  VitalField.spo2: (min: 50, max: 100),
  VitalField.systolic: (min: 50, max: 260),
  VitalField.diastolic: (min: 30, max: 200),
  VitalField.temperature: (min: 30.0, max: 45.0),
};

bool inVitalRange(VitalField f, num v) {
  final r = vitalRanges[f]!;
  return v >= r.min && v <= r.max;
}

/// A hand-entered reading. Every field is optional — someone may only have a
/// thermometer — but at least one must be present to be worth saving.
class ManualVitals {
  final int? heartRate;
  final int? spo2;
  final int? systolic;
  final int? diastolic;
  final double? temperature;
  const ManualVitals({this.heartRate, this.spo2, this.systolic, this.diastolic, this.temperature});

  bool get isEmpty =>
      heartRate == null && spo2 == null && systolic == null && diastolic == null && temperature == null;
}

/// Why a reading can't be saved. Empty when it's good to go.
enum VitalsError { empty, outOfRange, bloodPressurePartial, diastolicNotBelowSystolic }

/// Validate a hand-entered reading.
///
/// Blood pressure is validated as a PAIR: a lone systolic is meaningless, and a
/// diastolic at or above systolic is a transposition (the classic "120/80 typed
/// as 80/120"), not a real reading.
List<VitalsError> validateVitals(ManualVitals v) {
  final errors = <VitalsError>[];
  if (v.isEmpty) return [VitalsError.empty];

  final checks = <(VitalField, num?)>[
    (VitalField.heartRate, v.heartRate),
    (VitalField.spo2, v.spo2),
    (VitalField.systolic, v.systolic),
    (VitalField.diastolic, v.diastolic),
    (VitalField.temperature, v.temperature),
  ];
  for (final (field, value) in checks) {
    if (value != null && !inVitalRange(field, value)) {
      errors.add(VitalsError.outOfRange);
      break;
    }
  }

  final hasSys = v.systolic != null, hasDia = v.diastolic != null;
  if (hasSys != hasDia) {
    errors.add(VitalsError.bloodPressurePartial);
  } else if (hasSys && hasDia && v.diastolic! >= v.systolic!) {
    errors.add(VitalsError.diastolicNotBelowSystolic);
  }
  return errors;
}

/// Whether the reading can be saved as-is.
bool vitalsAreValid(ManualVitals v) => validateVitals(v).isEmpty;
