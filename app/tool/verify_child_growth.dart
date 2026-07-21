/// Pure-Dart verification of child growth tracking.
/// `dart run tool/verify_child_growth.dart`
library;

import 'dart:io';
import '../lib/domain/child_growth.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final jan = DateTime(2026, 1, 10);
  final feb = DateTime(2026, 2, 10);
  final mar = DateTime(2026, 3, 10);

  // ---- Recording ----
  {
    var pts = <GrowthPoint>[];
    pts = upsertGrowth(pts, GrowthPoint(at: feb, weightKg: 5.2));
    pts = upsertGrowth(pts, GrowthPoint(at: jan, weightKg: 4.4));
    _chk('points are kept oldest first', pts.first.at == jan && pts.last.at == feb);

    // One per day: a parent correcting a typo must end with a corrected
    // figure, not two conflicting ones an hour apart.
    pts = upsertGrowth(pts, GrowthPoint(at: DateTime(2026, 2, 10, 18), weightKg: 5.4));
    _chk('a second entry on the same day replaces it', pts.length == 2);
    _chk('and the newer value wins', pts.last.weightKg == 5.4);

    pts = removeGrowthOn(pts, feb);
    _chk('a day can be removed', pts.length == 1 && pts.single.at == jan);
  }
  {
    // An empty measurement is not a visit.
    final pts = upsertGrowth(const [], GrowthPoint(at: jan));
    _chk('a point with neither value is not stored', pts.isEmpty);
  }
  {
    // Height-only visits happen; they must be representable.
    final pts = upsertGrowth(const [], GrowthPoint(at: jan, heightCm: 54));
    _chk('a height-only visit is stored', pts.length == 1);
    _chk('and appears in the height series only',
        heightSeries(pts).length == 1 && weightSeries(pts).isEmpty);
  }

  // ---- Plausibility ----
  {
    // A typo filter, not a medical judgement: 100 kg in a baby's weight field
    // is a slipped decimal, and it would wreck the chart scale and every
    // "gained since last time" under it.
    _chk('a newborn weight is plausible', isPlausibleWeight(3.2));
    _chk('a toddler weight is plausible', isPlausibleWeight(12.0));
    _chk('a slipped decimal is not', !isPlausibleWeight(320));
    _chk('nor is zero', !isPlausibleWeight(0));
    _chk('nor infinity', !isPlausibleWeight(double.infinity));
    _chk('a newborn length is plausible', isPlausibleHeight(50));
    _chk('a metre-and-a-half is not a toddler', !isPlausibleHeight(180));
  }

  // ---- Change since last time ----
  {
    final pts = [
      GrowthPoint(at: jan, weightKg: 4.4),
      GrowthPoint(at: feb, weightKg: 5.2),
    ];
    final w = weightChange(pts)!;
    _chk('the gain is the difference', (w.delta - 0.8).abs() < 1e-9);
    _chk('and carries the interval', w.days == 31);
  }
  {
    // The first visit has nothing to compare against. "+0" there would read as
    // no growth rather than no data.
    _chk('one point yields no change', weightChange([GrowthPoint(at: jan, weightKg: 4.4)]) == null);
    _chk('no points yield no change', weightChange(const []) == null);
  }
  {
    // Weight and height are compared against their OWN previous value, not
    // against whatever visit happened to be last.
    final pts = [
      GrowthPoint(at: jan, weightKg: 4.4, heightCm: 54),
      GrowthPoint(at: feb, heightCm: 57), // height only
      GrowthPoint(at: mar, weightKg: 6.0),
    ];
    final w = weightChange(pts)!;
    _chk('weight skips the height-only visit', (w.delta - 1.6).abs() < 1e-9);
    _chk('and measures across the whole gap', w.days == 59);
    final h = heightChange(pts)!;
    _chk('height compares to the previous height', (h.delta - 3).abs() < 1e-9);
  }
  {
    // Babies do lose weight in the first days, and after illness. The app must
    // report that plainly rather than clamping it to zero.
    final pts = [
      GrowthPoint(at: jan, weightKg: 3.5),
      GrowthPoint(at: feb, weightKg: 3.3),
    ];
    _chk('a loss is reported as a loss', weightChange(pts)!.delta < 0);
  }

  // ---- Chart axis ----
  {
    final a = axisFor([4.0, 5.0, 6.0]);
    _chk('the axis contains the data', a.min < 4.0 && a.max > 6.0);
    _chk('with padding, so the line is not drawn against the edge',
        a.min > 2.0 && a.max < 8.0);

    // A flat series would otherwise collapse to a zero-height axis and divide
    // by zero when scaling.
    final flat = axisFor([5.0, 5.0, 5.0]);
    _chk('a flat series still has height', flat.max > flat.min);
    final one = axisFor([5.0]);
    _chk('a single point still has height', one.max > one.min);
    final none = axisFor(const []);
    _chk('an empty series does not divide by zero', none.max > none.min);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
