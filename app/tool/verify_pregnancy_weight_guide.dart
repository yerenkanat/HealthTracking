/// Pure-Dart verification of the pregnancy weight-gain guide.
/// `dart run tool/verify_pregnancy_weight_guide.dart`
library;

import 'dart:io';
import '../lib/domain/pregnancy_weight_guide.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The ranges ----
  {
    _chk('every BMI band has a range', totalGainRanges.length == BmiBand.values.length);
    _chk('bands are unique', totalGainRanges.map((r) => r.band).toSet().length == totalGainRanges.length);
    _chk('every range is low < high', totalGainRanges.every((r) => r.lowKg < r.highKg));

    // The bands step DOWN as BMI goes up — a heavier start means less to gain.
    GainRange of(BmiBand b) => totalGainRanges.firstWhere((r) => r.band == b);
    _chk('underweight gains the most', of(BmiBand.underweight).highKg >= of(BmiBand.normal).highKg);
    _chk('normal above overweight', of(BmiBand.normal).highKg > of(BmiBand.overweight).highKg);
    _chk('overweight above obese', of(BmiBand.overweight).highKg > of(BmiBand.obese).highKg);

    _chk('first trimester is a small total', firstTrimesterLowKg < firstTrimesterHighKg && firstTrimesterHighKg <= 3);
    _chk('the typical weekly band is sane', typicalWeeklyLowKg < typicalWeeklyHighKg && typicalWeeklyHighKg < 1);
  }

  // ---- BMI banding ----
  {
    _chk('16 is underweight', bmiBandFor(16) == BmiBand.underweight);
    _chk('just under 18.5 is underweight', bmiBandFor(18.49) == BmiBand.underweight);
    _chk('22 is normal', bmiBandFor(22) == BmiBand.normal);
    _chk('the 18.5 boundary is normal', bmiBandFor(18.5) == BmiBand.normal);
    _chk('27 is overweight', bmiBandFor(27) == BmiBand.overweight);
    _chk('the 25 boundary is overweight', bmiBandFor(25) == BmiBand.overweight);
    _chk('32 is obese', bmiBandFor(32) == BmiBand.obese);
    _chk('the 30 boundary is obese', bmiBandFor(30) == BmiBand.obese);
  }

  // ---- Pace read ----
  {
    _chk('no rate → no verdict', assessWeeklyPace(null) == null);
    _chk('0.42 kg/week is on track', assessWeeklyPace(0.42) == GainPace.onTrack);
    _chk('0.1 kg/week is slow', assessWeeklyPace(0.1) == GainPace.slow);
    _chk('0.9 kg/week is fast', assessWeeklyPace(0.9) == GainPace.fast);
    // The tolerance keeps a hair over/under from flipping the verdict.
    _chk('just under the low band is still on track', assessWeeklyPace(typicalWeeklyLowKg - 0.03) == GainPace.onTrack);
    _chk('well under is slow', assessWeeklyPace(typicalWeeklyLowKg - 0.2) == GainPace.slow);
    _chk('just over the high band is still on track', assessWeeklyPace(typicalWeeklyHighKg + 0.03) == GainPace.onTrack);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
