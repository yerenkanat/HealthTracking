/// Asserts the app's bundled pregnancy calendar (assets/data/pregnancy_weeks.json)
/// is byte-for-byte the shared contract (packages/contract/pregnancy_weeks.json),
/// and that the content parses and is complete (ru + kk for every week). If the
/// asset and the contract drift, the app, the backend and the admin panel would
/// show a mother different things on the same week.
/// `dart run tool/verify_pregnancy_weeks_contract.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/pregnancy_week_content.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

String _read(String rel) => File.fromUri(Platform.script.resolve(rel)).readAsStringSync();

void main() {
  final contract = _read('../../packages/contract/pregnancy_weeks.json');
  final asset = _read('../assets/data/pregnancy_weeks.json');

  // Normalise line endings so a CRLF checkout does not read as drift.
  _chk('the bundled asset matches the shared contract',
      contract.replaceAll('\r\n', '\n') == asset.replaceAll('\r\n', '\n'));

  final weeks = parsePregnancyWeeks(jsonDecode(asset) as Map<String, dynamic>);
  _chk('the calendar has at least 40 weeks', weeks.length >= 40);
  _chk('weeks are sorted and unique', () {
    for (var i = 1; i < weeks.length; i++) {
      if (weeks[i].week <= weeks[i - 1].week) return false;
    }
    return true;
  }());
  _chk('the first week is 1', weeks.isNotEmpty && weeks.first.week == 1);

  var blanks = 0;
  for (final w in weeks) {
    for (final t in [w.ru, w.kk]) {
      if (t.baby.isEmpty || t.you.isEmpty || t.recommend.isEmpty) blanks++;
    }
  }
  _chk('every week has ru + kk baby/you/recommend ($blanks blank)', blanks == 0);

  // The lookup clamps out-of-range weeks to a real entry.
  _chk('week 6 resolves', weekContentFor(weeks, 6)?.week == 6);
  _chk('week 0 clamps to the first', weekContentFor(weeks, 0)?.week == weeks.first.week);
  _chk('week 99 clamps to the last', weekContentFor(weeks, 99)?.week == weeks.last.week);
  _chk('en falls back to ru text', weekContentFor(weeks, 6)!.textFor('en').baby ==
      weekContentFor(weeks, 6)!.ru.baby);
  _chk('kk returns kazakh text', weekContentFor(weeks, 6)!.textFor('kk').baby ==
      weekContentFor(weeks, 6)!.kk.baby);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
