import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';

/// The grade behind the vital-signs colour code (green/amber/red — and ink,
/// where the product is not judging). Thresholds must stay aligned with the
/// advisor + triage layers.
void main() {
  // BLOOD PRESSURE GRADES AGAINST 140/90 AND NOTHING ELSE — clinical gate,
  // 2026-08-19. The 135/85 watch tier was removed because neither number is in
  // any source this product cites (docs/CLINICAL-REVIEW-WATCH.md, «135/85
  // stopped grading»; docs/TODO.md §1.1, §2.1), and an amber tile announced as
  // «вне безопасного диапазона» publishes a band to the reader exactly as a
  // printed «135» would. These tests are written so that putting either number
  // back fails here, whichever tier it is put back as.
  group('metricStatus — systolic', () {
    test('normal below the cited cutoff', () => expect(metricStatus('systolic', 118), MetricStatus.normal));
    test('no watch tier where 135 used to be', () => expect(metricStatus('systolic', 136), MetricStatus.normal));
    test('no watch tier at the old 135 boundary', () => expect(metricStatus('systolic', 135), MetricStatus.normal));
    test('danger at the emergency cutoff', () => expect(metricStatus('systolic', 140), MetricStatus.danger));
  });

  group('metricStatus — diastolic', () {
    test('normal', () => expect(metricStatus('diastolic', 76), MetricStatus.normal));
    test('no watch tier at the old 85 boundary', () => expect(metricStatus('diastolic', 85), MetricStatus.normal));
    test('no watch tier where 88 used to be amber', () => expect(metricStatus('diastolic', 88), MetricStatus.normal));
    test('danger at 90', () => expect(metricStatus('diastolic', 92), MetricStatus.danger));
  });

  group('no uncited band grades a blood pressure, from any source', () {
    // Swept rather than probed at three points: a band re-added anywhere below
    // the cited cutoff is caught wherever someone puts its edge.
    test('nothing below 140 systolic is a warning', () {
      for (var v = 80; v < 140; v++) {
        for (final src in ReadingSource.values) {
          expect(metricStatus('systolic', v.toDouble(), source: src).isWarning, isFalse,
              reason: 'systolic $v (${src.name}) graded as a warning — on what cited band?');
        }
      }
    });
    test('nothing below 90 diastolic is a warning', () {
      for (var v = 50; v < 90; v++) {
        for (final src in ReadingSource.values) {
          expect(metricStatus('diastolic', v.toDouble(), source: src).isWarning, isFalse,
              reason: 'diastolic $v (${src.name}) graded as a warning — on what cited band?');
        }
      }
    });

    // The other half, and it is the one that keeps this from being a loosening:
    // the CITED cutoff still fires, from a wrist estimate as well as a cuff.
    // «Gate the positives, never the warnings» is unchanged.
    test('140/90 is still danger from a device reading', () {
      expect(metricStatus('systolic', 140, source: ReadingSource.sensor), MetricStatus.danger);
      expect(metricStatus('diastolic', 90, source: ReadingSource.sensor), MetricStatus.danger);
      expect(metricStatus('systolic', 165, source: ReadingSource.sensor), MetricStatus.danger);
    });

    // And a device reading below it is still not painted teal (refused #23).
    test('a device reading below the cutoff is ungraded, not normal', () {
      expect(metricStatus('systolic', 137, source: ReadingSource.sensor), MetricStatus.ungraded);
      expect(metricStatus('diastolic', 88, source: ReadingSource.sensor), MetricStatus.ungraded);
      expect(metricStatus('systolic', 118, source: ReadingSource.sensor), MetricStatus.ungraded);
    });
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

    test('and a wrist blood pressure may still be red', () {
      // «Gate the positives, never the warnings.» The product escalates a
      // device BP at 140/90 — triage.dart has no source check — so the estimate
      // must still be able to pull a grade DOWN.
      expect(metricStatus('systolic', 165, source: ReadingSource.sensor),
          MetricStatus.danger);
      expect(metricStatus('diastolic', 112, source: ReadingSource.sensor),
          MetricStatus.danger);
      // «…or amber» USED TO BE THE THIRD LINE HERE: a wrist 137 graded
      // `watch`. It came out on 2026-08-19 with the 135/85 band itself, which
      // no cited source contains (docs/CLINICAL-REVIEW-WATCH.md, «135/85
      // stopped grading»). The estimate can still pull the grade down — that is
      // the two lines above, and they are the part of this test that carried
      // the rule. What it can no longer do is pull it down to an uncited tier.
      expect(metricStatus('systolic', 137, source: ReadingSource.sensor),
          MetricStatus.ungraded);
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
