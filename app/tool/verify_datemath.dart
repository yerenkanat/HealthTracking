/// Date arithmetic must count CALENDAR DAYS, not elapsed time.
/// `dart run tool/verify_datemath.dart`
///
/// `b.difference(a).inDays` measures a duration and truncates it. A calendar
/// day is 23 or 25 hours across a daylight-saving change, so any date maths
/// written that way is off by one for users whose clocks change — shifting a
/// gestational age, a cycle day, a countdown to a period or an appointment.
///
/// The app is aimed at Kazakhstan, which abolished daylight saving in 2005, so
/// this is not reproducible here and was never going to be caught by running
/// the app. It is a correctness property enforced by reading the source.
library;

import 'dart:io';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Files allowed to use the elapsed-time form, with the reason.
const _allowed = <String, String>{
  'cycle_log.dart': 'defines daysBetween itself, and names the old form in its doc comment',
};

void main() {
  final libDir = Directory.fromUri(Platform.script.resolve('../lib'));
  final offenders = <String>[];
  var scanned = 0;

  // Duration-based day counting: `.difference(x).inDays` and `.inDays` reached
  // straight off a Duration variable holding a date gap.
  final pattern = RegExp(r'\.difference\([^)]*\)\s*\.inDays');

  for (final f in libDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final name = f.path.replaceAll(r'\', '/').split('/').last;
    scanned++;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///')) continue;
      if (!pattern.hasMatch(line)) continue;
      if (_allowed.containsKey(name)) continue;
      offenders.add('lib/.../$name:${i + 1}  ${line.trim()}');
    }
  }

  _chk('the scan actually read the source ($scanned files)', scanned > 20);
  if (offenders.isNotEmpty) {
    print('\n  Counting days by elapsed time — use daysBetween() instead:');
    for (final o in offenders) {
      print('    $o');
    }
    print('');
  }
  _chk('no date maths counts days by elapsed time (${offenders.length} found)',
      offenders.isEmpty);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
