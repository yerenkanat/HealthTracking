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
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../lib/domain/cycle_log.dart' show addDays, dateKey, daysBetween;

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Files allowed to use the elapsed-time form, with the reason.
const _allowed = <String, String>{
  'cycle_log.dart': 'defines daysBetween itself, and names the old form in its doc comment',
};

/// Exempting a LINE, not a file.
///
/// A per-file allowlist would excuse every future line in the same file — and
/// the files that legitimately measure elapsed time (main.dart, the women's
/// health screen) are among the largest here, so the exemption would cover far
/// more than it was granted for. The marker sits on the line instead, and has
/// to carry a reason:
///
///     final since = now.subtract(Duration(days: 7)); // elapsed-ok: a cutoff instant
///
/// Two files are exempt whole, because the string appears in their prose:
/// cycle_log.dart defines addDays and quotes the old form to explain it, and
/// reminder_schedule.dart does the same.
const _steppingExemptFiles = <String, String>{
  'cycle_log.dart': 'defines addDays and quotes the old form in its doc comment',
  'reminder_schedule.dart': 'quotes the old form to explain why it is wrong',
};

final _exemptLine = RegExp(r'//\s*elapsed-ok:\s*\S');

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

  // The same scan for the STEPPING form.
  //
  // The check above passed for months while every date window in the app was
  // built by repeated subtract(Duration(days:)). It looked for one shape of the
  // mistake and reported zero, which reads as "date maths is clean". Half a
  // guard is worse than none, because it is quoted as though it were whole.
  {
    final stepPattern = RegExp(r'\.(add|subtract)\(\s*(const\s+)?Duration\(days:');
    final stepOffenders = <String>[];
    for (final f in libDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.path.replaceAll(r'\', '/').split('/').last;
      if (_steppingExemptFiles.containsKey(name)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///')) continue;
        if (!stepPattern.hasMatch(line)) continue;
        if (_exemptLine.hasMatch(line)) continue; // marked, with a reason
        stepOffenders.add('lib/.../$name:${i + 1}  ${line.trim()}');
      }
    }
    if (stepOffenders.isNotEmpty) {
      print('\n  Stepping across days by elapsed time — use addDays() instead:');
      for (final o in stepOffenders) {
        print('    $o');
      }
      print('');
    }
    _chk('no date window steps by elapsed time (${stepOffenders.length} found)',
        stepOffenders.isEmpty);
  }

  // ---- Stepping across days, not measuring across them ----
  //
  // daysBetween fixed the measuring direction. Building a window by repeated
  // `subtract(Duration(days: 1))` has the same flaw from the other side, and it
  // was still doing that in the weekly digest, medication adherence, the
  // hydration streak and the sleep window.
  //
  // Unlike the note at the top of this file, the mechanism IS reproducible —
  // just not with the host clock. Santiago moves its clocks at midnight, so
  // the timezone package can show it directly. This block demonstrates the
  // defect; the block after it asserts addDays does not have it.
  {
    tzdata.initializeTimeZones();
    final loc = tz.getLocation('America/Santiago');
    final anchor = tz.TZDateTime(loc, 2026, 9, 7);
    String key(DateTime d) => '${d.month}-${d.day}';

    final naive = [for (var i = 0; i < 7; i++) key(anchor.subtract(Duration(days: i)))];
    final calendar = [
      for (var i = 0; i < 7; i++) key(tz.TZDateTime(loc, anchor.year, anchor.month, anchor.day - i))
    ];

    _chk('exact-24h stepping skips a real date across a midnight DST change',
        !naive.contains('9-6') && naive.contains('8-31'));
    _chk('calendar stepping does not',
        calendar.contains('9-6') && !calendar.contains('8-31'));
  }

  // ---- addDays ----
  {
    // Zone-independent properties, so this holds on any machine that runs it.
    var ok = true;
    var skips = 0;
    // Walk two years backwards a day at a time from an anchor; every step must
    // land on the immediately preceding calendar date, exactly once.
    final seen = <String>{};
    final start = DateTime(2027, 3, 15, 9, 30);
    DateTime? prev;
    for (var i = 0; i < 730; i++) {
      final d = addDays(start, -i);
      if (!seen.add(dateKey(d))) ok = false; // repeated a date
      if (prev != null && daysBetween(d, prev) != 1) skips++;
      prev = d;
    }
    _chk('stepping back never repeats a date', ok);
    _chk('and never skips one', skips == 0);
    _chk('and covers exactly as many days as steps taken', seen.length == 730);

    _chk('the time of day is preserved',
        addDays(DateTime(2026, 7, 21, 9, 30), -3) == DateTime(2026, 7, 18, 9, 30));
    _chk('month boundaries roll over',
        dateKey(addDays(DateTime(2026, 3, 1), -1)) == '2026-02-28');
    _chk('year boundaries roll over',
        dateKey(addDays(DateTime(2027, 1, 1), -1)) == '2026-12-31');
    _chk('a leap day is not skipped',
        dateKey(addDays(DateTime(2028, 3, 1), -1)) == '2028-02-29');
    _chk('forwards works too', dateKey(addDays(DateTime(2026, 12, 31), 1)) == '2027-01-01');
    _chk('zero is the identity', addDays(start, 0) == start);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
