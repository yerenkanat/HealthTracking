/// Pure-Dart verification of the child safety advisor.
/// `dart run tool/verify_safety.dart`
library;

import 'dart:io';
import '../lib/domain/child_safety_advisor.dart';
import '../lib/domain/child_tracker_state.dart' show Freshness;

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

bool _has(List<SafetyTip> tips, String code) => tips.any((t) => t.code == code);

void main() {
  // ---- Age bands ----
  _chk('infant band', ageBandFor(6) == AgeBand.infant);
  _chk('toddler band', ageBandFor(24) == AgeBand.toddler);
  _chk('preschool band', ageBandFor(48) == AgeBand.preschool);
  _chk('school-age band', ageBandFor(96) == AgeBand.schoolAge);
  _chk('preteen band', ageBandFor(150) == AgeBand.preteen);
  _chk('band boundaries', ageBandFor(11) == AgeBand.infant && ageBandFor(12) == AgeBand.toddler &&
      ageBandFor(35) == AgeBand.toddler && ageBandFor(36) == AgeBand.preschool &&
      ageBandFor(143) == AgeBand.schoolAge && ageBandFor(144) == AgeBand.preteen);

  // ---- Age-specific tips ----
  final toddler = generateChildTips(ageMonths: 24);
  _chk('toddler tips present', _has(toddler, 'CS_TODDLER_WATER') && _has(toddler, 'CS_TODDLER_CHOKING'));
  final school = generateChildTips(ageMonths: 96);
  _chk('school tips present', _has(school, 'CS_SCHOOL_ROUTE') && _has(school, 'CS_SCHOOL_CHECKIN'));
  _chk('preteen tips present', _has(generateChildTips(ageMonths: 150), 'CS_PRETEEN_ONLINE'));

  // ---- No DOB → invite ----
  final noDob = generateChildTips(ageMonths: null);
  _chk('no DOB → CS_NO_DOB', _has(noDob, 'CS_NO_DOB'));
  _chk('no DOB → no age tips', !_has(noDob, 'CS_TODDLER_WATER'));

  // ---- Status-driven ----
  final atSchool = generateChildTips(ageMonths: 96, currentZone: 'School', freshness: Freshness.live, hasLocation: true);
  _chk('at zone (fresh) → positive CS_AT_ZONE', _has(atSchool, 'CS_AT_ZONE'));
  _chk('CS_AT_ZONE is first (positive before age tips)', atSchool.first.code == 'CS_AT_ZONE');

  final stale = generateChildTips(ageMonths: 96, currentZone: 'School', freshness: Freshness.stale, hasLocation: true);
  _chk('stale → watch CS_DELAYED', _has(stale, 'CS_DELAYED'));
  _chk('CS_DELAYED is first (watch wins)', stale.first.code == 'CS_DELAYED' && stale.first.tone == TipTone.watch);
  _chk('stale suppresses CS_AT_ZONE', !_has(stale, 'CS_AT_ZONE'));

  final moving = generateChildTips(ageMonths: 96, currentZone: null, freshness: Freshness.recent, hasLocation: true);
  _chk('between zones → CS_ON_MOVE', _has(moving, 'CS_ON_MOVE'));

  final noFix = generateChildTips(ageMonths: 96, hasLocation: false);
  _chk('no location → no status tips', !_has(noFix, 'CS_AT_ZONE') && !_has(noFix, 'CS_DELAYED') && !_has(noFix, 'CS_ON_MOVE'));
  _chk('no location still has age tips', _has(noFix, 'CS_SCHOOL_ROUTE'));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
