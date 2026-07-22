/// Asserts the Dart vaccination domain matches the shared contract
/// packages/contract/vaccination_schedule.json — the same file the backend serves
/// and the admin panel renders. A drift here would tell a parent a different
/// immunisation schedule in the app than staff see in the back-office.
/// `dart run tool/verify_vaccination_contract.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/vaccination.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

Map<String, dynamic> _readJson(String rel) =>
    jsonDecode(File.fromUri(Platform.script.resolve(rel)).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final c = _readJson('../../packages/contract/vaccination_schedule.json');
  final vaccines = (c['vaccines'] as List).cast<Map<String, dynamic>>();

  _chk('contract has the same number of vaccines as the domain',
      vaccines.length == kzSchedule.length);
  _chk('contract due-window matches the domain', c['dueWindowMonths'] == dueWindowMonths);

  for (var i = 0; i < kzSchedule.length; i++) {
    final v = kzSchedule[i];
    final j = vaccines[i];
    _chk('vaccine $i (${v.id}): id matches', j['id'] == v.id);
    _chk('vaccine $i (${v.id}): atMonth matches', j['atMonth'] == v.atMonth);
    _chk('vaccine $i (${v.id}): dose matches', (j['dose'] as int?) == v.dose);
    _chk('vaccine $i (${v.id}): has a non-empty ru label',
        (j['ru'] as String?)?.trim().isNotEmpty ?? false);
  }

  // A couple of anchors, so a reordering that still has the same count is caught.
  _chk('the first entries are the birth doses (hepb + bcg at month 0)',
      vaccines[0]['id'] == 'hepb' && vaccines[0]['atMonth'] == 0 && vaccines[1]['id'] == 'bcg');
  _chk('MMR dose 1 is at 12 months',
      vaccines.any((v) => v['id'] == 'mmr' && v['dose'] == 1 && v['atMonth'] == 12));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
