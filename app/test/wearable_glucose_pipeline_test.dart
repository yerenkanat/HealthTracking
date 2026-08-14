/// The watch's blood-sugar path: **carried, never graded.**
///
/// This file used to assert the opposite. It was written to guarantee the
/// band's reading travelled frame → snapshot → WearableMetrics → controller →
/// advisor, on the reasoning that a number "displayed and never judged" is a
/// defect. That reasoning was right in general and wrong here, and the clinical
/// gate reversed it on 2026-08-14.
///
/// The vendor documents the field as `当前血糖（0.1）` — a decimal place, and
/// **no unit**, anywhere in 3,248 pages. Dividing by ten and calling the result
/// mmol/L was ours, not theirs. So there is nothing to judge the number
/// against:
///
///   * «Сахар в норме» was refused sentence #5, and shipped word for word;
///   * the WARNING is refused too, and this is the part that is easy to get
///     wrong. "Gate the positives, never the warnings" presupposes a quantity
///     on a KNOWN SCALE. If that raw integer is mg/dL tenths, or an index, then
///     a true 2.8 mmol/L can sit above the low threshold and stay silent while
///     a true 5.5 fires the card. A warning with no defined relationship to the
///     thing it warns about is not conservative — it is a coin flip in both
///     directions, spending her alarm budget at random.
///
/// What survives is the raw integer, carried to the server and stored, exactly
/// as `glucoseMmol` already was: present, never triaged. That is what the last
/// test here pins, and it is the half that would be quietly lost if someone
/// "cleaned up" the unused field.
///
/// The typed-glucometer path is untouched and still grades: known instrument,
/// stated unit, deliberate act. It is not exercised here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/domain/wearable_day.dart';
import 'package:fcs_app/domain/wearable_metrics.dart';
import 'package:fcs_app/domain/health_advisor.dart';
import 'package:fcs_app/domain/health_series.dart';
import 'package:fcs_app/ble/starmax/starmax_health_bridge.dart';
import 'package:fcs_app/ble/starmax/starmax_frames.dart';

WearableMetrics _metrics(int tenths, DateTime at) =>
    WearableMetrics(at: at, steps: 1000, bloodSugarTenths: tenths);

void main() {
  test('a decoded snapshot carries the raw value, and does not scale it', () {
    const snap = StarmaxHealthSnapshot(
      totalSteps: 1000, totalKcal: 40, totalMeters: 700,
      totalSleepMin: 0, deepSleepMin: 0, lightSleepMin: 0,
      heartRate: 0, bloodOxygen: 0, bpSystolic: 0, bpDiastolic: 0,
      tempRaw: 0, bloodSugar: 82, isWorn: true, breathRate: 0, stress: 0, met: 0,
    );
    final m = wearableMetricsFromSnapshot(snap, DateTime(2026, 7, 24));
    // 82, not 8.2. The division by ten was where the unit got invented.
    expect(m.bloodSugarTenths, 82);
  });

  test('watch readings produce NO glucose advisory, high or low', () {
    final base = DateTime(2026, 7, 24, 9);
    final c = AppController(now: () => base);
    // Three readings that would once have fired ADV_GLUCOSE_HIGH.
    c.onWearableMetrics(_metrics(80, base));
    c.onWearableMetrics(_metrics(81, base.add(const Duration(minutes: 5))));
    c.onWearableMetrics(_metrics(82, base.add(const Duration(minutes: 10))));

    final codes = [for (final a in generateAdvisories(c.samples)) a.code];
    expect(codes, isNot(contains('ADV_GLUCOSE_HIGH')));
    expect(codes, isNot(contains('ADV_GLUCOSE_LOW')));
    // And the deleted one, from the other side of the same rule.
    expect(codes, isNot(contains('ADV_GLUCOSE_STEADY')));
  });

  test('a watch reading does not become a graded sample at all', () {
    // Stronger than "no advisory": the number never enters the series the
    // charts, bands and tile grades are all computed from, so there is no
    // second surface left where it could be coloured against a scale it does
    // not have.
    final base = DateTime(2026, 7, 24, 9);
    final c = AppController(now: () => base);
    c.onWearableMetrics(_metrics(80, base));
    c.onWearableMetrics(_metrics(81, base.add(const Duration(minutes: 5))));
    expect(buildSeries(c.samples, 'glucose'), isEmpty);
  });

  test('but the raw value still reaches the server, on the day path', () {
    // The half that must NOT be lost. Withdrawing a number from every screen is
    // not the same as discarding it: the reading is real data whose unit is
    // merely undocumented, and on the day the vendor states one, the history
    // should already be there. This is the `glucoseMmol` precedent — carried
    // and stored, never graded.
    final day = WearableDay(date: DateTime(2026, 7, 24), bloodSugarTenths: 82);
    final payload =
        day.toIngestPayload(deviceId: 'a-device', now: DateTime(2026, 7, 25));
    expect(payload['bloodSugarTenths'], 82);
    // As the integer it is, with no scale attached.
    expect(payload.containsKey('bloodSugarMmol'), isFalse);
    expect(payload.containsKey('glucoseMmol'), isFalse);
  });

  test('the LIVE snapshot path drops it, and that is pre-existing', () {
    // Found while writing the test above, and recorded rather than quietly
    // fixed. `WearableMetrics.toIngestPayload` has never carried
    // `bloodSugarTenths` — the field is on the model and is simply not put on
    // the wire — while the server accepts it, range-checks it with
    // `plausible(10, 300)` and has a column waiting for it.
    //
    // So the live path feeds nothing, and only the day/backfill path above
    // populates that column. This is the repository's signature defect seen
    // from the server's end, and it is NOT caused by the glucose withdrawal:
    // the withdrawal removed a getter and a grading branch, never this.
    //
    // Left as it is on purpose. Wiring it would be adding a data path under a
    // clinical withdrawal, and the ruling permits the raw value to be carried
    // without requiring it. Pinned so the gap is a decision rather than a
    // surprise, and so that closing it is a deliberate act that trips this test.
    final m = _metrics(82, DateTime(2026, 7, 24, 9));
    expect(m.bloodSugarTenths, 82, reason: 'the model still holds it');
    expect(m.toIngestPayload(deviceId: 'a-device').containsKey('bloodSugarTenths'),
        isFalse,
        reason: 'if this now passes the value, update the comment above — it is '
            'a change of behaviour, not a fix to this test');
  });
}
