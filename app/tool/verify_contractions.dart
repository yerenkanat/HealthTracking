/// Pure-Dart verification of the contraction-timing domain.
/// `dart run tool/verify_contractions.dart`
library;

import 'dart:io';
import '../lib/domain/contraction.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final t = DateTime(2026, 12, 1, 3, 0, 0);
  // Three contractions: 50s long, starts 5 min apart.
  final list = [
    Contraction(start: t, end: t.add(const Duration(seconds: 50))),
    Contraction(start: t.add(const Duration(minutes: 5)), end: t.add(const Duration(minutes: 5, seconds: 55))),
    Contraction(start: t.add(const Duration(minutes: 10)), end: t.add(const Duration(minutes: 11))),
  ];

  _chk('duration of first', list[0].duration == const Duration(seconds: 50));
  _chk('duration clamps negative to zero',
      Contraction(start: t, end: t.subtract(const Duration(seconds: 5))).duration == Duration.zero);

  _chk('no interval before first', intervalBefore(list, 0) == null);
  _chk('interval before second is 5 min', intervalBefore(list, 1) == const Duration(minutes: 5));
  _chk('interval before third is 5 min', intervalBefore(list, 2) == const Duration(minutes: 5));
  _chk('out-of-range interval null', intervalBefore(list, 9) == null);

  final s = contractionStats(list);
  _chk('count', s.count == 3);
  _chk('avg duration (50+55+60)/3 = 55s', s.avgDuration == const Duration(seconds: 55));
  _chk('avg interval 5 min', s.avgInterval == const Duration(minutes: 5));

  final one = contractionStats([list.first]);
  _chk('single → interval zero', one.avgInterval == Duration.zero && one.count == 1);

  final none = contractionStats(const []);
  _chk('empty stats zeroed', none.count == 0 && none.avgDuration == Duration.zero);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
