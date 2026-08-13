/// Asserts the app's bundled emergency-help list (assets/data/emergency_help.json)
/// is byte-for-byte the shared contract (packages/contract/emergency_help.json),
/// and that the content parses and is complete (ru + kk for every scenario). If
/// the asset and the contract drift, the app, the backend and the admin panel
/// would tell a frightened person three different things about the same
/// symptom — and screen 37 is the one screen where that is not survivable.
/// `dart run tool/verify_emergency_help_contract.dart`
library;

import 'dart:convert';
import 'dart:io';
import '../lib/domain/emergency_help.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

String _read(String rel) => File.fromUri(Platform.script.resolve(rel)).readAsStringSync();

void main() {
  final contract = _read('../../packages/contract/emergency_help.json');
  final asset = _read('../assets/data/emergency_help.json');

  // Normalise line endings so a CRLF checkout does not read as drift.
  _chk('the bundled asset matches the shared contract',
      contract.replaceAll('\r\n', '\n') == asset.replaceAll('\r\n', '\n'));

  final help = parseEmergencyHelp(jsonDecode(asset) as Map<String, dynamic>);
  _chk('the list has scenarios at all', help.scenarios.isNotEmpty);
  _chk('the ambulance number is 103', help.tel == '103');
  _chk('the version is a real number', help.version >= 1);

  _chk('ids are unique', () {
    final seen = <String>{};
    for (final s in help.scenarios) {
      if (!seen.add(s.id)) return false;
    }
    return true;
  }());

  // Both severities are present. A list that is all-red tells somebody to call
  // an ambulance for a fever; a list that is all-amber tells her to wait out a
  // seizure. Either is a content mistake this catches at build time.
  final red = scenariosBySeverity(help.scenarios, EmergencySeverity.red);
  final amber = scenariosBySeverity(help.scenarios, EmergencySeverity.amber);
  _chk('there is at least one «звоните 103 сейчас» scenario', red.isNotEmpty);
  _chk('there is at least one «позвоните врачу сегодня» scenario', amber.isNotEmpty);
  _chk('every scenario is one of the two severities',
      red.length + amber.length == help.scenarios.length);

  // The severity of every entry is the file's own word, not the parser's
  // fallback. `severityFromName` answers amber for anything unknown — which is
  // the right default at runtime and would silently hide a typo here.
  final raw = (jsonDecode(asset) as Map<String, dynamic>)['scenarios'] as List;
  _chk('no scenario has a severity outside red/amber',
      raw.every((s) => s is Map && (s['severity'] == 'red' || s['severity'] == 'amber')));
  _chk('the parser sees every scenario the file lists',
      help.scenarios.length == raw.length);

  // Audience. Every scenario names one, and both audiences are populated —
  // an all-`all` file is the bug this field was added to fix (pregnancy triage
  // in front of somebody who is not pregnant), and an all-`pregnancy` one would
  // empty the screen for everybody else.
  _chk('every scenario names its audience',
      raw.every((s) => s is Map && (s['audience'] == 'all' || s['audience'] == 'pregnancy')));
  final expecting = scenariosForAudience(help.scenarios, pregnant: true);
  final notExpecting = scenariosForAudience(help.scenarios, pregnant: false);
  _chk('a pregnant reader can reach every scenario',
      expecting.length == help.scenarios.length);
  _chk('a reader who is not expecting keeps the ones that apply to her',
      notExpecting.isNotEmpty && notExpecting.length < help.scenarios.length);
  _chk('...including a red one — the list is never all-amber for her',
      scenariosBySeverity(notExpecting, EmergencySeverity.red).isNotEmpty);
  // Named, not counted: these three are the pregnancy triage the fork used to
  // hide from the only readers it is written for.
  _chk('«после 20 недель» and «после 28 недель» are pregnancy-only', () {
    final pregnancyOnly = {
      for (final s in help.scenarios)
        if (s.audience == EmergencyAudience.pregnancy) s.id
    };
    return pregnancyOnly.containsAll({'preeclampsia', 'fetal_movements'});
  }());
  // Postpartum haemorrhage happens after the due date is cleared, so this one
  // must reach a reader the app no longer considers pregnant.
  _chk('bleeding after birth is not filed as pregnancy-only',
      notExpecting.any((s) => s.id == 'bleeding'));
  _chk('an unknown audience shows the scenario rather than hiding it',
      audienceFromName('whatever-the-server-sent') == EmergencyAudience.all);

  var blanks = 0;
  for (final s in help.scenarios) {
    for (final t in [s.ru, s.kk]) {
      if (t.title.isEmpty || t.what.isEmpty || t.todo.isEmpty) blanks++;
    }
  }
  _chk('every scenario has ru + kk title/what/do ($blanks blank)', blanks == 0);

  // The Kazakh half is not a copy of the Russian one. A contract that passed
  // the blank check by duplicating the Russian text would leave a Kazakh
  // speaker reading Russian while the panel reported a complete translation.
  var copied = 0;
  for (final s in help.scenarios) {
    if (s.kk.title == s.ru.title && s.kk.what == s.ru.what) copied++;
  }
  _chk('the Kazakh text is a translation, not a copy ($copied copied)', copied == 0);

  // Reading order is total and stable: the screen and the panel both sort by
  // (sort, id), and two entries sharing a sort would reshuffle between reads.
  _chk('sort values are unique', () {
    final seen = <int>{};
    for (final s in help.scenarios) {
      if (!seen.add(s.sort)) return false;
    }
    return true;
  }());
  _chk('parsing returns them in reading order', () {
    for (var i = 1; i < help.scenarios.length; i++) {
      if (help.scenarios[i].sort <= help.scenarios[i - 1].sort) return false;
    }
    return true;
  }());

  _chk('en falls back to ru text',
      help.scenarios.first.textFor('en').title == help.scenarios.first.ru.title);
  _chk('kk returns kazakh text',
      help.scenarios.first.textFor('kk').title == help.scenarios.first.kk.title);

  // A malformed entry costs that entry, not the file. This is the property
  // that keeps screen 37 from going blank over one bad row published by the
  // back office.
  final tolerant = parseEmergencyHelp({
    'version': 2,
    'tel': '103',
    'scenarios': [
      {'id': 'ok', 'severity': 'red', 'sort': 1,
        'ru': {'title': 'a', 'what': 'b', 'do': 'c'},
        'kk': {'title': 'ä', 'what': 'b̆', 'do': 'ç'}},
      {'id': 'broken'},
      'not even a map',
      {'severity': 'red', 'sort': 2, 'ru': {'title': 'no id'}, 'kk': {'title': 'no id'}},
    ],
  });
  _chk('a malformed scenario is skipped, not fatal', tolerant.scenarios.length == 1);
  _chk('...and the good one survives intact', tolerant.scenarios.first.id == 'ok');

  // An empty file is EMPTY, not a crash: the screen still draws the 103 card.
  _chk('an empty payload parses to an empty list',
      parseEmergencyHelp({'version': 1, 'scenarios': []}).isEmpty);
  _chk('a missing tel falls back to 103',
      parseEmergencyHelp({'version': 1, 'scenarios': []}).tel == '103');

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
