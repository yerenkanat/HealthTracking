/// Controller tests for hand-entered vitals — in particular that a manual
/// reading is triaged exactly like a measured one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/manual_vitals.dart';

void main() {
  test('a valid reading is stored and charted', () async {
    final c = AppController(now: () => DateTime(2026, 7, 16, 9));
    expect(c.samples, isEmpty);

    final ok = c.logManualVitals(const ManualVitals(heartRate: 72, spo2: 98, systolic: 118, diastolic: 76, temperature: 36.6));
    expect(ok, isTrue);
    expect(c.samples, hasLength(1));
    expect(c.samples.single.heartRate, 72);
    expect(c.samples.single.systolic, 118);
    await c.dispose();
  });

  test('an invalid reading changes nothing', () async {
    final c = AppController(now: () => DateTime(2026, 7, 16, 9));
    // Transposed blood pressure — a typo, not a reading.
    expect(c.logManualVitals(const ManualVitals(systolic: 80, diastolic: 120)), isFalse);
    expect(c.logManualVitals(const ManualVitals()), isFalse); // nothing entered
    expect(c.logManualVitals(const ManualVitals(heartRate: 900)), isFalse); // typo
    expect(c.samples, isEmpty);
    await c.dispose();
  });

  test('a dangerous hand-typed reading raises the same emergency as the band', () async {
    final c = AppController(now: () => DateTime(2026, 7, 16, 9));
    expect(c.emergencyActive, isFalse);

    // Severe hypertension: plausible enough to accept, dangerous enough to escalate.
    final ok = c.logManualVitals(const ManualVitals(systolic: 190, diastolic: 125));
    expect(ok, isTrue, reason: 'a real (if alarming) reading must be accepted');
    expect(c.emergencyActive, isTrue, reason: 'typed readings must not be treated as safer than measured ones');
    expect(c.route, AppRoute.emergency);
    await c.dispose();
  });

  test('an ordinary reading does not escalate', () async {
    final c = AppController(now: () => DateTime(2026, 7, 16, 9));
    c.logManualVitals(const ManualVitals(heartRate: 70, spo2: 98, systolic: 115, diastolic: 75));
    expect(c.emergencyActive, isFalse);
    expect(c.route, AppRoute.home);
    await c.dispose();
  });
}
