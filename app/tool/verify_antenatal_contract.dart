/// Asserts the Dart antenatal domain matches the shared contract
/// packages/contract/antenatal_protocol.json — the same file the backend serves
/// and the admin panel renders. If the domain and the contract disagree, the app,
/// the API and the admin would each tell a mother a different schedule.
/// `dart run tool/verify_antenatal_contract.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/antenatal_protocol.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

Map<String, dynamic> _readJson(String rel) {
  final f = File.fromUri(Platform.script.resolve(rel));
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final c = _readJson('../../packages/contract/antenatal_protocol.json');
  final visits = (c['visits'] as List).cast<Map<String, dynamic>>();
  final windows = (c['windows'] as List).cast<Map<String, dynamic>>();

  _chk('contract has the same number of visits as the domain',
      visits.length == antenatalVisits.length);
  _chk('contract has the same number of windows as the domain',
      windows.length == antenatalWindows.length);

  for (var i = 0; i < antenatalVisits.length; i++) {
    final v = antenatalVisits[i];
    final j = visits[i];
    _chk('visit ${v.number}: number matches', j['number'] == v.number);
    _chk('visit ${v.number}: fromWeek matches', j['fromWeek'] == v.fromWeek);
    _chk('visit ${v.number}: toWeek matches', j['toWeek'] == v.toWeek);
    final jItems = (j['items'] as List).cast<Map<String, dynamic>>();
    _chk('visit ${v.number}: item count matches', jItems.length == v.items.length);
    for (var k = 0; k < v.items.length; k++) {
      final it = v.items[k];
      final ji = jItems[k];
      _chk('visit ${v.number} item ${it.id}: id matches', ji['id'] == it.id);
      _chk('visit ${v.number} item ${it.id}: category matches', ji['category'] == it.category.name);
      _chk('visit ${v.number} item ${it.id}: risk matches', ji['risk'] == it.risk);
      _chk('visit ${v.number} item ${it.id}: has a non-empty ru label',
          (ji['ru'] as String?)?.trim().isNotEmpty ?? false);
    }
  }

  for (var i = 0; i < antenatalWindows.length; i++) {
    final w = antenatalWindows[i];
    final j = windows[i];
    _chk('window ${w.id}: id matches', j['id'] == w.id);
    _chk('window ${w.id}: fromWeek matches', j['fromWeek'] == w.fromWeek);
    _chk('window ${w.id}: toWeek matches', j['toWeek'] == w.toWeek);
    _chk('window ${w.id}: risk matches', j['risk'] == w.risk);
  }

  // Every category the domain uses is labelled in the contract.
  final cats = (c['categories'] as Map).keys.toSet();
  for (final cat in AntenatalCategory.values) {
    _chk('contract labels the ${cat.name} category', cats.contains(cat.name));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
