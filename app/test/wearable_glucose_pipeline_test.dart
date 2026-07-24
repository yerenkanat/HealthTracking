import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';
import 'package:fcs_app/domain/health_advisor.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/ble/starmax/starmax_health_bridge.dart';
import 'package:fcs_app/ble/starmax/starmax_frames.dart';

/// End-to-end guard for the smart-watch blood-sugar path. The band's reading has
/// to travel frame → snapshot → WearableMetrics → controller → advisor. If any
/// link is cut the number is "displayed and never judged" again — the exact
/// defect this pipeline was built to close.
WearableMetrics _metrics(double mmol, DateTime at) =>
    WearableMetrics(at: at, steps: 1000, bloodSugarTenths: (mmol * 10).round());

void main() {
  test('a decoded snapshot carries blood sugar into WearableMetrics', () {
    const snap = StarmaxHealthSnapshot(
      totalSteps: 1000, totalKcal: 40, totalMeters: 700,
      totalSleepMin: 0, deepSleepMin: 0, lightSleepMin: 0,
      heartRate: 0, bloodOxygen: 0, bpSystolic: 0, bpDiastolic: 0,
      tempRaw: 0, bloodSugar: 82, isWorn: true, breathRate: 0, stress: 0, met: 0,
    );
    final m = wearableMetricsFromSnapshot(snap, DateTime(2026, 7, 24));
    expect(m.bloodSugar, closeTo(8.2, 1e-9));
  });

  test('watch metrics reach the advisor and an elevated reading is flagged', () {
    final base = DateTime(2026, 7, 24, 9);
    final c = AppController(now: () => base);
    // Three distinct elevated readings — enough for the advisor's minimum window.
    c.onWearableMetrics(_metrics(8.0, base));
    c.onWearableMetrics(_metrics(8.1, base.add(const Duration(minutes: 5))));
    c.onWearableMetrics(_metrics(8.2, base.add(const Duration(minutes: 10))));

    final glucosePoints = buildSeries(c.samples, 'glucose');
    expect(glucosePoints.length, 3, reason: 'each distinct reading is a sample');

    final advisories = generateAdvisories(c.samples);
    expect(advisories.any((a) => a.code == 'ADV_GLUCOSE_HIGH'), isTrue);
  });

  test('an unchanged reading is not re-recorded on every sync', () {
    final base = DateTime(2026, 7, 24, 9);
    final c = AppController(now: () => base);
    c.onWearableMetrics(_metrics(5.4, base));
    c.onWearableMetrics(_metrics(5.4, base.add(const Duration(minutes: 5))));
    c.onWearableMetrics(_metrics(5.4, base.add(const Duration(minutes: 10))));
    expect(buildSeries(c.samples, 'glucose').length, 1);
  });
}
