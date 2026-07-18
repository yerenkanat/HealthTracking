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

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
