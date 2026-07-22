/// Pure-Dart verification of the week-by-week fetal development highlights.
/// `dart run tool/verify_fetal_development.dart`
library;

import 'dart:io';
import '../lib/domain/fetal_development.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- The table is coherent ----
  {
    _chk('there are highlights', fetalHighlights.length >= 15);
    _chk('every highlight has a non-empty id', fetalHighlights.every((h) => h.id.trim().isNotEmpty));
    _chk('no week is before five or past term',
        fetalHighlights.every((h) => h.week >= 5 && h.week <= 40));

    final ids = fetalHighlights.map((h) => h.id).toList();
    _chk('ids are unique', ids.toSet().length == ids.length);

    // Strictly increasing weeks — fetalHighlightFor relies on the order, and a
    // week out of place would snap to the wrong highlight.
    var ordered = true;
    for (var i = 1; i < fetalHighlights.length; i++) {
      if (fetalHighlights[i].week <= fetalHighlights[i - 1].week) ordered = false;
    }
    _chk('weeks are strictly increasing', ordered);
  }

  // ---- Snapping ----
  {
    _chk('before the first entry → null', fetalHighlightFor(4) == null);
    _chk('exact week five → heartbeat', fetalHighlightFor(5)?.id == 'heartbeat');
    _chk('exact week twenty → hearing your voice', fetalHighlightFor(20)?.id == 'voice');
    _chk('term → ready', fetalHighlightFor(40)?.id == 'ready');
    _chk('past term clamps to the last', fetalHighlightFor(42)?.id == 'ready');

    // A gap week snaps back to the most recent highlight.
    final at13 = fetalHighlightFor(13);
    _chk('a gap week snaps back (13 → the week-12 highlight)', at13?.week == 12);
    _chk('and it is a real, earlier-or-equal week', at13 != null && at13.week <= 13);
  }

  // ---- Coverage across the pregnancy ----
  {
    // From week 5 onward every week resolves to a highlight, so the card is
    // never empty once there is anything to show.
    var everyWeekCovered = true;
    for (var w = 5; w <= 40; w++) {
      if (fetalHighlightFor(w) == null) everyWeekCovered = false;
    }
    _chk('every week 5..40 resolves to a highlight', everyWeekCovered);

    final weeks = fetalHighlights.map((h) => h.week).toSet();
    _chk('the first trimester is covered', weeks.any((w) => w <= 13));
    _chk('the second trimester is covered', weeks.any((w) => w > 13 && w <= 27));
    _chk('the third trimester is covered', weeks.any((w) => w > 27));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
