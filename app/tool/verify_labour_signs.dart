/// Pure-Dart verification of the signs-of-labour guide.
/// `dart run tool/verify_labour_signs.dart`
library;

import 'dart:io';
import '../lib/domain/labour_signs.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('there are labour signs', labourSigns.length >= 3);
  _chk('sign ids are unique', labourSigns.toSet().length == labourSigns.length);
  _chk('contractions are listed as a sign', labourSigns.contains('contractions'));
  _chk('waters breaking is listed as a sign', labourSigns.contains('waters'));

  _chk('there is a go-in list', labourGoIn.length >= 4);
  _chk('go-in ids are unique', labourGoIn.toSet().length == labourGoIn.length);
  _chk('the 5-1-1 pattern is a go-in reason', labourGoIn.contains('five_one_one'));
  _chk('bleeding is a go-in reason', labourGoIn.contains('bleeding'));
  _chk('reduced movements is a go-in reason', labourGoIn.contains('reduced_movements'));
  _chk('the when-in-doubt call is present', labourGoIn.contains('unsure'));

  // The two lists do not overlap — a sign is either "may be starting" or "go in".
  _chk('the lists do not overlap',
      labourSigns.toSet().intersection(labourGoIn.toSet()).isEmpty);

  _chk('preterm is before full term', pretermBeforeWeek == 37);
  _chk('the 5-1-1 numbers are five, one, one',
      fiveOneOneEveryMin == 5 && fiveOneOneLastingMin == 1 && fiveOneOneForHours == 1);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
