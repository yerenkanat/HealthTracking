/// Pure-Dart verification of the wearable-metrics model and its bridge from a
/// Starmax snapshot. `dart run tool/verify_wearable_metrics.dart`
library;

import 'dart:io';
import '../lib/domain/wearable_metrics.dart';
import '../lib/ble/starmax/starmax_frames.dart';
import '../lib/ble/starmax/starmax_health_bridge.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

StarmaxHealthSnapshot snap({
  int steps = 0,
  int kcal = 0,
  int meters = 0,
  int sleep = 0,
  int deep = 0,
  int light = 0,
  int stress = 0,
  int breath = 0,
  int sugar = 0,
  bool worn = true,
}) =>
    StarmaxHealthSnapshot(
      totalSteps: steps,
      totalKcal: kcal,
      totalMeters: meters,
      totalSleepMin: sleep,
      deepSleepMin: deep,
      lightSleepMin: light,
      heartRate: 0,
      bloodOxygen: 0,
      stress: stress,
      met: 0,
      bpDiastolic: 0,
      bpSystolic: 0,
      tempRaw: 0,
      bloodSugar: sugar,
      isWorn: worn,
      breathRate: breath,
    );

void main() {
  final at = DateTime(2026, 7, 22, 10);

  // ---- The bridge maps the fields the triage path drops ----
  {
    final m = wearableMetricsFromSnapshot(
      snap(steps: 8200, kcal: 420, meters: 6100, sleep: 465, deep: 120, light: 300, stress: 34, breath: 15, sugar: 55),
      at,
    );
    _chk('steps map', m.steps == 8200);
    _chk('calories map', m.kcal == 420);
    _chk('distance maps and converts to km', m.meters == 6100 && m.km == 6.1);
    _chk('sleep totals map', m.sleepMinutes == 465 && m.deepSleepMinutes == 120 && m.lightSleepMinutes == 300);
    _chk('stress maps', m.stress == 34);
    _chk('breathing rate maps', m.breathRate == 15);
    _chk('blood sugar maps to mmol/L', m.bloodSugar == 5.5);
    _chk('the timestamp is stamped', m.at == at);
    _chk('there is something to show', m.hasAnything);
  }

  // ---- The zero rule ----
  {
    // Current wellness fields of 0 mean "not measured" → null.
    final m = wearableMetricsFromSnapshot(snap(stress: 0, breath: 0, sugar: 0), at);
    _chk('an unmeasured stress is null, not calm', m.stress == null);
    _chk('an unmeasured breathing rate is null', m.breathRate == null);
    _chk('an unmeasured blood sugar is null', m.bloodSugar == null);

    // Daily totals of 0 are REAL — 0 steps at dawn is true, not unknown.
    final dawn = wearableMetricsFromSnapshot(snap(steps: 0, kcal: 0), at);
    _chk('zero steps is a real total, kept as 0', dawn.steps == 0);
  }

  // ---- hasAnything gates an empty panel ----
  {
    _chk('an all-zero snapshot has nothing to show',
        !wearableMetricsFromSnapshot(snap(), at).hasAnything);
    _chk('a few steps is enough to show',
        wearableMetricsFromSnapshot(snap(steps: 500), at).hasAnything);
    _chk('a stress reading alone is enough to show',
        wearableMetricsFromSnapshot(snap(stress: 40), at).hasAnything);
  }

  // ---- The model's own maths ----
  {
    final m = WearableMetrics(at: at);
    _chk('a bare model has nothing to show', !m.hasAnything);
    _chk('distance of a bare model is zero km', m.km == 0);
    _chk('blood sugar unknown is null', m.bloodSugar == null);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
