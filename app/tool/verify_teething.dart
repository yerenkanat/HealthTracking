/// Pure-Dart verification of the teething guide.
/// `dart run tool/verify_teething.dart`
library;

import 'dart:io';
import '../lib/domain/teething.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  {
    _chk('there is a timeline', teethingTimeline.length >= 5);
    _chk('every group has an id', teethingTimeline.every((g) => g.id.trim().isNotEmpty));
    _chk('ids are unique', teethingTimeline.map((g) => g.id).toSet().length == teethingTimeline.length);
    _chk('no window is inside-out', teethingTimeline.every((g) => g.fromMonth <= g.toMonth));

    // Authored earliest-first by start age, so the list reads as an order.
    var ordered = true;
    for (var i = 1; i < teethingTimeline.length; i++) {
      if (teethingTimeline[i].fromMonth < teethingTimeline[i - 1].fromMonth) ordered = false;
    }
    _chk('the timeline is in eruption order', ordered);

    _chk('the first teeth are the lower central incisors around six months',
        teethingTimeline.first.id == 'lower_central' && teethingTimeline.first.fromMonth == 6);

    _chk('there are signs', teethingSigns.length >= 3);
    _chk('there are soothing measures', teethingSoothe.length >= 3);
    _chk('the not-teething caution names a high fever', teethingNot.contains('high_fever'));
  }

  // ---- Which tooth for an age ----
  {
    _chk('at 7 months, the lower central incisors', toothGroupForAge(7)?.id == 'lower_central');
    _chk('at 18 months, the first molars', toothGroupForAge(18)?.id == 'first_molars');
    _chk('before the first tooth window, none', toothGroupForAge(3) == null);
    _chk('after the last, none', toothGroupForAge(40) == null);
  }

  // ---- The window ----
  {
    _chk('the guide starts a little before the first tooth', teethingFromMonth < teethingTimeline.first.fromMonth);
    _chk('and runs to the end of the timeline', teethingToMonth == teethingTimeline.last.toMonth);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
