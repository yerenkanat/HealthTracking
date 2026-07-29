/// Asserts the app's bundled baby-development calendar
/// (assets/data/baby_development.json) is byte-for-byte the shared contract
/// (packages/contract/baby_development.json), and that the content parses and is
/// complete (ru + kk skills for every week of the first year). If the asset and
/// the contract drift, the app, the backend and the admin panel would show a
/// parent different milestones for the same week.
/// `dart run tool/verify_baby_development_contract.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/baby_development_content.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

String _read(String rel) => File.fromUri(Platform.script.resolve(rel)).readAsStringSync();

void main() {
  final contract = _read('../../packages/contract/baby_development.json');
  final asset = _read('../assets/data/baby_development.json');

  // Normalise line endings so a CRLF checkout does not read as drift.
  _chk('the bundled asset matches the shared contract',
      contract.replaceAll('\r\n', '\n') == asset.replaceAll('\r\n', '\n'));

  final cal = parseChildDevelopment(jsonDecode(asset) as Map<String, dynamic>);
  final weeks = cal.weeks;
  _chk('the calendar covers the first year (>= 52 weeks)', weeks.length >= 52);
  _chk('weeks are sorted and unique', () {
    for (var i = 1; i < weeks.length; i++) {
      if (weeks[i].week <= weeks[i - 1].week) return false;
    }
    return true;
  }());
  _chk('the first week is 1', weeks.isNotEmpty && weeks.first.week == 1);

  var blanks = 0;
  for (final w in weeks) {
    if (w.weightKg.isEmpty || w.heightCm.isEmpty) blanks++;
    for (final s in [w.ru, w.kk]) {
      if (s.motor.isEmpty || s.speech.isEmpty || s.cognition.isEmpty) blanks++;
    }
  }
  _chk('every week has WHO ranges + ru + kk motor/speech/cognition ($blanks blank)', blanks == 0);

  _chk('the paediatrician note is present in ru + kk',
      cal.noteRu.isNotEmpty && cal.noteKk.isNotEmpty);

  // The lookup clamps out-of-range weeks to a real entry.
  _chk('week 24 resolves', cal.weekContentFor(24)?.week == 24);
  _chk('week 0 clamps to the first', cal.weekContentFor(0)?.week == weeks.first.week);
  _chk('week 999 clamps to the last', cal.weekContentFor(999)?.week == weeks.last.week);
  _chk('en falls back to ru text',
      cal.weekContentFor(24)!.skillsFor('en').motor == cal.weekContentFor(24)!.ru.motor);
  _chk('kk returns kazakh text',
      cal.weekContentFor(24)!.skillsFor('kk').motor == cal.weekContentFor(24)!.kk.motor);

  // childAgeWeeks: a birth date N weeks ago floors to N completed weeks.
  final now = DateTime(2026, 7, 23);
  _chk('childAgeWeeks floors to completed weeks',
      childAgeWeeks(now.subtract(const Duration(days: 30)), now) == 4);
  _chk('childAgeWeeks never goes negative',
      childAgeWeeks(now.add(const Duration(days: 10)), now) == 0);

  // childAgeDays: 1-based (birth day = day 1), calendar-day counted.
  _chk('childAgeDays is 1 on the day of birth',
      childAgeDays(now, now) == 1);
  _chk('childAgeDays counts calendar days + 1',
      childAgeDays(now.subtract(const Duration(days: 30)), now) == 31);
  _chk('childAgeDays never goes below 1',
      childAgeDays(now.add(const Duration(days: 5)), now) == 1);
  // Calendar-day counting, not elapsed: a birth just before midnight and a
  // "now" the next morning is one calendar day old (day 2), where
  // now.difference(birth).inDays would truncate to 0 and give day 1.
  _chk('childAgeDays counts the calendar boundary, not elapsed 24h',
      childAgeDays(DateTime(2026, 7, 22, 23, 30), DateTime(2026, 7, 23, 7, 0)) == 2);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
