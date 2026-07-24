import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/domain/health_series.dart';

/// The three-tier grade behind the vital-signs colour code (green/amber/red).
/// Thresholds must stay aligned with the advisor + triage layers.
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
  });

  test('unknown metric is treated as normal', () => expect(metricStatus('cortisol', 999), MetricStatus.normal));
}
