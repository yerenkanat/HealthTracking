/// `findings[0]` is the worst finding, not the earliest branch.
///
/// This shipped, and it suppressed an emergency screen.
///
/// `assessTelemetry`'s docstring has always called `findings[0]` "the top
/// finding surfaced in UI/push". It was branch order. That was survivable while
/// every early branch was itself an emergency — and stopped being survivable
/// when `DEVICE_TEMP_HIGH`, a WARNING, was added to the fever block on
/// 2026-08-13, because the fever block runs before oxygen.
///
/// One sample, a band temperature of 37.9 and an SpO2 of 82:
///
///     severity             = emergency        (from the hypoxia)
///     forceEmergencyScreen = true
///     findings[0]          = DEVICE_TEMP_HIGH (a warning)
///
/// `AppController` hands `findings.first` to `EmergencyConfirmation`. So the
/// gate was asked about a warning, in a different `emergencyFamily`, from a
/// sensor source — it answered «ask her to repeat it», the caller returned
/// early, and **the severe-hypoxia emergency screen did not open**. Had it
/// opened later it would have carried a code with no localized message, falling
/// back to EMERGENCY_GENERIC, and printed the TEMPERATURE as the reading that
/// raised an emergency.
///
/// The clinical ruling of 2026-08-13 says no device path may raise an
/// emergency. This defeated the other half of it: a device warning could
/// silence one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/core/triage.dart';

void main() {
  test('an emergency outranks a warning that fired in an earlier branch', () {
    // The exact shipped case. Temperature is checked before oxygen, and this
    // temperature is a device reading, so it yields the warning-tier code.
    const t = BandTelemetry(
      coreTempC: 37.9,
      spo2Pct: 82,
      source: ReadingSource.sensor,
    );
    final r = assessTelemetry(t);

    expect(r.severity, TriageSeverity.emergency);
    expect(r.forceEmergencyScreen, isTrue);
    expect(r.findings.first.code, 'HYPOXIA_SEVERE',
        reason: 'the emergency must be first — this is what the caller hands '
            'to the confirmation gate and prints on the emergency screen');
    expect(r.findings.first.severity, TriageSeverity.emergency);
    // The warning is not discarded, only demoted: it is still a true finding
    // and still belongs in the list.
    expect(r.findings.map((f) => f.code), contains('DEVICE_TEMP_HIGH'));
  });

  test('among equal severities the clinical branch order is untouched', () {
    // Blood pressure is checked before heart rate, and both of these are
    // emergencies. If ranking reordered equals, `findings[0]` would stop
    // matching the TypeScript twin — and no test asserting a single code would
    // notice. Dart's List.sort is NOT stable, which is why the implementation
    // carries the original index into the comparator rather than trusting it.
    const t = BandTelemetry(
      systolicMmHg: 170,
      diastolicMmHg: 115,
      heartRateBpm: 145,
      source: ReadingSource.manual,
    );
    final r = assessTelemetry(t);

    final codes = [for (final f in r.findings) f.code];
    final bp = codes.indexWhere((c) => c.startsWith('PREECLAMPSIA'));
    final hr = codes.indexWhere((c) => c.contains('TACHY'));
    expect(bp, greaterThanOrEqualTo(0), reason: 'the BP emergency should fire');
    expect(hr, greaterThanOrEqualTo(0), reason: 'the HR emergency should fire');
    expect(bp, lessThan(hr),
        reason: 'blood pressure is checked before heart rate and both are '
            'emergencies — ranking must not disturb that order');
  });

  test('a lone warning is still first, so nothing is hidden by ranking', () {
    // The blast-radius check: ranking must not drop or reorder anything when
    // there is only one tier present.
    const t = BandTelemetry(coreTempC: 37.9, source: ReadingSource.sensor);
    final r = assessTelemetry(t);
    expect(r.severity, TriageSeverity.warning);
    expect(r.findings.first.code, 'DEVICE_TEMP_HIGH');
  });
}
