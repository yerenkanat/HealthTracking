/// «Давление ровное» is a verdict on a body, and a wrist cannot deliver it.
///
/// The temperature half of this defect was refused as sentence #15 in
/// docs/CLINICAL-REVIEW-WATCH.md and fixed in `generateAdvisories`. Blood
/// pressure sat four lines above it in the SAME function, doing the same thing,
/// and shipped in all three languages for another week.
///
/// It is the worse of the two:
///
///   * the review puts wrist PPG blood pressure at ±10–15 mmHg against a 140
///     threshold, so the uncertainty is the size of the decision;
///   * `bpCalibrationMaxAgeDays` exists because the calibration behind that
///     estimate expires, and nothing on this path checks whether it has;
///   * the antenatal protocol pairs blood pressure with urine protein at every
///     visit from the second — so unlike a temperature, a reassurance here can
///     defer a check that is actually scheduled.
///
/// What is NOT being claimed: that the app should go quiet about a high
/// reading. Refusing to reassure and refusing to warn are different decisions,
/// and only the first is made here. The last test pins that distinction,
/// because the obvious over-correction is to silence the whole branch.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/domain/health_advisor.dart';
// Also brings ReadingSource, which health_series re-exports so a decoder needs
// one import rather than two.
import 'package:fcs_app/domain/health_series.dart';

List<String> _codes(List<Advisory> a) => [for (final x in a) x.code];

/// Three readings, because `generateAdvisories` says nothing below `minSamples`.
List<HealthSample> _bp(double sys, double dia, ReadingSource source) => [
      for (var i = 0; i < 3; i++)
        HealthSample(
          at: DateTime(2026, 8, 14, 9 + i),
          systolic: sys,
          diastolic: dia,
          source: source,
        ),
    ];

void main() {
  group('the advisor does not call a wrist estimate normal', () {
    test('a device reading in range earns NO reassurance', () {
      final codes = _codes(generateAdvisories(_bp(118, 76, ReadingSource.sensor)));
      expect(codes, isNot(contains('ADV_BP_STEADY')));
    });

    test('a cuff reading she typed in still does', () {
      // The whole point of branching on provenance rather than deleting the
      // card: a real instrument keeps its voice. If this ever goes silent the
      // fix has become "say nothing about blood pressure", which is a different
      // and unreviewed decision.
      final codes = _codes(generateAdvisories(_bp(118, 76, ReadingSource.manual)));
      expect(codes, contains('ADV_BP_STEADY'));
    });

    test('a stored row with no provenance is treated as a wrist, not a cuff', () {
      // The safe reading of an ambiguous row. Assuming manual would restore the
      // defect across every legacy row at once — and this is not hypothetical:
      // GET /vitals/manual does not currently emit `source`, so these are the
      // rows a woman gets back after changing handsets.
      final legacy = HealthSample.fromJson(const {
        'recordedAt': '2026-08-01T09:00:00.000',
        'systolicMmHg': 118.0,
        'diastolicMmHg': 76.0,
      });
      expect(legacy.isDeviceEstimate, isTrue);
      expect(_codes(generateAdvisories([legacy, legacy, legacy])),
          isNot(contains('ADV_BP_STEADY')));
    });

    test('provenance follows the newest reading, not the last one in the list', () {
      // The number comes from `statsFor(buildSeries(...)).latest`, which is
      // CHRONOLOGICAL. If the provenance check used list order instead, the two
      // could describe different readings — and the card would be about one
      // while claiming the authority of the other.
      final samples = [
        HealthSample(
          at: DateTime(2026, 8, 14, 18),
          systolic: 118,
          diastolic: 76,
          source: ReadingSource.sensor,
        ),
        HealthSample(
          at: DateTime(2026, 8, 14, 9),
          systolic: 117,
          diastolic: 75,
          source: ReadingSource.manual,
        ),
        HealthSample(
          at: DateTime(2026, 8, 14, 10),
          systolic: 119,
          diastolic: 77,
          source: ReadingSource.manual,
        ),
      ];
      // Newest is the 18:00 wrist estimate, though a manual reading is last in
      // the list. No reassurance.
      expect(_codes(generateAdvisories(samples)), isNot(contains('ADV_BP_STEADY')));
    });

    test('a HIGH reading still warns, whoever measured it', () {
      // The blast-radius guard, and the reason this fix is scoped to the
      // positive card only. Silencing a warning because the sensor is imprecise
      // would be the same error in the opposite direction — and worse, because
      // the cost of a missed warning is not symmetrical with the cost of a
      // missed reassurance.
      final codes = _codes(generateAdvisories(_bp(138, 88, ReadingSource.sensor)));
      expect(codes, contains('ADV_BP_ELEVATED'));
    });
  });
}
