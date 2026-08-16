import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';

/// The grade behind the vital-signs colour code (green/amber/red — and ink,
/// where the product is not judging). Thresholds must stay aligned with the
/// advisor + triage layers.
void main() {
  group('metricStatus — systolic', () {
    test('normal below 135', () => expect(metricStatus('systolic', 118), MetricStatus.normal));
    test('watch at the elevated band', () => expect(metricStatus('systolic', 136), MetricStatus.watch));
    test('watch at the 135 boundary', () => expect(metricStatus('systolic', 135), MetricStatus.watch));
    test('danger at the emergency cutoff', () => expect(metricStatus('systolic', 140), MetricStatus.danger));
  });

  group('metricStatus — diastolic', () {
    test('normal', () => expect(metricStatus('diastolic', 76), MetricStatus.normal));
    test('watch at 85', () => expect(metricStatus('diastolic', 85), MetricStatus.watch));
    test('danger at 90', () => expect(metricStatus('diastolic', 92), MetricStatus.danger));
  });

  group('metricStatus — heart rate (two-sided)', () {
    test('normal resting', () => expect(metricStatus('hr', 72), MetricStatus.normal));
    test('watch when tachy', () => expect(metricStatus('hr', 122), MetricStatus.watch));
    test('watch when brady at 50', () => expect(metricStatus('hr', 50), MetricStatus.watch));
    test('danger when severely tachy', () => expect(metricStatus('hr', 145), MetricStatus.danger));
    test('danger when severely brady', () => expect(metricStatus('hr', 38), MetricStatus.danger));
  });

  group('metricStatus — spo2 (low is bad)', () {
    test('normal', () => expect(metricStatus('spo2', 98), MetricStatus.normal));
    test('watch below 95', () => expect(metricStatus('spo2', 94), MetricStatus.watch));
    test('danger below 90', () => expect(metricStatus('spo2', 89), MetricStatus.danger));
  });

  group('metricStatus — temperature', () {
    test('normal', () => expect(metricStatus('temp', 36.7), MetricStatus.normal));
    test('watch at fever warning', () => expect(metricStatus('temp', 37.9), MetricStatus.watch));
    test('danger at high fever', () => expect(metricStatus('temp', 38.6), MetricStatus.danger));
  });

  group('metricStatus — glucose (mmol/L, two-sided)', () {
    test('normal casual reading', () => expect(metricStatus('glucose', 5.4), MetricStatus.normal));
    test('watch when elevated (GDM screening band)', () => expect(metricStatus('glucose', 8.2), MetricStatus.watch));
    test('watch when mildly low', () => expect(metricStatus('glucose', 3.6), MetricStatus.watch));
    test('danger when diabetes-range high', () => expect(metricStatus('glucose', 12.0), MetricStatus.danger));
    test('danger when severely low', () => expect(metricStatus('glucose', 2.8), MetricStatus.danger));
  });

  group('metricStatus — watch wellness metrics (watch-tier only)', () {
    test('calm stress is normal', () => expect(metricStatus('stress', 40), MetricStatus.normal));
    test('high stress is a soft watch, never danger', () {
      expect(metricStatus('stress', 72), MetricStatus.watch);
      expect(metricStatus('stress', 100), isNot(MetricStatus.danger));
    });
    test('normal breathing is normal', () => expect(metricStatus('breathRate', 16), MetricStatus.normal));
    test('fast breathing is a watch', () => expect(metricStatus('breathRate', 26), MetricStatus.watch));
    test('slow breathing is a watch', () => expect(metricStatus('breathRate', 8), MetricStatus.watch));
  });

  group('worstStatus', () {
    test('empty is normal', () => expect(worstStatus(const []), MetricStatus.normal));
    test('picks the most severe', () {
      expect(worstStatus([MetricStatus.normal, MetricStatus.watch]), MetricStatus.watch);
      expect(worstStatus([MetricStatus.watch, MetricStatus.danger, MetricStatus.normal]), MetricStatus.danger);
    });

    test('an ungraded half makes the pair ungraded', () {
      // «118 / 76» is ONE reading. A pair holding a half the product may not
      // judge cannot come out `normal` and be painted teal — that is refused
      // sentence #23 arriving through a card whose halves are graded apart.
      expect(worstStatus([MetricStatus.ungraded, MetricStatus.normal]),
          MetricStatus.ungraded);
      expect(worstStatus([MetricStatus.normal, MetricStatus.ungraded]),
          MetricStatus.ungraded);
    });

    test('the declaration order agrees with the ranking', () {
      // Belt and braces, and the braces are the point. `worstStatus` ranks
      // explicitly rather than by `s.index`, because an enum index is a
      // declaration order and the gate named this as the trap. The enum is
      // ALSO declared in that order, so a call site that reaches for `.index`
      // by habit lands on the same answer instead of a wrong one — and this
      // test is what stops the two drifting apart.
      expect(MetricStatus.values, [
        MetricStatus.normal,
        MetricStatus.ungraded,
        MetricStatus.watch,
        MetricStatus.danger,
      ]);
    });

    test('but a warning in either half still wins', () {
      // The other direction, and the corollary that governs it: silence about
      // one number never suppresses a warning about the other.
      for (final w in const [MetricStatus.watch, MetricStatus.danger]) {
        expect(worstStatus([MetricStatus.ungraded, w]), w);
        expect(worstStatus([w, MetricStatus.ungraded]), w);
      }
      expect(worstStatus([MetricStatus.ungraded, MetricStatus.watch,
          MetricStatus.danger]), MetricStatus.danger);
    });
  });

  group('a device reading is ungraded, never green', () {
    // docs/CLINICAL-REVIEW-WATCH.md — the freshness table for temperature, the
    // blood-sugar verdict, and refused sentence #23 for blood pressure. Green
    // survives only where the grade is real: a current reading, on a cited
    // band, from a source the product may reassure from.
    test('a wrist blood pressure in range is ungraded', () {
      expect(metricStatus('systolic', 118, source: ReadingSource.sensor),
          MetricStatus.ungraded);
      expect(metricStatus('diastolic', 76, source: ReadingSource.sensor),
          MetricStatus.ungraded);
    });

    test('a cuff blood pressure in range keeps its green', () {
      // The over-correction guard: a reading she took with an instrument and
      // typed in is a different evidential object.
      expect(metricStatus('systolic', 118, source: ReadingSource.manual),
          MetricStatus.normal);
      expect(metricStatus('diastolic', 76, source: ReadingSource.manual),
          MetricStatus.normal);
    });

    test('and a wrist blood pressure may still be red, or amber', () {
      // «Gate the positives, never the warnings.» The product escalates a
      // device BP at 140/90 — triage.dart has no source check — so the estimate
      // must still be able to pull a grade DOWN.
      expect(metricStatus('systolic', 165, source: ReadingSource.sensor),
          MetricStatus.danger);
      expect(metricStatus('diastolic', 112, source: ReadingSource.sensor),
          MetricStatus.danger);
      expect(metricStatus('systolic', 137, source: ReadingSource.sensor),
          MetricStatus.watch);
    });

    test('a device temperature and a device blood sugar are ungraded at every '
        'value', () {
      // These two differ from blood pressure on purpose: the temperature ruling
      // barred the device path from EVERY tier including emergency, and the
      // blood-sugar one found the number is not on a stated scale at all.
      for (final v in const [35.2, 36.6, 37.9, 38.6, 40.5]) {
        expect(metricStatus('temp', v, source: ReadingSource.sensor),
            MetricStatus.ungraded);
      }
      for (final v in const [2.8, 3.6, 5.4, 8.2, 12.0]) {
        expect(metricStatus('glucose', v, source: ReadingSource.sensor),
            MetricStatus.ungraded);
      }
    });
  });

  test('unknown metric is treated as normal', () => expect(metricStatus('cortisol', 999), MetricStatus.normal));
}
