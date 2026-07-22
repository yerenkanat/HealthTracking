/// Pure-Dart verification of the baby size-comparison domain.
/// `dart run tool/verify_baby_size.dart`
library;

import 'dart:io';
import '../lib/domain/baby_size.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('before week 4 → null', babySizeFor(3) == null);
  _chk('week 4 → poppy seed', babySizeFor(4)?.code == 'bsize_poppyseed');
  _chk('exact week 20 → banana', babySizeFor(20)?.code == 'bsize_banana');
  _chk('gap week snaps back (15 → peach@14)', babySizeFor(15)?.code == 'bsize_peach');
  _chk('gap week snaps back (21 → banana@20)', babySizeFor(21)?.code == 'bsize_banana');
  _chk('term week 40 → watermelon', babySizeFor(40)?.code == 'bsize_watermelon');
  _chk('past term clamps to last', babySizeFor(42)?.code == 'bsize_watermelon');
  _chk('length grows with week', babySizeFor(40)!.lengthCm > babySizeFor(4)!.lengthCm);

  // Table integrity: strictly increasing weeks and lengths, unique codes.
  var okOrder = true;
  final codes = <String>{};
  for (var i = 0; i < babySizeTable.length; i++) {
    codes.add(babySizeTable[i].code);
    if (i > 0 && babySizeTable[i].week <= babySizeTable[i - 1].week) okOrder = false;
    if (i > 0 && babySizeTable[i].lengthCm <= babySizeTable[i - 1].lengthCm) okOrder = false;
  }
  _chk('weeks & lengths strictly increasing', okOrder);
  _chk('all codes unique', codes.length == babySizeTable.length);

  // ---- The proportional size visual ----
  _chk('term length is the week-40 entry', termLengthCm == babySizeTable.last.lengthCm);
  _chk('term maps to a full disc', sizeVisualFraction(termLengthCm) == 1.0);
  _chk('the tiniest week is not sub-pixel (floored)',
      sizeVisualFraction(babySizeTable.first.lengthCm) >= 0.14);
  _chk('a mid week sits between floor and full',
      () {
        final f = sizeVisualFraction(babySizeFor(20)!.lengthCm);
        return f > 0.14 && f < 1.0;
      }());
  // Monotonic: a later, longer week never draws a smaller disc.
  var monotonic = true;
  for (var i = 1; i < babySizeTable.length; i++) {
    if (sizeVisualFraction(babySizeTable[i].lengthCm) <
        sizeVisualFraction(babySizeTable[i - 1].lengthCm)) {
      monotonic = false;
    }
  }
  _chk('the disc never shrinks as the weeks pass', monotonic);
  _chk('area tracks length (radius is its root)',
      // half the length → radius fraction of 1/sqrt(2), not 1/2.
      (sizeVisualFraction(termLengthCm / 2) - (1 / 1.4142135623730951)).abs() < 1e-9);
  _chk('over-term clamps, never exceeds a full disc',
      sizeVisualFraction(termLengthCm * 2) == 1.0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
