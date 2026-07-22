/// Pure-Dart verification of the hospital-bag checklist.
/// `dart run tool/verify_hospital_bag.dart`
library;

import 'dart:io';
import '../lib/domain/hospital_bag.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  {
    _chk('there is a checklist', hospitalBagItems.length >= 12);
    _chk('every item has a non-empty id', hospitalBagItems.every((i) => i.id.trim().isNotEmpty));
    final ids = hospitalBagItems.map((i) => i.id).toList();
    _chk('ids are unique', ids.toSet().length == ids.length);

    // All three bags are represented.
    for (final c in BagCategory.values) {
      _chk('the ${c.name} bag has items', itemsInCategory(c).isNotEmpty);
    }
    _chk('grouping loses nothing',
        BagCategory.values.fold<int>(0, (n, c) => n + itemsInCategory(c).length) == hospitalBagItems.length);

    _chk('total matches the list', hospitalBagTotal == hospitalBagItems.length);
    _chk('the car seat is on the list', ids.contains('car_seat'));
    _chk('the exchange card is on the list', ids.contains('exchange_card'));
  }

  // ---- Packing maths ----
  {
    _chk('nothing packed is zero', packedCount(const {}) == 0);
    _chk('and the fraction is zero', packedFraction(const {}) == 0);
    _chk('not fully packed when empty', !isFullyPacked(const {}));

    final two = {hospitalBagItems[0].id, hospitalBagItems[1].id};
    _chk('counts the ticked items', packedCount(two) == 2);
    _chk('fraction is count over total', (packedFraction(two) - 2 / hospitalBagTotal).abs() < 1e-9);

    final all = {for (final i in hospitalBagItems) i.id};
    _chk('everything ticked is fully packed', isFullyPacked(all));
    _chk('and the fraction is one', packedFraction(all) == 1.0);

    // A stale id (no longer in the list) must not inflate the count.
    final withStale = {hospitalBagItems[0].id, 'an_item_removed_in_a_later_build'};
    _chk('a stale tick is ignored, not counted', packedCount(withStale) == 1);
  }

  {
    _chk('the surfacing week is in the third trimester', hospitalBagFromWeek >= 28 && hospitalBagFromWeek <= 36);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
